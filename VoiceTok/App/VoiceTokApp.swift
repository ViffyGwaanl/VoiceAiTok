// VoiceTokApp.swift
// VoiceTok - AI-Powered Media Player with Transcription & Chat
// Combines VLCKit playback + WhisperKit transcription + AI conversation

import SwiftUI

@main
struct VoiceTokApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
