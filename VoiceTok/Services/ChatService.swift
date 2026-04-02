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

    // MARK: - Set Context
    func setTranscript(_ transcript: Transcript) {
        self.transcript = transcript
        messages = [
            ChatMessage(
                role: .system,
                content: buildSystemContext(transcript)
            )
        ]
    }

    private func buildSystemContext(_ transcript: Transcript, maxTokenEstimate: Int = 80_000) -> String {
        var context = effectiveConfig.systemPrompt + "\n\n"
        context += "=== MEDIA TRANSCRIPT ===\n"

        if let lang = transcript.language {
            context += "Language: \(lang)\n\n"
        }

        var tokenCount = context.count / 4 // rough estimate: ~4 chars per token
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
        isGenerating = true
        currentStreamText = ""

        // Add a placeholder assistant message for streaming
        let placeholderId = UUID()
        let placeholder = ChatMessage(id: placeholderId, role: .assistant, content: "")
        messages.append(placeholder)

        do {
            try await streamLLM(messages: messages) { [weak self] delta in
                guard let self else { return }
                self.currentStreamText += delta
                // Update the last message in place
                if let idx = self.messages.lastIndex(where: { $0.id == placeholderId }) {
                    self.messages[idx] = ChatMessage(
                        id: placeholderId,
                        role: .assistant,
                        content: self.currentStreamText,
                        timestamp: self.messages[idx].timestamp
                    )
                }
            }
        } catch {
            // If streaming fails, try non-streaming fallback
            do {
                let response = try await callLLM(messages: messages.filter { $0.id != placeholderId })
                if let idx = messages.lastIndex(where: { $0.id == placeholderId }) {
                    messages[idx] = ChatMessage(id: placeholderId, role: .assistant, content: response)
                }
            } catch {
                if let idx = messages.lastIndex(where: { $0.id == placeholderId }) {
                    messages[idx] = ChatMessage(
                        id: placeholderId, role: .assistant,
                        content: String(format: String(localized: "Sorry, I encountered an error: %@"), error.localizedDescription)
                    )
                }
            }
        }

        isGenerating = false
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
    private func streamLLM(messages: [ChatMessage], onDelta: @escaping (String) -> Void) async throws {
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
        guard !cfg.apiKey.isEmpty else {
            throw ChatError.missingAPIKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Separate system message from conversation
        let systemContent = messages.first(where: { $0.role == .system })?.content ?? cfg.systemPrompt
        let conversationMessages = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName,
            "max_tokens": cfg.maxTokens,
            "system": systemContent,
            "messages": conversationMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatError.apiError("Claude API error: \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String

        return text ?? "No response generated."
    }

    // MARK: - OpenAI API
    private func callOpenAI(messages: [ChatMessage], cfg: Config) async throws -> String {
        guard !cfg.apiKey.isEmpty else {
            throw ChatError.missingAPIKey
        }

        let base = cfg.baseURL.isEmpty ? "https://api.openai.com" : cfg.baseURL
        let url = URL(string: "\(base)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName,
            "max_tokens": cfg.maxTokens,
            "temperature": cfg.temperature,
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]

        return message?["content"] as? String ?? "No response generated."
    }

    // MARK: - Ollama (Local)
    private func callOllama(messages: [ChatMessage], cfg: Config) async throws -> String {
        let url = URL(string: "\(cfg.baseURL.isEmpty ? "http://localhost:11434" : cfg.baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": cfg.modelName.isEmpty ? "llama3.2" : cfg.modelName,
            "messages": apiMessages,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = json?["message"] as? [String: Any]

        return message?["content"] as? String ?? "No response generated."
    }

    // MARK: - Streaming: Claude
    private func streamClaude(messages: [ChatMessage], cfg: Config, onDelta: @escaping (String) -> Void) async throws {
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
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw ChatError.apiError("Claude streaming error: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // Claude SSE: content_block_delta events contain {"delta": {"text": "..."}}
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                await MainActor.run { onDelta(text) }
            }
        }
    }

    // MARK: - Streaming: OpenAI
    private func streamOpenAI(messages: [ChatMessage], cfg: Config, onDelta: @escaping (String) -> Void) async throws {
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

        let (bytes, _) = try await URLSession.shared.bytes(for: request)

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // OpenAI SSE: choices[0].delta.content
            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                await MainActor.run { onDelta(content) }
            }
        }
    }

    // MARK: - Streaming: Ollama
    private func streamOllama(messages: [ChatMessage], cfg: Config, onDelta: @escaping (String) -> Void) async throws {
        let url = URL(string: "\(cfg.baseURL.isEmpty ? "http://localhost:11434" : cfg.baseURL)/api/chat")!
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

        let (bytes, _) = try await URLSession.shared.bytes(for: request)

        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // Ollama streaming: each line is a JSON with message.content
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                await MainActor.run { onDelta(content) }
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
}

// MARK: - Errors
enum ChatError: LocalizedError {
    case missingAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return String(localized: "API key not configured. Go to Settings to add your key.")
        case .apiError(let msg): return msg
        }
    }
}
