// SettingsView.swift
// App settings: API keys, model selection, preferences

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var providerService: AIProviderService
    @Environment(\.dismiss) var dismiss

    @AppStorage("whisper_model") private var whisperModel = "base"
    @AppStorage("auto_transcribe") private var autoTranscribe = false
    @AppStorage("word_timestamps") private var wordTimestamps = true
    @AppStorage("transcript_language") private var transcriptLanguage = ""
    @State private var selectedProvider: TranscriptionProvider = .whisperKit
    @State private var openAITranscriptionKey: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - AI Chat API
                Section {
                    NavigationLink {
                        AIProviderListView()
                    } label: {
                        HStack {
                            Text("AI Providers")
                            Spacer()
                            if let active = providerService.activeProvider {
                                Text(active.name)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("AI Chat", systemImage: "brain")
                } footer: {
                    Text("Configure AI providers for transcript-based conversations. Supports Claude, OpenAI, Ollama, and custom OpenAI-compatible endpoints.")
                }

                // MARK: - Transcription
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(TranscriptionProvider.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Transcription", systemImage: "waveform")
                } footer: {
                    Text(selectedProvider.description)
                }

                // WhisperKit-specific settings
                if selectedProvider == .whisperKit {
                    Section("WhisperKit Model") {
                        NavigationLink {
                            ModelManagementView()
                        } label: {
                            HStack {
                                Text("Model")
                                Spacer()
                                Text(whisperModel)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle("Word-level Timestamps", isOn: $wordTimestamps)
                    }

                    // Downloaded models quick view
                    Section("Downloaded Models") {
                        let downloaded = appState.transcriptionService.localModelStates
                            .filter { $0.value == .downloaded }
                            .map(\.key)
                            .sorted()
                        if downloaded.isEmpty {
                            HStack {
                                Image(systemName: "arrow.down.circle.dotted")
                                    .foregroundStyle(.secondary)
                                Text("No models downloaded yet. Tap \"Model\" above to download.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(downloaded, id: \.self) { model in
                                HStack {
                                    Image(systemName: whisperModel == model
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(whisperModel == model ? .green : .secondary)
                                        .font(.subheadline)
                                    Text(model)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(TranscriptionService.estimatedSize(for: model))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    whisperModel = model
                                    appState.transcriptionService.config.modelName = model
                                }
                            }
                        }
                    }
                }

                // Apple Speech info
                if selectedProvider == .appleSpeech {
                    Section("Apple Speech") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("No download required — uses iOS built-in speech recognition.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // OpenAI API key for transcription
                if selectedProvider == .openAIAPI {
                    Section("OpenAI Whisper API") {
                        SecureField("API Key (sk-...)", text: $openAITranscriptionKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("Used for cloud-based audio transcription via OpenAI Whisper API.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Shared transcription settings
                Section("Transcription Options") {
                    Toggle("Auto-transcribe on Import", isOn: $autoTranscribe)

                    Picker("Language", selection: $transcriptLanguage) {
                        Text("Auto-detect").tag("")
                        ForEach(supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
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
            .onAppear { loadSettings() }
            .task {
                // Populate model download states so the Downloaded Models list shows correctly
                if appState.transcriptionService.availableModels.isEmpty {
                    appState.transcriptionService.availableModels = TranscriptionService.fallbackModels
                }
                await appState.transcriptionService.refreshLocalModelStates()
            }
        }
    }

    private func applySettings() {
        // Apply to service config
        appState.transcriptionService.config.provider = selectedProvider
        appState.transcriptionService.config.modelName = whisperModel
        appState.transcriptionService.config.wordTimestamps = wordTimestamps
        appState.transcriptionService.config.language = transcriptLanguage.isEmpty ? nil : transcriptLanguage
        appState.transcriptionService.config.openAIAPIKey = openAITranscriptionKey.isEmpty ? nil : openAITranscriptionKey

        // Persist to UserDefaults so AppState.syncPersistedSettings() picks them up on next launch
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "transcription_provider")
        UserDefaults.standard.set(openAITranscriptionKey, forKey: "openai_transcription_key")
    }

    private func loadSettings() {
        selectedProvider = appState.transcriptionService.config.provider
        openAITranscriptionKey = appState.transcriptionService.config.openAIAPIKey ?? ""
        // Pre-fill from existing OpenAI AI provider if transcription key is empty
        if openAITranscriptionKey.isEmpty,
           let openAI = providerService.providers.first(where: { $0.type == .openai }) {
            let key = providerService.apiKey(for: openAI)
            if !key.isEmpty { openAITranscriptionKey = key }
        }
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
