// AIProvider.swift
// Multi-provider AI configuration system inspired by PaperTok Reader

import Foundation

// MARK: - Provider Type

enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case claude = "claude"
    case openai = "openai"
    case ollama = "ollama"
    case openaiCompatible = "openai_compatible"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama (Local)"
        case .openaiCompatible: return String(localized: "OpenAI Compatible")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com"
        case .ollama: return "http://localhost:11434"
        case .openaiCompatible: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-20250514"
        case .openai: return "gpt-4o-mini"
        case .ollama: return "llama3.2"
        case .openaiCompatible: return ""
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .claude, .openai, .openaiCompatible: return true
        case .ollama: return false
        }
    }

    var icon: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .openai: return "sparkles"
        case .ollama: return "desktopcomputer"
        case .openaiCompatible: return "server.rack"
        }
    }
}

// MARK: - Provider Model

struct AIProvider: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var type: AIProviderType
    var baseURL: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var systemPrompt: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    static func == (lhs: AIProvider, rhs: AIProvider) -> Bool {
        lhs.id == rhs.id
    }

    // API key stored separately in Keychain, keyed by provider id
    var keychainKey: String { "ai_provider_\(id.uuidString)" }

    static let defaultSystemPrompt = """
    You are VoiceTok AI, an intelligent assistant that helps users understand \
    and interact with media content through its transcript. You can answer \
    questions about the content, summarize sections, explain concepts mentioned, \
    identify key topics, and provide analysis. Always reference specific parts \
    of the transcript when relevant. Be concise but thorough.
    """
}

// MARK: - Built-in Providers

extension AIProvider {
    static let builtInClaude = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Claude",
        type: .claude,
        baseURL: AIProviderType.claude.defaultBaseURL,
        modelName: "claude-sonnet-4-20250514",
        temperature: 0.7,
        maxTokens: 2048,
        systemPrompt: defaultSystemPrompt,
        isBuiltIn: true,
        isEnabled: true,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )

    static let builtInOpenAI = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "OpenAI",
        type: .openai,
        baseURL: AIProviderType.openai.defaultBaseURL,
        modelName: "gpt-4o-mini",
        temperature: 0.7,
        maxTokens: 2048,
        systemPrompt: defaultSystemPrompt,
        isBuiltIn: true,
        isEnabled: true,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )

    static let builtInOllama = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Ollama",
        type: .ollama,
        baseURL: AIProviderType.ollama.defaultBaseURL,
        modelName: "llama3.2",
        temperature: 0.7,
        maxTokens: 2048,
        systemPrompt: defaultSystemPrompt,
        isBuiltIn: true,
        isEnabled: true,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )

    static let builtInProviders = [builtInClaude, builtInOpenAI, builtInOllama]
}

// MARK: - Provider Service (Persistence)

@MainActor
final class AIProviderService: ObservableObject {
    @Published var providers: [AIProvider] = []
    @Published var selectedProviderID: UUID?

    private let providersKey = "ai_providers_v1"
    private let selectedKey = "ai_selected_provider"

    var activeProvider: AIProvider? {
        if let id = selectedProviderID {
            return providers.first { $0.id == id && $0.isEnabled }
        }
        return providers.first { $0.isEnabled }
    }

    init() {
        load()
    }

    // MARK: - Load / Save

    func load() {
        if let data = UserDefaults.standard.data(forKey: providersKey),
           let saved = try? JSONDecoder().decode([AIProvider].self, from: data) {
            // Merge built-in providers (ensure they always exist)
            var merged = saved
            for builtIn in AIProvider.builtInProviders {
                if !merged.contains(where: { $0.id == builtIn.id }) {
                    merged.insert(builtIn, at: 0)
                }
            }
            providers = merged
        } else {
            providers = AIProvider.builtInProviders
        }

        if let idStr = UserDefaults.standard.string(forKey: selectedKey),
           let uuid = UUID(uuidString: idStr) {
            selectedProviderID = uuid
        } else {
            selectedProviderID = providers.first?.id
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: providersKey)
        }
        if let id = selectedProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: selectedKey)
        }
    }

    // MARK: - CRUD

    func addProvider(name: String, type: AIProviderType) -> AIProvider {
        let provider = AIProvider(
            id: UUID(),
            name: name,
            type: type,
            baseURL: type.defaultBaseURL,
            modelName: type.defaultModel,
            temperature: 0.7,
            maxTokens: 2048,
            systemPrompt: AIProvider.defaultSystemPrompt,
            isBuiltIn: false,
            isEnabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        providers.append(provider)
        save()
        return provider
    }

    func updateProvider(_ provider: AIProvider) {
        var updated = provider
        updated.updatedAt = Date()
        if let idx = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[idx] = updated
        }
        save()
    }

    func deleteProvider(_ provider: AIProvider) {
        guard !provider.isBuiltIn else { return }
        KeychainService.delete(key: provider.keychainKey)
        providers.removeAll { $0.id == provider.id }
        if selectedProviderID == provider.id {
            selectedProviderID = providers.first(where: { $0.isEnabled })?.id
        }
        save()
    }

    func selectProvider(_ provider: AIProvider) {
        selectedProviderID = provider.id
        save()
    }

    // MARK: - API Key Management (via Keychain)

    func apiKey(for provider: AIProvider) -> String {
        KeychainService.load(key: provider.keychainKey)
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        KeychainService.save(key: provider.keychainKey, value: key)
    }

    // MARK: - Migration from legacy settings

    func migrateFromLegacyIfNeeded() {
        let legacyKey = KeychainService.load(key: "api_key")
        guard !legacyKey.isEmpty else { return }

        let legacyProvider = UserDefaults.standard.string(forKey: "api_provider") ?? "claude"

        // Find matching built-in provider and save the key
        if let match = providers.first(where: { $0.type.rawValue == legacyProvider || $0.type.displayName == legacyProvider }) {
            if apiKey(for: match).isEmpty {
                setAPIKey(legacyKey, for: match)
            }

            // Migrate model name and base URL
            var updated = match
            if let model = UserDefaults.standard.string(forKey: "chat_model"), !model.isEmpty {
                updated.modelName = model
            }
            if let url = UserDefaults.standard.string(forKey: "api_base_url"), !url.isEmpty {
                updated.baseURL = url
            }
            updateProvider(updated)
            selectProvider(updated)
        }

        // Clear legacy keys
        KeychainService.delete(key: "api_key")
        UserDefaults.standard.removeObject(forKey: "api_provider")
        UserDefaults.standard.removeObject(forKey: "chat_model")
        UserDefaults.standard.removeObject(forKey: "api_base_url")
    }
}
