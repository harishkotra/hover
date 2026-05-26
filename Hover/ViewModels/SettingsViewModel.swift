//
//  SettingsViewModel.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Manages persisted model configuration, secure API key storage, and listener preferences.
//

import AppKit
import ApplicationServices
import Foundation

enum EndpointPreset: String, CaseIterable, Identifiable {
    case lmStudio
    case ollama
    case openAI
    case featherless
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .lmStudio:
            "LM Studio"
        case .ollama:
            "Ollama"
        case .openAI:
            "OpenAI"
        case .featherless:
            "Featherless"
        case .custom:
            "Compatible"
        }
    }

    var systemImage: String {
        switch self {
        case .lmStudio:
            "desktopcomputer"
        case .ollama:
            "terminal"
        case .openAI:
            "sparkles"
        case .featherless:
            "cloud"
        case .custom:
            "slider.horizontal.3"
        }
    }

    var baseURL: String {
        switch self {
        case .lmStudio:
            "http://localhost:1234/v1"
        case .ollama:
            "http://localhost:11434/v1"
        case .openAI:
            "https://api.openai.com/v1"
        case .featherless:
            "https://api.featherless.ai/v1"
        case .custom:
            "https://api.example.com/v1"
        }
    }

    var modelName: String {
        switch self {
        case .lmStudio, .featherless:
            "meta-llama-3-8b-instruct"
        case .ollama:
            "llama3.1"
        case .openAI:
            "gpt-4.1-mini"
        case .custom:
            "model-name"
        }
    }

    var usesAPIKey: Bool {
        switch self {
        case .openAI, .featherless, .custom:
            true
        case .lmStudio, .ollama:
            false
        }
    }

    var isLocal: Bool {
        switch self {
        case .lmStudio, .ollama:
            true
        case .openAI, .featherless, .custom:
            false
        }
    }

    static func inferred(from baseURLString: String) -> EndpointPreset? {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { preset in
            preset != .custom && preset.baseURL == trimmedURL
        }
    }
}

enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success(String)
    case failed(String)
}

@MainActor
final class SettingsViewModel: ObservableObject {
    private enum Defaults {
        static let systemPrompt = """
        You are Hover, a concise inline assistant. Use the user's request, selected text, and screen context to answer directly. Return only the useful response without prefacing it.
        """
    }

    private enum Keys {
        static let providerPreset = "Hover.providerPreset"
        static let baseURL = "Hover.baseURL"
        static let modelName = "Hover.modelName"
        static let systemPrompt = "Hover.systemPrompt"
        static let listenerEnabled = "Hover.listenerEnabled"
        static let tripleRightClickEnabled = "Hover.tripleRightClickEnabled"
        static let screenContextEnabled = "Hover.screenContextEnabled"
        static let screenshotContextEnabled = "Hover.screenshotContextEnabled"
        static let voiceInputEnabled = "Hover.voiceInputEnabled"
        static let onboardingCompleted = "Hover.onboardingCompleted"
        static let legacyAPIKeyAccount = "OpenAICompatibleAPIKey"
    }

    @Published private(set) var selectedPreset: EndpointPreset
    @Published private(set) var discoveredLocalProviders: [LocalModelProvider] = []
    @Published private(set) var isDiscoveringLocalModels = false
    @Published var baseURLString: String
    @Published var apiKey: String
    @Published var modelName: String
    @Published var systemPrompt: String
    @Published var statusMessage: String?
    @Published private(set) var connectionTestState: ConnectionTestState = .idle
    @Published var isOnboardingCompleted: Bool {
        didSet {
            userDefaults.set(isOnboardingCompleted, forKey: Keys.onboardingCompleted)
        }
    }
    @Published var isGlobalListenerEnabled: Bool {
        didSet {
            userDefaults.set(isGlobalListenerEnabled, forKey: Keys.listenerEnabled)
            onListenerPreferenceChanged?(isGlobalListenerEnabled)
        }
    }
    @Published var isTripleRightClickEnabled: Bool {
        didSet {
            userDefaults.set(isTripleRightClickEnabled, forKey: Keys.tripleRightClickEnabled)
            onTripleRightClickPreferenceChanged?(isTripleRightClickEnabled)
        }
    }
    @Published var isScreenContextEnabled: Bool {
        didSet {
            userDefaults.set(isScreenContextEnabled, forKey: Keys.screenContextEnabled)
        }
    }
    @Published var isScreenshotContextEnabled: Bool {
        didSet {
            userDefaults.set(isScreenshotContextEnabled, forKey: Keys.screenshotContextEnabled)
        }
    }
    @Published var isVoiceInputEnabled: Bool {
        didSet {
            userDefaults.set(isVoiceInputEnabled, forKey: Keys.voiceInputEnabled)
        }
    }

