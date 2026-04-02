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

    // MARK: - Flags
    @Published var isTranscribing = false
    @Published var whisperKitReady = false

    init() {
        // Load API key from Keychain
        let savedKey = KeychainService.load(key: "api_key")
        if !savedKey.isEmpty {
            chatService.config.apiKey = savedKey
        }

        Task {
            await prepareWhisperKit()
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
