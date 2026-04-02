// AIProviderDetailView.swift
// Per-provider settings: URL, model fetch/select, key test, parameters, system prompt

import SwiftUI

struct AIProviderDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var provider: AIProvider
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var showDeleteConfirm = false
    @State private var showSystemPromptEditor = false

    // Model fetching
    @State private var cachedModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?

    // API key testing
    @State private var isTesting = false
    @State private var testResult: Bool?

    private var service: AIProviderService { appState.aiProviderService }
    private var isSelected: Bool { service.selectedProviderID == provider.id }

    var body: some View {
        Form {
            // MARK: - Status
            Section {
                HStack {
                    Text("Type")
                    Spacer()
                    Label(provider.type.displayName, systemImage: provider.type.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Toggle("Enabled", isOn: $provider.isEnabled)

                if isSelected {
                    Label("Active Provider", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        service.selectProvider(provider)
                    } label: {
                        Label("Set as Default", systemImage: "checkmark.circle")
                    }
                }
            }

            // MARK: - Connection
            Section {
                if !provider.isBuiltIn || provider.type == .ollama {
                    TextField("Base URL", text: $provider.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text(provider.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Model selection: dropdown if cached, text field otherwise
                if cachedModels.isEmpty {
                    TextField("Model Name", text: $provider.modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Picker("Model", selection: $provider.modelName) {
                        ForEach(cachedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        if !cachedModels.contains(provider.modelName) && !provider.modelName.isEmpty {
                            Text(provider.modelName + " (custom)").tag(provider.modelName)
                        }
                    }

                    // Still allow manual input
                    TextField("Or enter custom model", text: $provider.modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption)
                }

                // Fetch Models button
                Button {
                    Task { await fetchModels() }
                } label: {
                    HStack {
                        if isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text("Fetch Models")
                        Spacer()
                        if !cachedModels.isEmpty {
                            Text("\(cachedModels.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isFetchingModels)

            } header: {
                Label("Connection", systemImage: "network")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = fetchError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    modelSuggestions
                }
            }

            // MARK: - API Key
            if provider.type.requiresAPIKey {
                Section {
                    HStack {
                        Group {
                            if showAPIKey {
                                TextField("API Key", text: $apiKey)
                            } else {
                                SecureField("API Key", text: $apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Test API Key
                    Button {
                        Task { await testKey() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.shield")
                            }
                            Text("Test API Key")
                            Spacer()
                            if let result = testResult {
                                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result ? .green : .red)
                            }
                        }
                    }
                    .disabled(isTesting || apiKey.isEmpty)

                } header: {
                    Label("Authentication", systemImage: "key")
                } footer: {
                    Text("API keys are stored securely in iOS Keychain and never synced.")
                }
            }

            // MARK: - Parameters
            Section {
                // Temperature
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", provider.temperature))
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }
                Slider(value: $provider.temperature, in: 0...2, step: 0.1)
                    .tint(.orange)

                // Top P
                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", provider.topP))
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }
                Slider(value: $provider.topP, in: 0...1, step: 0.05)
                    .tint(.orange)

                // Max Tokens
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    TextField("", value: $provider.maxTokens, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            } header: {
                Label("Parameters", systemImage: "slider.horizontal.3")
            } footer: {
                Text("Temperature controls randomness (0=focused, 2=creative). Top P controls diversity of token selection.")
            }

            // MARK: - System Prompt
            Section {
                Button {
                    showSystemPromptEditor = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                        Text(provider.systemPrompt.prefix(80) + "...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Button("Reset to Default") {
                    provider.systemPrompt = AIProvider.defaultSystemPrompt
                }
                .foregroundStyle(.orange)
            } header: {
                Label("System Prompt", systemImage: "text.quote")
            }

            // MARK: - Danger Zone
            if !provider.isBuiltIn {
                Section {
                    Button("Delete Provider", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(provider.isBuiltIn ? provider.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !provider.isBuiltIn {
                ToolbarItem(placement: .principal) {
                    TextField("Provider Name", text: $provider.name)
                        .multilineTextAlignment(.center)
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveAndDismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            apiKey = service.apiKey(for: provider)
            cachedModels = service.getCachedModels(for: provider)
        }
        .onDisappear {
            saveProvider()
        }
        .confirmationDialog("Delete \(provider.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                service.deleteProvider(provider)
                dismiss()
            }
        }
        .sheet(isPresented: $showSystemPromptEditor) {
            SystemPromptEditor(prompt: $provider.systemPrompt)
        }
    }

    // MARK: - Model Suggestions (quick presets)

    @ViewBuilder
    private var modelSuggestions: some View {
        let models: [(String, String)] = {
            switch provider.type {
            case .claude:
                return [
                    ("claude-sonnet-4-20250514", "Sonnet 4"),
                    ("claude-opus-4-20250514", "Opus 4"),
                    ("claude-haiku-4-5-20251001", "Haiku 4.5")
                ]
            case .openai:
                return [
                    ("gpt-4o-mini", "4o Mini"),
                    ("gpt-4o", "4o"),
                    ("o3-mini", "o3 Mini")
                ]
            case .ollama:
                return [
                    ("llama3.2", "Llama 3.2"),
                    ("mistral", "Mistral"),
                    ("qwen2.5", "Qwen 2.5")
                ]
            case .openaiCompatible:
                return []
            }
        }()

        if !models.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(models, id: \.0) { id, label in
                        Button(label) {
                            provider.modelName = id
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(provider.modelName == id ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15))
                        .foregroundStyle(provider.modelName == id ? .orange : .primary)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func fetchModels() async {
        isFetchingModels = true
        fetchError = nil
        // Save key first so fetch can use it
        service.setAPIKey(apiKey, for: provider)
        service.updateProvider(provider)

        do {
            let models = try await service.fetchModels(for: provider)
            cachedModels = models
            service.saveCachedModels(models, for: provider)
        } catch {
            fetchError = error.localizedDescription
        }
        isFetchingModels = false
    }

    private func testKey() async {
        isTesting = true
        testResult = nil
        service.setAPIKey(apiKey, for: provider)
        service.updateProvider(provider)

        do {
            testResult = try await service.testAPIKey(for: provider)
        } catch {
            testResult = false
        }
        isTesting = false
    }

    private func saveProvider() {
        service.setAPIKey(apiKey, for: provider)
        service.updateProvider(provider)
    }

    private func saveAndDismiss() {
        saveProvider()
        dismiss()
    }
}

// MARK: - System Prompt Editor

struct SystemPromptEditor: View {
    @Binding var prompt: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $prompt)
                .font(.body)
                .padding()
                .navigationTitle("System Prompt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}