    var onListenerPreferenceChanged: ((Bool) -> Void)?
    var onTripleRightClickPreferenceChanged: ((Bool) -> Void)?

    var selectedProviderModelOptions: [String] {
        discoveredProvider(for: selectedPreset)?.models ?? []
    }

    var localDiscoverySummary: String {
        if isDiscoveringLocalModels {
            return "Looking for LM Studio and Ollama models..."
        }

        let detected = discoveredLocalProviders.filter { !$0.models.isEmpty }
        if !detected.isEmpty {
            return detected
                .map { "\($0.displayName): \($0.models.count) model\($0.models.count == 1 ? "" : "s")" }
                .joined(separator: "  •  ")
        }

        let installed = discoveredLocalProviders.filter(\.isInstalled)
        if !installed.isEmpty {
            return "\(installed.map(\.displayName).joined(separator: " and ")) installed, but no local model server responded."
        }

        return "No local model server detected. Start LM Studio or Ollama, then refresh."
    }

    var apiKeyHelperText: String {
        effectivePresetForCurrentBaseURL().usesAPIKey
            ? "Stored in a non-syncing macOS Keychain item for this provider."
            : "Local providers do not require a cloud API key."
    }

    var currentProviderRequiresAPIKey: Bool {
        effectivePresetForCurrentBaseURL().usesAPIKey
    }

    var currentProviderTitle: String {
        effectivePresetForCurrentBaseURL().title
    }

    private let keychainStore: KeychainStore
    private let userDefaults: UserDefaults
    private let modelDiscovery: LocalModelDiscovery
    private let healthCheckClient = LLMClient()
    private var displayedAPIKeyAccount: String

    init(
        keychainStore: KeychainStore,
        userDefaults: UserDefaults = .standard,
        modelDiscovery: LocalModelDiscovery = LocalModelDiscovery()
    ) {
        self.keychainStore = keychainStore
        self.userDefaults = userDefaults
        self.modelDiscovery = modelDiscovery

        let persistedBaseURL = userDefaults.string(forKey: Keys.baseURL)
        let initialBaseURL = persistedBaseURL ?? EndpointPreset.lmStudio.baseURL
        let persistedPreset = userDefaults.string(forKey: Keys.providerPreset).flatMap(EndpointPreset.init(rawValue:))
        let inferredPreset = EndpointPreset.inferred(from: initialBaseURL)
        let initialPreset = persistedPreset ?? inferredPreset ?? .lmStudio
        let initialAPIKeyAccount = Self.apiKeyAccount(for: initialPreset, baseURLString: initialBaseURL)

        self.selectedPreset = initialPreset
        self.baseURLString = initialBaseURL
        self.modelName = userDefaults.string(forKey: Keys.modelName) ?? initialPreset.modelName
        self.systemPrompt = userDefaults.string(forKey: Keys.systemPrompt) ?? Defaults.systemPrompt
        self.isGlobalListenerEnabled = userDefaults.object(forKey: Keys.listenerEnabled) as? Bool ?? true
        self.isTripleRightClickEnabled = userDefaults.object(forKey: Keys.tripleRightClickEnabled) as? Bool ?? true
        self.isScreenContextEnabled = userDefaults.object(forKey: Keys.screenContextEnabled) as? Bool ?? true
        self.isScreenshotContextEnabled = userDefaults.object(forKey: Keys.screenshotContextEnabled) as? Bool ?? true
        self.isVoiceInputEnabled = userDefaults.object(forKey: Keys.voiceInputEnabled) as? Bool ?? true
        self.isOnboardingCompleted = userDefaults.object(forKey: Keys.onboardingCompleted) as? Bool ?? false
        self.displayedAPIKeyAccount = initialAPIKeyAccount

        do {
            if initialPreset.usesAPIKey {
                self.apiKey = try keychainStore.readString(account: initialAPIKeyAccount)
                    ?? keychainStore.readString(account: Keys.legacyAPIKeyAccount)
                    ?? ""
            } else {
                self.apiKey = ""
            }
        } catch {
            self.apiKey = ""
            self.statusMessage = Self.message(for: error)
        }

        let shouldApplyDetectedDefault = persistedBaseURL == nil && persistedPreset == nil
        Task { [weak self] in
            await self?.refreshLocalModels(applyDefaultIfUnconfigured: shouldApplyDetectedDefault)
        }
    }

    func refreshLocalModels() async {
        await refreshLocalModels(applyDefaultIfUnconfigured: false)
    }

