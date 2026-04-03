// ChatHistoryService.swift
// Manages conversation sessions — create, load, save, delete, list

import Foundation

// MARK: - Chat Session Model

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var mediaItemId: UUID?
    var providerName: String?
    var modelName: String?
    var createdAt: Date
    var updatedAt: Date
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        mediaItemId: UUID? = nil,
        providerName: String? = nil,
        modelName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.mediaItemId = mediaItemId
        self.providerName = providerName
        self.modelName = modelName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isCompleted = isCompleted
    }

    /// Auto-generate title from first user message
    var autoTitle: String {
        if let firstUser = messages.first(where: { $0.role == .user }) {
            let text = firstUser.content.prefix(50)
            return text.count < firstUser.content.count ? "\(text)..." : String(text)
        }
        return title
    }
}

// MARK: - ChatHistoryService

@MainActor
final class ChatHistoryService: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var activeSessionId: UUID?

    private let storageKey = "voicetok_chat_sessions"
    private let maxSessions = 100

    var activeSession: ChatSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    init() {
        loadSessions()
    }

    // MARK: - CRUD

    /// Create a new session, optionally linked to a media item
    @discardableResult
    func createSession(mediaItemId: UUID? = nil, transcript: Transcript? = nil, providerName: String? = nil, modelName: String? = nil) -> ChatSession {
        let session = ChatSession(
            mediaItemId: mediaItemId,
            providerName: providerName,
            modelName: modelName
        )
        sessions.insert(session, at: 0)
        activeSessionId = session.id
        enforceLimit()
        saveSessions()
        return session
    }

    /// Update a session (called after messages change)
    func updateSession(_ session: ChatSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var updated = session
        updated.updatedAt = Date()
        // Auto-title from first user message
        if updated.title == "New Chat" {
            updated.title = updated.autoTitle
        }
        sessions[idx] = updated
        saveSessions()
    }

    /// Delete a session
    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.first?.id
        }
        saveSessions()
    }

    /// Load a session by ID
    func loadSession(_ id: UUID) {
        activeSessionId = id
    }

    /// Get sessions filtered by media item
    func sessions(for mediaItemId: UUID) -> [ChatSession] {
        sessions.filter { $0.mediaItemId == mediaItemId }
    }

    /// Rename a session
    func renameSession(_ id: UUID, to title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = title
        saveSessions()
    }

    // MARK: - Persistence

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([ChatSession].self, from: data) else {
            return
        }
        sessions = loaded.sorted { $0.updatedAt > $1.updatedAt }
        activeSessionId = sessions.first?.id
    }

    private func enforceLimit() {
        while sessions.count > maxSessions {
            sessions.removeLast()
        }
    }
}
