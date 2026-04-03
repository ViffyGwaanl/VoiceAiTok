// ChatService.swift
// AI conversation service that uses transcripts as context
// Supports multiple LLM backends: Claude API, OpenAI, local LLM

import Foundation

@MainActor
final class ChatService: ObservableObject {
    // MARK: - Published State
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var currentStreamText = ""
    private var streamingTask: Task<Void, Never>?

    /// History service for multi-session persistence
    weak var historyService: ChatHistoryService?
    private var currentSessionId: UUID?

    // MARK: - Configuration

    /// Legacy config — now reads from AIProviderService.activeProvider
    struct Config {
        var apiProvider: AIProviderType = .claude
        var apiKey: String = ""
        var baseURL: String = ""
        var modelName: String = "claude-sonnet-4-20250514"
        var maxTokens: Int = 2048
        var temperature: Double = 0.7
        var topP: Double = 0.9
        var systemPrompt: String = AIProvider.defaultSystemPrompt
    }

    var config = Config()
    weak var providerService: AIProviderService?
    private var transcript: Transcript?

    /// Resolve effective config from active provider
    private var effectiveConfig: Config {
        guard let service = providerService, let provider = service.activeProvider else {
            return config
        }
        return Config(
            apiProvider: provider.type,
            apiKey: service.apiKey(for: provider),
            baseURL: provider.baseURL,
            modelName: provider.modelName,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature,
            topP: provider.topP,
            systemPrompt: provider.systemPrompt
        )
    }

    /// Whether an active provider with API key is configured
    var hasConfiguredProvider: Bool {
        guard let service = providerService, let provider = service.activeProvider else {
            return false
        }
        // Ollama doesn't need an API key
        if provider.type == .ollama { return true }
        return !service.apiKey(for: provider).isEmpty
    }

    // MARK: - Session Management

    /// Start a new session, optionally with a transcript context
    func startNewSession(transcript: Transcript? = nil, mediaItemId: UUID? = nil) {
        stopGeneration()
        self.transcript = transcript
        currentStreamText = ""

        if let transcript {
            messages = [ChatMessage(role: .system, content: buildSystemContext(transcript))]
        } else {
            messages = []
        }

        // Create a session in history
        let provName = providerService?.activeProvider?.name
        let modName = providerService?.activeProvider?.modelName
        if let history = historyService {
            let session = history.createSession(
                mediaItemId: mediaItemId,
                transcript: transcript,
                providerName: provName,
                modelName: modName
            )
            currentSessionId = session.id
        }
    }

    /// Load an existing session from history
    func loadSession(_ session: ChatSession) {
        stopGeneration()
        currentStreamText = ""
        messages = session.messages
        currentSessionId = session.id
        historyService?.loadSession(session.id)
    }

    /// Persist current messages to the active session
    func saveCurrentSession() {
        guard let id = currentSessionId,
              var session = historyService?.activeSession ?? historyService?.sessions.first(where: { $0.id == id }) else { return }
        session.messages = messages
        session.isCompleted = !isGenerating
        historyService?.updateSession(session)
    }

    // MARK: - Set Context (legacy — creates session if none)
    func setTranscript(_ transcript: Transcript) {
        self.transcript = transcript
        messages = [
            ChatMessage(
                role: .system,
                content: buildSystemContext(transcript)
            )
        ]
    }