    func testConnection() async {
        guard connectionTestState != .testing else {
            return
        }

        do {
            // Reuse the production configuration builder so the health check validates
            // the exact endpoint, key, model, and transport rules used by Hover requests.
            connectionTestState = .testing
            let configuration = try makeConfiguration()
            let response = try await healthCheckClient.testConnection(configuration: configuration)
            connectionTestState = .success("Connected to \(currentProviderTitle). Model replied: \(response)")
            statusMessage = "Connection test passed."
        } catch {
            let message = Self.message(for: error)
            connectionTestState = .failed(message)
            statusMessage = message
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            _ = try makeConfiguration()
            selectedPreset = effectivePresetForCurrentBaseURL()

            persistNonSecretSettings()

            if selectedPreset.usesAPIKey {
                let account = Self.apiKeyAccount(for: selectedPreset, baseURLString: baseURLString)
                displayedAPIKeyAccount = account
                try keychainStore.saveString(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
            }

            statusMessage = "Settings saved."
            return true
        } catch {
            statusMessage = Self.message(for: error)
            return false
        }
    }

    func restoreDefaults() {
        applyBestLocalDefaultIfAvailable(persist: false)
        systemPrompt = Defaults.systemPrompt
        connectionTestState = .idle
        statusMessage = "Defaults restored. Save to persist them."
    }

    func applyPreset(_ preset: EndpointPreset) {
        saveCurrentAPIKeyBestEffort()

        selectedPreset = preset
        baseURLString = preset.baseURL
        modelName = discoveredProvider(for: preset)?.preferredModel ?? preset.modelName
        reloadAPIKeyForSelectedProvider()

        if preset.isLocal {
            apiKey = ""
        }

        statusMessage = "\(preset.title) preset applied. Save to persist it."
        connectionTestState = .idle
    }

    func baseURLDidChange() {
        let effectivePreset = effectivePresetForCurrentBaseURL()
        let effectiveAccount = Self.apiKeyAccount(for: effectivePreset, baseURLString: baseURLString)

        if effectivePreset != selectedPreset {
            selectedPreset = effectivePreset
        }

        connectionTestState = .idle

        guard effectiveAccount != displayedAPIKeyAccount else {
            if !effectivePreset.usesAPIKey {
                apiKey = ""
            }
            return
        }

        displayedAPIKeyAccount = effectiveAccount

        if effectivePreset == .openAI || effectivePreset == .featherless {
            reloadAPIKeyForSelectedProvider()
        } else {
            apiKey = ""
        }
    }

    func isCurrentPreset(_ preset: EndpointPreset) -> Bool {
        selectedPreset == preset
    }

    func makeConfiguration() throws -> LLMConfiguration {
        let baseURLText = trimmed(baseURLString)
        guard let baseURL = URL(string: baseURLText),
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host?.isEmpty == false else {
            throw SettingsValidationError.invalidBaseURL
        }

        let model = trimmed(modelName)
        guard !model.isEmpty else {
            throw SettingsValidationError.emptyModelName
        }

        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw SettingsValidationError.emptySystemPrompt
        }

        let effectivePreset = effectivePresetForCurrentBaseURL()
        let requestAPIKey = effectivePreset.usesAPIKey
            ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return LLMConfiguration(
            baseURL: baseURL,
            apiKey: requestAPIKey,
            modelName: model,
            systemPrompt: prompt
        )
    }

    func completeOnboarding() {
        isOnboardingCompleted = true
        statusMessage = "Setup complete."
    }

    func copyDiagnosticsToClipboard() {
        let diagnostics = diagnosticsReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        statusMessage = "Diagnostics copied."
    }

    func clearCurrentAPIKey() {
        let preset = effectivePresetForCurrentBaseURL()
        guard preset.usesAPIKey else {
            return
        }

        do {
            try keychainStore.deleteString(account: Self.apiKeyAccount(for: preset, baseURLString: baseURLString))
            apiKey = ""
            statusMessage = "API key cleared."
        } catch {
            statusMessage = Self.message(for: error)
        }
    }

    private func refreshLocalModels(applyDefaultIfUnconfigured: Bool) async {
        guard !isDiscoveringLocalModels else {
            return
        }

        isDiscoveringLocalModels = true
        defer {
            isDiscoveringLocalModels = false
        }

        let providers = await modelDiscovery.discoverLocalProviders()
        discoveredLocalProviders = providers

        if applyDefaultIfUnconfigured {
            applyBestLocalDefaultIfAvailable(persist: true)
        } else if providers.contains(where: { !$0.models.isEmpty }) {
            statusMessage = "Local models refreshed."
        }
    }

