// AIProviderDetailView.swift
// Per-provider settings: URL, model fetch/select, key test, parameters, system prompt
// Reads/writes directly from AIProviderService to avoid stale state.

import SwiftUI

struct AIProviderDetailView: View {
    let providerID: UUID

    @EnvironmentObject var providerService: AIProviderService
    @Environment(\.dismiss) var dismiss

    // Local editing state — synced from/to service
    @State private var name = ""
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var temperature: Double = 0.7
    @State private var topP: Double = 0.9
    @State private var maxTokens: Int = 2048
    @State private var systemPrompt = AIProvider.defaultSystemPrompt
    @State private var isEnabled = true

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

    private var provider: AIProvider? {
        providerService.providers.first { $0.id == providerID }
    }
    private var isSelected: Bool { providerService.selectedProviderID == providerID }

    var body: some View {
        Group {
            if let p = provider {
                formContent(p)
            } else {
                ContentUnavailableView("Provider Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear { loadFromService() }
    }

    // MARK: - Form

    @ViewBuilder
    private func formContent(_ p: AIProvider) -> some View {
        Form {
            // MARK: - Status
            Section {
                HStack {
                    Text("Type")
                    Spacer()
                    Label(p.type.displayName, systemImage: p.type.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Toggle("Enabled", isOn: $isEnabled)

                if isSelected {
                    Label("Active Provider", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        providerService.selectProvider(p)
                    } label: {
                        Label("Set as Default", systemImage: "checkmark.circle")
                    }
                }
            }

            // MARK: - Connection
            Section {
                if !p.isBuiltIn || p.type == .ollama {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text(baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Model selection: dropdown if cached, text field otherwise
                if cachedModels.isEmpty {
                    TextField("Model Name", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Picker("Model", selection: $modelName) {
                        ForEach(cachedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        if !cachedModels.contains(modelName) && !modelName.isEmpty {
                            Text(modelName + " (custom)").tag(modelName)
                        }
                    }
                    TextField("Or enter custom model", text: $modelName)
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
                            ProgressView().controlSize(.small)
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
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                    modelSuggestions(for: p.type)
                }
            }

            // MARK: - API Key
            if p.type.requiresAPIKey {
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

                    Button {
                        Task { await testKey() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().controlSize(.small)
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
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .foregroundStyle(.secondary).frame(width: 40)
                }
                Slider(value: $temperature, in: 0...2, step: 0.1).tint(.orange)

                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", topP))
                        .foregroundStyle(.secondary).frame(width: 40)
                }
                Slider(value: $topP, in: 0...1, step: 0.05).tint(.orange)

                HStack {
                    Text("Max Tokens")
                    Spacer()
                    TextField("", value: $maxTokens, format: .number)
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
                        Text(systemPrompt.prefix(80) + "...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Button("Reset to Default") {
                    systemPrompt = AIProvider.defaultSystemPrompt
                }
                .foregroundStyle(.orange)
            } header: {
                Label("System Prompt", systemImage: "text.quote")
            }

            // MARK: - Danger Zone
            if !p.isBuiltIn {
                Section {
                    Button("Delete Provider", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(p.isBuiltIn ? p.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !(provider?.isBuiltIn ?? true) {
                ToolbarItem(placement: .principal) {
                    TextField("Provider Name", text: $name)
                        .multilineTextAlignment(.center)
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { saveAndDismiss() }
                    .fontWeight(.semibold)
            }
        }
        .onDisappear { writeToService() }
        .confirmationDialog("Delete?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let p = provider { providerService.deleteProvider(p) }
                dismiss()
            }
        }
        .sheet(isPresented: $showSystemPromptEditor) {
            SystemPromptEditor(prompt: $systemPrompt)
        }
    }

    // MARK: - Model Suggestions

    @ViewBuilder
    private func modelSuggestions(for type: AIProviderType) -> some View {
        let models: [(String, String)] = {
            switch type {
            case .claude: return [("claude-sonnet-4-20250514","Sonnet 4"),("claude-opus-4-20250514","Opus 4"),("claude-haiku-4-5-20251001","Haiku 4.5")]
            case .openai: return [("gpt-4o-mini","4o Mini"),("gpt-4o","4o"),("o3-mini","o3 Mini")]
            case .ollama: return [("llama3.2","Llama 3.2"),("mistral","Mistral"),("qwen2.5","Qwen 2.5")]
            case .openaiCompatible: return []
            }
        }()

        if !models.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(models, id: \.0) { id, label in
                        Button(label) { modelName = id }
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(modelName == id ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15))
                            .foregroundStyle(modelName == id ? .orange : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Sync with Service

    private func loadFromService() {
        guard let p = provider else { return }
        name = p.name
        baseURL = p.baseURL
        modelName = p.modelName
        temperature = p.temperature
        topP = p.topP
        maxTokens = p.maxTokens
        systemPrompt = p.systemPrompt
        isEnabled = p.isEnabled
        apiKey = providerService.apiKey(for: p)
        cachedModels = providerService.getCachedModels(for: p)
    }

    private func writeToService() {
        guard var p = provider else { return }
        p.name = name
        p.baseURL = baseURL
        p.modelName = modelName
        p.temperature = temperature
        p.topP = topP
        p.maxTokens = maxTokens
        p.systemPrompt = systemPrompt
        p.isEnabled = isEnabled
        providerService.setAPIKey(apiKey, for: p)
        providerService.updateProvider(p)
    }

    // MARK: - Actions

    private func fetchModels() async {
        isFetchingModels = true
        fetchError = nil
        writeToService()

        do {
            guard let p = provider else { return }
            let models = try await providerService.fetchModels(for: p)
            cachedModels = models
            providerService.saveCachedModels(models, for: p)
        } catch {
            fetchError = error.localizedDescription
        }
        isFetchingModels = false
    }

    private func testKey() async {
        isTesting = true
        testResult = nil
        writeToService()

        do {
            guard let p = provider else { return }
            testResult = try await providerService.testAPIKey(for: p)
        } catch {
            testResult = false
        }
        isTesting = false
    }

    private func saveAndDismiss() {
        writeToService()
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
