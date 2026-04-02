// ContentView.swift
// Main container view with tab-based navigation

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // Library Tab
            LibraryView()
                .tabItem {
                    Label(LocalizedStringKey(AppTab.library.rawValue), systemImage: AppTab.library.icon)
                }
                .tag(AppTab.library)

            // Player Tab
            PlayerContainerView()
                .tabItem {
                    Label(LocalizedStringKey(AppTab.player.rawValue), systemImage: AppTab.player.icon)
                }
                .tag(AppTab.player)

            // Chat Tab
            ChatContainerView()
                .tabItem {
                    Label(LocalizedStringKey(AppTab.chat.rawValue), systemImage: AppTab.chat.icon)
                }
                .tag(AppTab.chat)
        }
        .tint(.orange)
    }
}

// MARK: - Player Container (passes dependencies)
struct PlayerContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let item = appState.activeMediaItem {
            PlayerView(
                mediaItem: item,
                transcriptionService: appState.transcriptionService,
                chatService: appState.chatService,
                mediaLibraryService: appState.mediaLibraryService
            )
        } else {
            EmptyPlayerView()
        }
    }
}

// MARK: - Chat Container
struct ChatContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.activeMediaItem?.transcript != nil {
            ChatView(chatService: appState.chatService)
        } else {
            EmptyChatView()
        }
    }
}

// MARK: - Empty States
struct EmptyPlayerView: View {
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "play.circle")
                    .font(.system(size: 80))
                    .foregroundStyle(.tertiary)
                Text("No Media Selected")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Import a video or audio file from\nthe Library tab to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("Player")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

struct EmptyChatView: View {
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 80))
                    .foregroundStyle(.tertiary)
                Text("No Transcript Available")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Transcribe a media file first, then\nyou can chat about its content with AI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("AI Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}
