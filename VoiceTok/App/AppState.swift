// AppState.swift
// Global application state

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Navigation
    @Published var selectedTab: AppTab = .library
    @Published var activeMediaItem: MediaItem?

    // MARK: - Services
    let transcriptionService = TranscriptionService()
    let chatService = ChatService()
    let mediaLibraryService = MediaLibraryService()
    let aiProviderService = AIProviderService()

    // MARK: - Flags
    @Published var isTranscribing = false
    @Published var whisperKitReady = false

    init() {
        // Wire ChatService to AIProviderService
        chatService.providerService = aiProviderService

        // Migrate legacy single-provider settings if present
        aiProviderService.migrateFromLegacyIfNeeded()

        // Sync persisted settings → service config on launch
        syncPersistedSettings()

        Task {
            await prepareWhisperKit()
        }
    }

    /// Load @AppStorage-persisted values into service configs.
    /// This ensures settings survive app restarts without requiring
    /// the user to open Settings first.
    private func syncPersistedSettings() {
        let defaults = UserDefaults.standard

        // Transcription language
        let lang = defaults.string(forKey: "transcript_language") ?? ""
        transcriptionService.config.language = lang.isEmpty ? nil : lang

        // Transcription model
        let model = defaults.string(forKey: "whisper_model") ?? "base"
        transcriptionService.config.modelName = model

        // Word timestamps
        transcriptionService.config.wordTimestamps = defaults.object(forKey: "word_timestamps") as? Bool ?? true

        // Transcription provider (persisted as raw string)
        if let providerRaw = defaults.string(forKey: "transcription_provider"),
           let provider = TranscriptionProvider(rawValue: providerRaw) {
            transcriptionService.config.provider = provider
        }

        // OpenAI transcription API key
        if let key = defaults.string(forKey: "openai_transcription_key"), !key.isEmpty {
            transcriptionService.config.openAIAPIKey = key
        }
    }

    func prepareWhisperKit() async {
        do {
            try await transcriptionService.initialize()
            whisperKitReady = true
        } catch {
            print("[VoiceTok] WhisperKit initialization failed: \(error)")
        }
    }
}

enum AppTab: String, CaseIterable {
    case library = "Library"
    case player = "Player"
    case chat = "Chat"

    var icon: String {
        switch self {
        case .library: return "square.grid.2x2.fill"
        case .player: return "play.circle.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
}
