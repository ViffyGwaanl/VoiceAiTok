// SettingsView.swift
// App settings: API keys, model selection, preferences

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @AppStorage("api_provider") private var apiProvider = "claude"
    @State private var apiKey = ""  // Loaded from Keychain, not UserDefaults
    @AppStorage("api_base_url") private var apiBaseURL = ""
    @AppStorage("chat_model") private var chatModel = "claude-sonnet-4-20250514"
    @AppStorage("whisper_model") private var whisperModel = "base"
    @AppStorage("auto_transcribe") private var autoTranscribe = false
    @AppStorage("word_timestamps") private var wordTimestamps = true
    @AppStorage("transcript_language") private var transcriptLanguage = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - AI Chat API
                Section {
                    Picker("Provider", selection: $apiProvider) {
                        ForEach(ChatService.APIProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.rawValue).tag(provider.rawValue)
                        }
                    }

                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if apiProvider == "openai" || apiProvider == "ollama" {
                        TextField("Base URL (optional)", text: $apiBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    TextField("Model Name", text: $chatModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                } header: {
                    Label("AI Chat API", systemImage: "brain")
                } footer: {
                    Text("Configure the LLM provider for transcript-based AI conversations. Claude, OpenAI, or local Ollama are supported.")
                }

                // MARK: - Whisper Transcription
                Section {
                    Picker("Model", selection: $whisperModel) {
                        ForEach(TranscriptionService.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    Toggle("Word-level Timestamps", isOn: $wordTimestamps)

                    Toggle("Auto-transcribe on Import", isOn: $autoTranscribe)

                    Picker("Language", selection: $transcriptLanguage) {
                        Text("Auto-detect").tag("")
                        ForEach(supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }

                } header: {
                    Label("WhisperKit Transcription", systemImage: "waveform")
                } footer: {
                    Text("Larger models are more accurate but slower. 'base' is recommended for most devices. 'large-v3' provides the best quality on newer iPhones/iPads.")
                }

                // MARK: - Playback
                Section {
                    NavigationLink("Audio & Video Settings") {
                        PlaybackSettingsView()
                    }
                } header: {
                    Label("Playback", systemImage: "play.circle")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Built with")
                        Spacer()
                        Text("VLCKit + WhisperKit")
                            .foregroundStyle(.secondary)
                    }

                    Link("WhisperKit on GitHub", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                    Link("VLC for iOS on GitHub", destination: URL(string: "https://github.com/videolan/vlc-ios")!)
                } header: {
                    Label("About VoiceTok", systemImage: "info.circle")
                }

                // MARK: - Data
                Section {
                    Button("Clear All Transcripts", role: .destructive) {
                        // Clear all transcripts from media items
                        for i in appState.mediaLibraryService.mediaItems.indices {
                            appState.mediaLibraryService.mediaItems[i].transcript = nil
                            appState.mediaLibraryService.mediaItems[i].chatHistory = nil
                        }
                    }

                    Button("Clear All Data", role: .destructive) {
                        appState.mediaLibraryService.mediaItems.removeAll()
                        UserDefaults.standard.removeObject(forKey: "voicetok_media_library")
                    }
                } header: {
                    Label("Data Management", systemImage: "externaldrive")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        applySettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                apiKey = KeychainService.load(key: "api_key")
            }
        }
    }

    private func applySettings() {
        // Save API key securely to Keychain
        KeychainService.save(key: "api_key", value: apiKey)

        // Apply chat settings
        if let provider = ChatService.APIProvider(rawValue: apiProvider) {
            appState.chatService.config.apiProvider = provider
        }
        appState.chatService.config.apiKey = apiKey
        appState.chatService.config.baseURL = apiBaseURL
        appState.chatService.config.modelName = chatModel

        // Apply transcription settings
        appState.transcriptionService.config.modelName = whisperModel
        appState.transcriptionService.config.wordTimestamps = wordTimestamps
        appState.transcriptionService.config.language = transcriptLanguage.isEmpty ? nil : transcriptLanguage
    }

    // MARK: - Languages
    struct LanguageItem {
        let code: String
        let name: String
    }

    let supportedLanguages: [LanguageItem] = [
        .init(code: "en", name: "English"),
        .init(code: "zh", name: "Chinese / 中文"),
        .init(code: "ja", name: "Japanese / 日本語"),
        .init(code: "ko", name: "Korean / 한국어"),
        .init(code: "es", name: "Spanish"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "ru", name: "Russian"),
        .init(code: "ar", name: "Arabic"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "it", name: "Italian"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "sv", name: "Swedish"),
        .init(code: "pl", name: "Polish"),
        .init(code: "tr", name: "Turkish"),
        .init(code: "th", name: "Thai"),
        .init(code: "vi", name: "Vietnamese"),
    ]
}

// MARK: - Playback Settings
struct PlaybackSettingsView: View {
    @AppStorage("continue_in_background") private var backgroundPlayback = true
    @AppStorage("default_playback_rate") private var defaultRate = 1.0
    @AppStorage("skip_interval") private var skipInterval = 15.0

    var body: some View {
        Form {
            Section("General") {
                Toggle("Background Playback", isOn: $backgroundPlayback)

                Picker("Default Speed", selection: $defaultRate) {
                    Text("0.5x").tag(0.5)
                    Text("0.75x").tag(0.75)
                    Text("1x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                    Text("2x").tag(2.0)
                }

                Picker("Skip Interval", selection: $skipInterval) {
                    Text("5 sec").tag(5.0)
                    Text("10 sec").tag(10.0)
                    Text("15 sec").tag(15.0)
                    Text("30 sec").tag(30.0)
                }
            }
        }
        .navigationTitle("Playback Settings")
    }
}
