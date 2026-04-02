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
                .environmentObject(appState.aiProviderService)
                .preferredColorScheme(.dark)
                // Handle files opened directly (Files.app "Open In", AirDrop, document picker)
                .onOpenURL { url in
                    Task {
                        do {
                            _ = try await appState.mediaLibraryService.importMedia(from: url)
                            appState.selectedTab = .library
                        } catch {
                            print("[VoiceTok] onOpenURL import failed: \(error)")
                        }
                    }
                }
                // Process files deposited by the Share Extension when app comes to foreground
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    Task {
                        let n = await appState.mediaLibraryService.importFromSharedContainer()
                        if n > 0 { appState.selectedTab = .library }
                    }
                }
                // Also check the inbox on cold launch
                .task {
                    let n = await appState.mediaLibraryService.importFromSharedContainer()
                    if n > 0 { appState.selectedTab = .library }
                }
        }
    }
}
