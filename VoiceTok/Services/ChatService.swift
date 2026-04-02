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
    struct Config {
        var apiProvider: APIProvider = .claude
        var apiKey: String = ""
        var baseURL: String = ""
        var modelName: String = "claude-sonnet-4-20250514"
        var maxTokens: Int = 2048
        var temperature: Double = 0.7
        var systemPrompt: String = """
        You are VoiceTok AI, an intelligent assistant that helps users understand \
        and interact with media content through its transcript. You can answer \
        questions about the content, summarize sections, explain concepts mentioned, \
        identify key topics, and provide analysis. Always reference specific parts \
        of the transcript when relevant. Be concise but thorough.
        """
    }

    enum APIProvider: String, CaseIterable {
        case claude = "Claude (Anthropic)"
        case openai = "OpenAI"
        case ollama = "Ollama (Local)"
    }

    var config = Config()
    private var transcript: Transcript?

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

    private func buildSystemContext(_ transcript: Transcript) -> String {
        var context = config.systemPrompt + "\n\n"
        context += "=== MEDIA TRANSCRIPT ===\n"

        if let lang = transcript.language {
            context += "Language: \(lang)\n\n"
        }

        for segment in transcript.segments {
            context += "[\(segment.formattedTimeRange)] \(segment.text)\n"
        }

        context += "\n=== END TRANSCRIPT ===\n"
        context += "\nFull text summary available. \(transcript.segments.count) segments, "
        context += "total length: \(TranscriptSegment.format(transcript.segments.last?.endTime ?? 0))"

        return context
    }

    // MARK: - Send Message
    func send(_ userMessage: String) async {
        let userMsg = ChatMessage(role: .user, content: userMessage)
        messages.append(userMsg)
        isGenerating = true
        currentStreamText = ""

        do {
            let response = try await callLLM(messages: messages)
            let assistantMsg = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMsg)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Sorry, I encountered an error: \(error.localizedDescription)"
            )
            messages.append(errorMsg)
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

    // MARK: - LLM API Call
    private func callLLM(messages: [ChatMessage]) async throws -> String {
        switch config.apiProvider {
        case .claude:
            return try await callClaude(messages: messages)
        case .openai:
            return try await callOpenAI(messages: messages)
        case .ollama:
            return try await callOllama(messages: messages)
        }
    }

    // MARK: - Claude API
    private func callClaude(messages: [ChatMessage]) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw ChatError.missingAPIKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Separate system message from conversation
        let systemContent = messages.first(where: { $0.role == .system })?.content ?? config.systemPrompt
        let conversationMessages = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": config.modelName,
            "max_tokens": config.maxTokens,
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
    private func callOpenAI(messages: [ChatMessage]) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw ChatError.missingAPIKey
        }

        let url = URL(string: "\(config.baseURL.isEmpty ? "https://api.openai.com" : config.baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": config.modelName,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
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
    private func callOllama(messages: [ChatMessage]) async throws -> String {
        let url = URL(string: "\(config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": config.modelName.isEmpty ? "llama3.2" : config.modelName,
            "messages": apiMessages,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = json?["message"] as? [String: Any]

        return message?["content"] as? String ?? "No response generated."
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
        case .missingAPIKey: return "API key not configured. Go to Settings to add your key."
        case .apiError(let msg): return msg
        }
    }
}