    private func applyBestLocalDefaultIfAvailable(persist: Bool) {
        guard let provider = preferredLocalProvider() else {
            selectedPreset = .lmStudio
            baseURLString = EndpointPreset.lmStudio.baseURL
            modelName = EndpointPreset.lmStudio.modelName
            apiKey = ""
            displayedAPIKeyAccount = Self.apiKeyAccount(for: .lmStudio, baseURLString: baseURLString)
            return
        }

        selectedPreset = provider.preset
        baseURLString = provider.baseURL
        modelName = provider.preferredModel ?? provider.preset.modelName
        apiKey = ""
        displayedAPIKeyAccount = Self.apiKeyAccount(for: provider.preset, baseURLString: provider.baseURL)
        statusMessage = "Detected \(provider.displayName). Using \(modelName) by default."

        if persist {
            persistNonSecretSettings()
        }
    }

    private func preferredLocalProvider() -> LocalModelProvider? {
        let preferenceOrder: [EndpointPreset] = [.lmStudio, .ollama]
        for preset in preferenceOrder {
            if let provider = discoveredProvider(for: preset), !provider.models.isEmpty {
                return provider
            }
        }

        return nil
    }

    private func discoveredProvider(for preset: EndpointPreset) -> LocalModelProvider? {
        discoveredLocalProviders.first { $0.preset == preset }
    }

    private func persistNonSecretSettings() {
        userDefaults.set(selectedPreset.rawValue, forKey: Keys.providerPreset)
        userDefaults.set(trimmed(baseURLString), forKey: Keys.baseURL)
        userDefaults.set(trimmed(modelName), forKey: Keys.modelName)
        userDefaults.set(systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.systemPrompt)
    }

    private func diagnosticsReport() -> String {
        // Diagnostics are intentionally operational only. They help debug setup without
        // copying prompts, responses, selected text, screenshots, transcripts, or API keys.
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let accessibility = AXIsProcessTrusted() ? "granted" : "not granted"
        let screenRecording = CGPreflightScreenCaptureAccess() ? "granted" : "not granted"

        return """
        Hover Diagnostics
        Version: \(version) (\(build))
        macOS: \(os)
        Provider: \(currentProviderTitle)
        Base URL host: \(URL(string: trimmed(baseURLString))?.host ?? "invalid")
        Model: \(trimmed(modelName))
        Listener enabled: \(isGlobalListenerEnabled)
        Triple right-click enabled: \(isTripleRightClickEnabled)
        Screen context enabled: \(isScreenContextEnabled)
        Screenshot context enabled: \(isScreenshotContextEnabled)
        Voice input enabled: \(isVoiceInputEnabled)
        Accessibility: \(accessibility)
        Screen Recording: \(screenRecording)
        API key included: no
        User content included: no
        """
    }

    private func reloadAPIKeyForSelectedProvider() {
        displayedAPIKeyAccount = Self.apiKeyAccount(for: selectedPreset, baseURLString: baseURLString)

        guard selectedPreset.usesAPIKey else {
            apiKey = ""
            return
        }

        do {
            let account = Self.apiKeyAccount(for: selectedPreset, baseURLString: baseURLString)
            displayedAPIKeyAccount = account
            apiKey = try keychainStore.readString(account: account) ?? ""
        } catch {
            apiKey = ""
            statusMessage = Self.message(for: error)
        }
    }

    private func saveCurrentAPIKeyBestEffort() {
        let effectivePreset = effectivePresetForCurrentBaseURL()
        guard effectivePreset.usesAPIKey else {
            return
        }

        let account = Self.apiKeyAccount(for: effectivePreset, baseURLString: baseURLString)
        try? keychainStore.saveString(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
    }

    private func effectivePresetForCurrentBaseURL() -> EndpointPreset {
        if let inferredPreset = EndpointPreset.inferred(from: baseURLString) {
            return inferredPreset
        }

        let currentBaseURL = trimmed(baseURLString)
        return currentBaseURL == selectedPreset.baseURL ? selectedPreset : .custom
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func apiKeyAccount(for preset: EndpointPreset, baseURLString: String) -> String {
        switch preset {
        case .openAI:
            "APIKey.openai"
        case .featherless:
            "APIKey.featherless"
        case .custom:
            customAPIKeyAccount(baseURLString: baseURLString)
        case .lmStudio:
            "APIKey.local.lmStudio"
        case .ollama:
            "APIKey.local.ollama"
        }
    }

    private static func customAPIKeyAccount(baseURLString: String) -> String {
        guard let host = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))?.host else {
            return "APIKey.custom.unknown"
        }

        let normalizedHost = host
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber || character == "." || character == "-"
            }

        return "APIKey.custom.\(normalizedHost.isEmpty ? "unknown" : normalizedHost)"
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }

        return error.localizedDescription
    }
}

enum SettingsValidationError: LocalizedError {
    case invalidBaseURL
    case emptyModelName
    case emptySystemPrompt

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter a valid HTTP or HTTPS base URL, for example http://localhost:1234/v1."
        case .emptyModelName:
            "Enter a model name."
        case .emptySystemPrompt:
            "Enter a system prompt."
        }
    }
}