    // MARK: - Edit Message
    /// Edit a user message at the given index and regenerate from there
    func editMessage(at messageId: UUID, newContent: String) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].role == .user else { return }

        // Replace the user message content
        messages[idx] = ChatMessage(
            id: messages[idx].id,
            role: .user,
            content: newContent,
            timestamp: messages[idx].timestamp
        )

        // Remove all messages after this user message
        let removeFrom = idx + 1
        if removeFrom < messages.count {
            messages.removeSubrange(removeFrom...)
        }

        // Regenerate from the edited message
        await runStreaming()
    }

    /// Regenerate from a specific user message (discards everything after it)
    func regenerateFrom(messageId: UUID) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else {
            // If it's an assistant message, find the preceding user message
            if let aIdx = messages.firstIndex(where: { $0.id == messageId }),
               messages[aIdx].role == .assistant {
                // Remove from this assistant message onwards
                messages.removeSubrange(aIdx...)
                await runStreaming()
            }
            return
        }

        // Remove everything after this message
        let removeFrom = idx + 1
        if removeFrom < messages.count {
            messages.removeSubrange(removeFrom...)
        }

        // If this is a user message, regenerate response
        if messages[idx].role == .user {
            await runStreaming()
        }
    }

    private func buildSystemContext(_ transcript: Transcript, maxTokenEstimate: Int = 80_000) -> String {
        var context = effectiveConfig.systemPrompt + "\n\n"
        context += "=== MEDIA TRANSCRIPT ===\n"

        if let lang = transcript.language {
            context += "Language: \(lang)\n\n"
        }

        var tokenCount = context.count / 4
        var truncated = false

        for (index, segment) in transcript.segments.enumerated() {
            let segmentLine = "[\(segment.formattedTimeRange)] \(segment.text)\n"
            let segmentTokens = segmentLine.count / 4

            if tokenCount + segmentTokens > maxTokenEstimate {
                let remaining = transcript.segments.count - index
                context += "\n[... transcript truncated for context limit. "
                context += "\(remaining) of \(transcript.segments.count) segments omitted. "
                context += "Total duration: \(TranscriptSegment.format(transcript.segments.last?.endTime ?? 0)) ...]\n"
                truncated = true
                break
            }

            context += segmentLine
            tokenCount += segmentTokens
        }

        context += "\n=== END TRANSCRIPT ===\n"
        context += "\n\(transcript.segments.count) segments, "
        context += "total length: \(TranscriptSegment.format(transcript.segments.last?.endTime ?? 0))"
        if truncated {
            context += " (transcript was truncated to fit context window)"
        }

        return context
    }

    // MARK: - Send Message (with streaming)
    func send(_ userMessage: String) async {
        let userMsg = ChatMessage(role: .user, content: userMessage)
        messages.append(userMsg)
        saveCurrentSession()
        await runStreaming()
    }

    /// Stop in-progress generation
    func stopGeneration() {
        streamingTask?.cancel()
        streamingTask = nil
        isGenerating = false
    }

    /// Regenerate the last AI response
    func regenerate() async {
        if let lastAssistant = messages.last, lastAssistant.role == .assistant {
            messages.removeLast()
        }
        await runStreaming()
    }

    private func runStreaming() async {
        isGenerating = true
        currentStreamText = ""

        // Pre-flight check: is provider configured?
        let cfg = effectiveConfig
        if cfg.apiKey.isEmpty && cfg.apiProvider != .ollama {
            let errMsg = ChatMessage(
                role: .assistant,
                content: String(localized: "⚠️ No API key configured. Go to Settings → AI Providers to add your key.")
            )
            messages.append(errMsg)
            isGenerating = false
            return
        }

        let placeholderId = UUID()
        let placeholder = ChatMessage(id: placeholderId, role: .assistant, content: "")
        messages.append(placeholder)

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                // Build messages WITHOUT the empty placeholder for the API call
                let apiMessages = self.messages.filter { $0.id != placeholderId }
                try await self.streamLLM(messages: apiMessages) { [weak self] delta in
                    guard let self else { return }
                    try Task.checkCancellation()
                    self.currentStreamText += delta
                    if let idx = self.messages.lastIndex(where: { $0.id == placeholderId }) {
                        self.messages[idx] = ChatMessage(
                            id: placeholderId, role: .assistant,
                            content: self.currentStreamText,
                            timestamp: self.messages[idx].timestamp
                        )
                    }
                }
            } catch is CancellationError {
                // Stopped by user — keep partial response
            } catch {
                // Streaming failed — try non-streaming fallback
                do {
                    let apiMessages = self.messages.filter { $0.id != placeholderId }
                    let response = try await self.callLLM(messages: apiMessages)
                    if let idx = self.messages.lastIndex(where: { $0.id == placeholderId }) {
                        self.messages[idx] = ChatMessage(id: placeholderId, role: .assistant, content: response)
                    }
                } catch {
                    let errorText = Self.friendlyError(error)
                    if let idx = self.messages.lastIndex(where: { $0.id == placeholderId }) {
                        self.messages[idx] = ChatMessage(id: placeholderId, role: .assistant, content: errorText)
                    }
                }
            }
            await MainActor.run {
                self.isGenerating = false
                self.saveCurrentSession()
            }
        }

        await streamingTask?.value
    }

    /// Map errors to user-friendly messages
    private static func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("401") || msg.contains("unauthorized") || msg.contains("auth") {
            return String(localized: "⚠️ Authentication failed — please verify your API key in Settings → AI Providers.")
        }
        if msg.contains("429") || msg.contains("rate limit") {
            return String(localized: "⚠️ Rate limit reached. Please wait a moment and try again.")
        }
        if msg.contains("404") || msg.contains("not found") {
            return String(localized: "⚠️ Model not found. Check the model name in Settings → AI Providers.")
        }
        if msg.contains("timeout") {
            return String(localized: "⚠️ Request timed out. Check your network connection.")
        }
        if msg.contains("network") || msg.contains("offline") || msg.contains("internet") {
            return String(localized: "⚠️ Network error. Check your internet connection.")
        }
        return "⚠️ \(error.localizedDescription)"
    }

    // MARK: - Quick Actions
    func summarize() async {
        await send("Please provide a comprehensive summary of this media content, highlighting the main topics and key points discussed.")
    }

    func extractKeyTopics() async {
        await send("What are the main topics and themes discussed in this content? List them with brief descriptions.")
    }

    func generateNotes() async {
        await send("Create structured study notes from this transcript with headings, bullet points, and key takeaways.")
    }

    func translateSummary(to language: String) async {
        await send("Please summarize the main content and translate the summary to \(language).")
    }

    // MARK: - Streaming LLM Call
    private func streamLLM(messages: [ChatMessage], onDelta: @escaping (String) throws -> Void) async throws {
        let cfg = effectiveConfig
        switch cfg.apiProvider {
        case .claude:
            try await streamClaude(messages: messages, cfg: cfg, onDelta: onDelta)
        case .openai, .openaiCompatible:
            try await streamOpenAI(messages: messages, cfg: cfg, onDelta: onDelta)
        case .ollama:
            try await streamOllama(messages: messages, cfg: cfg, onDelta: onDelta)
        }
    }

    // MARK: - LLM API Call (non-streaming fallback)
    private func callLLM(messages: [ChatMessage]) async throws -> String {
        let cfg = effectiveConfig
        switch cfg.apiProvider {
        case .claude:
            return try await callClaude(messages: messages, cfg: cfg)
        case .openai, .openaiCompatible:
            return try await callOpenAI(messages: messages, cfg: cfg)
        case .ollama:
            return try await callOllama(messages: messages, cfg: cfg)
        }
    }

    // MARK: - Claude API
    private func callClaude(messages: [ChatMessage], cfg: Config) async throws -> String {
        guard !cfg.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let base = cfg.baseURL.isEmpty ? "https://api.anthropic.com" : cfg.baseURL
        let url = URL(string: "\(base)/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let systemContent = messages.first(where: { $0.role == .system })?.content ?? cfg.systemPrompt
        let conversationMessages = messages
            .filter { $0.role != .system && !$0.content.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName,
            "max_tokens": cfg.maxTokens,
            "system": systemContent,
            "messages": conversationMessages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTPResponse(response, data: data, provider: "Claude")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? "No response generated."
    }

    // MARK: - OpenAI API
    private func callOpenAI(messages: [ChatMessage], cfg: Config) async throws -> String {
        guard !cfg.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let base = cfg.baseURL.isEmpty ? "https://api.openai.com" : cfg.baseURL
        let url = URL(string: "\(base)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")

        let apiMessages = messages
            .filter { !$0.content.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName,
            "max_tokens": cfg.maxTokens,
            "temperature": cfg.temperature,
            "messages": apiMessages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTPResponse(response, data: data, provider: "OpenAI")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? "No response generated."
    }

    // MARK: - Ollama (Local)
    private func callOllama(messages: [ChatMessage], cfg: Config) async throws -> String {
        let base = cfg.baseURL.isEmpty ? "http://localhost:11434" : cfg.baseURL
        let url = URL(string: "\(base)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiMessages = messages
            .filter { !$0.content.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName.isEmpty ? "llama3.2" : cfg.modelName,
            "messages": apiMessages,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTPResponse(response, data: data, provider: "Ollama")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = json?["message"] as? [String: Any]
        return message?["content"] as? String ?? "No response generated."
    }

    // MARK: - Streaming: Claude
    private func streamClaude(messages: [ChatMessage], cfg: Config, onDelta: @escaping (String) throws -> Void) async throws {
        guard !cfg.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let base = cfg.baseURL.isEmpty ? "https://api.anthropic.com" : cfg.baseURL
        let url = URL(string: "\(base)/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let systemContent = messages.first(where: { $0.role == .system })?.content ?? cfg.systemPrompt
        let conversationMessages = messages
            .filter { $0.role != .system && !$0.content.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName,
            "max_tokens": cfg.maxTokens,
            "system": systemContent,
            "messages": conversationMessages,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatError.apiError("Claude: invalid response")
        }
        guard 200..<300 ~= http.statusCode else {
            // Read the error body from the stream
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line; if errorBody.count > 500 { break } }
            throw ChatError.apiError("Claude HTTP \(http.statusCode): \(Self.extractAPIError(errorBody))")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                try await MainActor.run { try onDelta(text) }
            }
        }
    }

    // MARK: - Streaming: OpenAI
    private func streamOpenAI(messages: [ChatMessage], cfg: Config, onDelta: @escaping (String) throws -> Void) async throws {
        guard !cfg.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let base = cfg.baseURL.isEmpty ? "https://api.openai.com" : cfg.baseURL
        let url = URL(string: "\(base)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")

        let apiMessages = messages
            .filter { !$0.content.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName,
            "max_tokens": cfg.maxTokens,
            "temperature": cfg.temperature,
            "messages": apiMessages,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatError.apiError("OpenAI: invalid response")
        }
        guard 200..<300 ~= http.statusCode else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line; if errorBody.count > 500 { break } }
            throw ChatError.apiError("OpenAI HTTP \(http.statusCode): \(Self.extractAPIError(errorBody))")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                try await MainActor.run { try onDelta(content) }
            }
        }
    }

    // MARK: - Streaming: Ollama
    private func streamOllama(messages: [ChatMessage], cfg: Config, onDelta: @escaping (String) throws -> Void) async throws {
        let base = cfg.baseURL.isEmpty ? "http://localhost:11434" : cfg.baseURL
        let url = URL(string: "\(base)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiMessages = messages
            .filter { !$0.content.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName.isEmpty ? "llama3.2" : cfg.modelName,
            "messages": apiMessages,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line; if errorBody.count > 500 { break } }
            throw ChatError.apiError("Ollama HTTP \(http.statusCode): \(Self.extractAPIError(errorBody))")
        }

        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                try await MainActor.run { try onDelta(content) }
            }
        }
    }

    // MARK: - Clear
    func clearHistory() {
        if let transcript = transcript {
            messages = [ChatMessage(role: .system, content: buildSystemContext(transcript))]
        } else {
            messages = []
        }
    }

    // MARK: - HTTP Helpers

    /// Check non-streaming HTTP response and throw with meaningful error
    private static func checkHTTPResponse(_ response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ChatError.apiError("\(provider): invalid response")
        }
        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ChatError.apiError("\(provider) HTTP \(http.statusCode): \(extractAPIError(body))")
        }
    }

    /// Extract human-readable error from JSON API response body
    private static func extractAPIError(_ body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // OpenAI/Ollama: { "error": { "message": "..." } }
            if let errorObj = json["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                return msg
            }
            // Claude: { "error": { "message": "..." } }
            if let errorObj = json["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                return msg
            }
            // Simple: { "error": "..." }
            if let msg = json["error"] as? String {
                return msg
            }
        }
        // Truncate raw body for display
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown error" : String(trimmed.prefix(200))
    }
}

// MARK: - Errors
enum ChatError: LocalizedError {
    case missingAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return String(localized: "API key not configured. Go to Settings → AI Providers to add your key.")
        case .apiError(let msg): return msg
        }
    }
}
