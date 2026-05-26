//
//  SettingsView.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Renders the native SwiftUI settings panel for local and OpenAI-compatible endpoints.
//

import AppKit
import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SettingsViewModel
    @State private var revealAPIKey = false
    @State private var isClosingAfterSave = false
    private let providerPrivacyLinks = [
        ProviderPrivacyLink(
            title: "OpenAI Privacy Policy",
            detail: "Remote API provider",
            urlString: "https://openai.com/policies/privacy-policy"
        ),
        ProviderPrivacyLink(
            title: "OpenAI API Data Controls",
            detail: "API retention and training controls",
            urlString: "https://developers.openai.com/api/docs/guides/your-data"
        ),
        ProviderPrivacyLink(
            title: "Featherless Privacy Policy",
            detail: "Remote API provider",
            urlString: "https://featherless.ai/legal/privacy-policy"
        ),
        ProviderPrivacyLink(
            title: "LM Studio App Privacy",
            detail: "Local model app",
            urlString: "https://lmstudio.ai/app-privacy"
        ),
        ProviderPrivacyLink(
            title: "Ollama Privacy Policy",
            detail: "Local and cloud model provider",
            urlString: "https://ollama.com/privacy"
        )
    ]
    private let permissionReasons = [
        PermissionReason(
            permission: "Accessibility",
            reason: "Lets Hover copy selected text and read focused UI text only when you trigger it.",
            systemImage: "text.viewfinder"
        ),
        PermissionReason(
            permission: "Input Monitoring",
            reason: "Lets Hover listen for Command-Shift-X and the optional triple right-click gesture.",
            systemImage: "keyboard"
        ),
        PermissionReason(
            permission: "Automation",
            reason: "Lets Hover ask the active app to perform the normal copy command for the current selection.",
            systemImage: "command"
        ),
        PermissionReason(
            permission: "Screen Recording",
            reason: "Used only when screen context is enabled so a vision model can understand what is visible.",
            systemImage: "rectangle.on.rectangle"
        ),
        PermissionReason(
            permission: "Microphone and Speech Recognition",
            reason: "Used only during push-to-talk voice input. Hover does not keep the microphone open in the background.",
            systemImage: "mic"
        ),
        PermissionReason(
            permission: "Local Network",
            reason: "Lets Hover detect and connect to local LM Studio or Ollama servers.",
            systemImage: "network"
        )
    ]

    var body: some View {
        ZStack {
            VisualEffectView(material: .windowBackground, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar

                Divider()
                    .opacity(0.55)

                TabView {
                    SettingsTabPage {
                        inferenceSection
                        promptSection
                    }
                    .tabItem {
                        Label("Inference", systemImage: "cpu")
                    }

                    SettingsTabPage {
                        triggersSection
                    }
                    .tabItem {
                        Label("Triggers", systemImage: "switch.2")
                    }

                    SettingsTabPage {
                        contextSection
                    }
                    .tabItem {
                        Label("Context", systemImage: "eye")
                    }

                    SettingsTabPage {
                        privacySection
                    }
                    .tabItem {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 10)

                Divider()
                    .opacity(0.55)

                footer
            }
        }
        .frame(width: 700, height: 700)
        .background(
            SettingsWindowAccessor { window in
                // SettingsLink opens the native Settings scene, but accessory apps do not
                // always activate above the foreground app. Raising the resolved NSWindow
                // keeps the native scene while making the result visible to users.
                SettingsWindowPresenter.bringSettingsWindowForward(window)
            }
        )
        .onChange(of: viewModel.baseURLString) { _, _ in
            viewModel.baseURLDidChange()
        }
    }

    private var titleBar: some View {
        HStack(spacing: 14) {
            Image("HoverLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.16), radius: 10, y: 3)
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hover")
                    .font(.system(size: 17, weight: .semibold))
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            StatusPill(
                title: viewModel.isGlobalListenerEnabled ? "Listener On" : "Listener Off",
                systemImage: viewModel.isGlobalListenerEnabled ? "checkmark.circle.fill" : "pause.circle.fill",
                color: viewModel.isGlobalListenerEnabled ? .green : .secondary
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var triggersSection: some View {
        SettingsSection(title: "Triggers", systemImage: "switch.2") {
            SettingsRow(title: "Global Listener", detail: "Command-Shift-X captures the current selection.") {
                Toggle("", isOn: $viewModel.isGlobalListenerEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(title: "Triple Right-Click", detail: "Three secondary clicks near the pointer opens Hover.") {
                Toggle("", isOn: $viewModel.isTripleRightClickEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(title: "Shortcut", detail: "Default global trigger.") {
                ShortcutPreview(keys: ["⌘", "⇧", "X"])
            }
        }
    }

    private var inferenceSection: some View {
        SettingsSection(title: "Inference", systemImage: "cpu") {
            SettingsRow(title: "Provider", detail: "Local providers are detected automatically.") {
                PresetPicker(viewModel: viewModel)
                    .frame(width: 438)
            }

            SettingsDivider()

            SettingsRow(title: "Local Models", detail: viewModel.localDiscoverySummary) {
                Button {
                    Task {
                        await viewModel.refreshLocalModels()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isDiscoveringLocalModels)
            }

            SettingsDivider()

            SettingsRow(title: "Base URL") {
                PremiumTextField(
                    prompt: "http://localhost:1234/v1",
                    text: $viewModel.baseURLString
                )
            }

            SettingsDivider()

            SettingsRow(title: "Model") {
                ModelField(viewModel: viewModel)
            }

            SettingsDivider()

            SettingsRow(title: "API Key", detail: viewModel.apiKeyHelperText) {
                if viewModel.currentProviderRequiresAPIKey {
                    HStack(spacing: 8) {
                        Group {
                            if revealAPIKey {
                                PremiumTextField(
                                    prompt: "Paste provider key",
                                    text: $viewModel.apiKey
                                )
                            } else {
                                PremiumSecureField(
                                    prompt: "Paste provider key",
                                    text: $viewModel.apiKey
                                )
                            }
                        }

                        Button {
                            revealAPIKey.toggle()
                        } label: {
                            Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .help(revealAPIKey ? "Hide API key" : "Reveal API key")

                        Button {
                            viewModel.clearCurrentAPIKey()
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear API key from Keychain")
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                        Text("No API key is stored or sent for \(viewModel.currentProviderTitle).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsDivider()

            SettingsRow(title: "Health Check", detail: "Verifies the endpoint, key, model, and streaming support.") {
                HStack(spacing: 10) {
                    ConnectionTestStatusView(state: viewModel.connectionTestState)

                    Button {
                        Task {
                            await viewModel.testConnection()
                        }
                    } label: {
                        Label("Test Connection", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(viewModel.connectionTestState == .testing)
                }
            }
        }
    }

    private var contextSection: some View {
        SettingsSection(title: "Context", systemImage: "eye") {
            SettingsRow(title: "Screen Context", detail: "Attach active app and focused UI text to each request.") {
                Toggle("", isOn: $viewModel.isScreenContextEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(title: "Screenshot Context", detail: "Send a compact screenshot only to vision-capable models.") {
                Toggle("", isOn: $viewModel.isScreenshotContextEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!viewModel.isScreenContextEnabled)
            }

            SettingsDivider()

            SettingsRow(title: "Voice Input", detail: "Push-to-talk transcription in the Hover panel.") {
                Toggle("", isOn: $viewModel.isVoiceInputEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var promptSection: some View {
        SettingsSection(title: "Prompt", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 8) {
                Text("System Prompt")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                TextEditor(text: $viewModel.systemPrompt)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 136)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.9), lineWidth: 1)
                    }
            }
            .padding(14)
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy", systemImage: "hand.raised") {
            VStack(alignment: .leading, spacing: 14) {
                PrivacyNoticeRow(
                    systemImage: "checkmark.shield",
                    title: "Hover does not track your work",
                    message: "Hover does not record, sell, or store your prompts, selected text, screen context, screenshots, voice input, model responses, or usage history. This app does not include first-party analytics or a Hover server that receives your requests."
                )

                Divider()

                PrivacyNoticeRow(
                    systemImage: "key",
                    title: "Secrets stay in macOS Keychain",
                    message: "External provider keys are saved in a non-syncing Keychain item that is available only on this Mac while the device is unlocked. Provider URLs, model names, and toggles are stored locally in app settings."
                )

                Divider()

                PrivacyNoticeRow(
                    systemImage: "doc.on.clipboard",
                    title: "Clipboard access is temporary",
                    message: "When you ask about selected text, Hover sends a normal Command-C to the active app, reads the copied text, and restores the previous pasteboard contents."
                )

                Divider()

                PrivacyNoticeRow(
                    systemImage: "arrow.up.right.circle",
                    title: "Remote providers are separate services",
                    message: "If you choose OpenAI, Featherless, or another remote OpenAI-compatible endpoint, Hover sends your prompt and any enabled context to that provider. Their privacy policy, account settings, retention rules, and terms control what happens next. Hover cannot control or take responsibility for third-party processing."
                )

                ProviderPolicyLinksView(links: providerPrivacyLinks)

                Divider()

                PermissionReasonList(reasons: permissionReasons)

                Divider()

                PrivacyNoticeRow(
                    systemImage: "exclamationmark.triangle",
                    title: "Use care with sensitive information",
                    message: "Hover only gathers context when you trigger it, but that context can include selected text, focused UI text, screenshots, or dictated prompts if those features are enabled. Prefer local LM Studio or Ollama for confidential work, disable screenshot context when it is not needed, and review AI answers before relying on them."
                )

                Divider()

                PrivacyNoticeRow(
                    systemImage: "slider.horizontal.3",
                    title: "You stay in control",
                    message: "You can turn off the listener, screen context, screenshot context, voice input, and right-click gesture here. macOS permissions can be revoked any time in System Settings > Privacy & Security."
                )

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    PrivacyNoticeRow(
                        systemImage: "stethoscope",
                        title: "Privacy-safe diagnostics",
                        message: "Copies app version, macOS version, provider type, settings toggles, and permission status. It never includes prompts, responses, screenshots, selected text, or API keys."
                    )

                    Button {
                        viewModel.copyDiagnosticsToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let statusMessage = viewModel.statusMessage {
                HStack(spacing: 7) {
                    Image(systemName: statusMessage == "Settings saved." ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(statusMessage == "Settings saved." ? .green : .secondary)
                    Text(statusMessage)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.restoreDefaults()
                isClosingAfterSave = false
            } label: {
                Label("Restore Defaults", systemImage: "arrow.counterclockwise")
            }
            .disabled(isClosingAfterSave)

            Button {
                guard !isClosingAfterSave else {
                    return
                }

                if viewModel.save() {
                    isClosingAfterSave = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 850_000_000)
                        dismiss()
                    }
                }
            } label: {
                Label(
                    isClosingAfterSave ? "Settings Saved" : "Save Changes",
                    systemImage: isClosingAfterSave ? "checkmark.circle.fill" : "checkmark"
                )
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(isClosingAfterSave)
        }
        .controlSize(.regular)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }
}

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onFinish: () -> Void
    @State private var step = 0
    @State private var permissionMessage: String?

    private let steps = ["Welcome", "Permissions", "Inference", "Ready"]

    var body: some View {
        ZStack {
            VisualEffectView(material: .windowBackground, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                onboardingHeader

                Divider()
                    .opacity(0.55)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(28)

                Divider()
                    .opacity(0.55)

                footer
            }
        }
        .frame(width: 720, height: 560)
    }

    private var onboardingHeader: some View {
        HStack(spacing: 12) {
            Image("HoverLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.16), radius: 10, y: 3)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Set Up Hover")
                    .font(.system(size: 20, weight: .semibold))
                Text("AI anywhere on your Mac, without accounts or cloud lock-in.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color(nsColor: .separatorColor))
                        .frame(width: index == step ? 22 : 8, height: 8)
                        .animation(.easeOut(duration: 0.16), value: step)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 16) {
                Text("Hover lives next to your cursor.")
                    .font(.system(size: 24, weight: .semibold))

                Text("Select text anywhere, press Command-Shift-X or triple right-click, choose an action, and put the result back into the app you were using.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: 540, alignment: .leading)

                OnboardingFeatureGrid(items: [
                    ("Local-first", "Use LM Studio or Ollama when privacy matters.", "desktopcomputer"),
                    ("Bring your own key", "OpenAI, Featherless, and compatible APIs are supported.", "key"),
                    ("No Hover cloud", "Hover does not run a backend for your prompts.", "lock.shield"),
                    ("Fast actions", "Explain, rewrite, summarize, translate, reply, and more.", "bolt")
                ])
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Permissions are requested only for features you choose.")
                    .font(.system(size: 19, weight: .semibold))

                Text("Hover does not watch your screen or listen to your microphone in the background. Context is gathered only after you trigger Hover.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                PermissionSetupRow(
                    title: "Accessibility and Input Monitoring",
                    detail: "Needed for the global shortcut, optional right-click trigger, and copying selected text.",
                    systemImage: "keyboard"
                ) {
                    GlobalTriggerManager.requestAccessibilityTrustIfNeeded()
                    permissionMessage = "macOS opened the permission prompt. Enable Hover in Privacy & Security, then return here."
                }

                PermissionSetupRow(
                    title: "Screen Recording",
                    detail: "Optional. Needed only if you enable screenshot context for vision-capable models.",
                    systemImage: "rectangle.on.rectangle"
                ) {
                    let granted = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
                    permissionMessage = granted
                        ? "Screen Recording permission is available."
                        : "Enable Screen Recording in System Settings > Privacy & Security if you want screenshot context."
                }

                PermissionSetupRow(
                    title: "Microphone and Speech Recognition",
                    detail: "Optional. Used only while push-to-talk voice input is active.",
                    systemImage: "mic"
                ) {
                    Task { @MainActor in
                        let granted = await SpeechTranscriptionService.requestPermissions()
                        permissionMessage = granted
                            ? "Voice input permissions are available."
                            : "Enable Microphone and Speech Recognition in Privacy & Security to use voice input."
                    }
                }

                if let permissionMessage {
                    Text(permissionMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        case 2:
            SettingsSection(title: "Choose Inference", systemImage: "cpu") {
                SettingsRow(title: "Provider", detail: "Local providers are detected automatically.") {
                    PresetPicker(viewModel: viewModel)
                        .frame(width: 438)
                }

                SettingsDivider()

                SettingsRow(title: "Base URL") {
                    PremiumTextField(
                        prompt: "http://localhost:1234/v1",
                        text: $viewModel.baseURLString
                    )
                }

                SettingsDivider()

                SettingsRow(title: "Model") {
                    ModelField(viewModel: viewModel)
                }

                SettingsDivider()

                SettingsRow(title: "API Key", detail: viewModel.apiKeyHelperText) {
                    if viewModel.currentProviderRequiresAPIKey {
                        PremiumSecureField(prompt: "Paste provider key", text: $viewModel.apiKey)
                    } else {
                        Text("No API key needed for \(viewModel.currentProviderTitle).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsDivider()

                SettingsRow(title: "Test") {
                    HStack(spacing: 10) {
                        ConnectionTestStatusView(state: viewModel.connectionTestState)
                        Button {
                            Task {
                                await viewModel.testConnection()
                            }
                        } label: {
                            Label("Test Connection", systemImage: "bolt.horizontal.circle")
                        }
                        .disabled(viewModel.connectionTestState == .testing)
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 16) {
                Text("You are ready to use Hover.")
                    .font(.system(size: 24, weight: .semibold))

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingChecklistItem(text: "Select text in any app, then press Command-Shift-X.")
                    OnboardingChecklistItem(text: "Choose Explain, Rewrite, Summarize, Reply, Translate, Fix grammar, or Ask.")
                    OnboardingChecklistItem(text: "Use Copy, Replace Selection, or Paste to Active App to finish the workflow.")
                    OnboardingChecklistItem(text: "Open Settings anytime from the menu bar to change provider, privacy, or trigger options.")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                onFinish()
            } label: {
                Text("Skip Setup")
            }

            Spacer(minLength: 0)

            Button {
                step = max(0, step - 1)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(step == 0)

            Button {
                if step >= steps.count - 1 {
                    viewModel.save()
                    onFinish()
                } else {
                    step += 1
                }
            } label: {
                Label(step >= steps.count - 1 ? "Finish Setup" : "Continue", systemImage: step >= steps.count - 1 ? "checkmark" : "chevron.right")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }
}

private struct ProviderPrivacyLink: Identifiable {
    let title: String
    let detail: String
    let urlString: String

    var id: String {
        title
    }

    var url: URL? {
        URL(string: urlString)
    }
}

private struct PermissionReason: Identifiable {
    let permission: String
    let reason: String
    let systemImage: String

    var id: String {
        permission
    }
}

private struct ConnectionTestStatusView: View {
    let state: ConnectionTestState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var label: String {
        switch state {
        case .idle:
            "Not tested"
        case .testing:
            "Testing..."
        case .success(let message):
            message
        case .failed(let message):
            message
        }
    }

    private var systemImage: String {
        switch state {
        case .idle:
            "circle"
        case .testing:
            "clock"
        case .success:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .idle:
            .secondary
        case .testing:
            .accentColor
        case .success:
            .green
        case .failed:
            .orange
        }
    }
}

private struct OnboardingFeatureGrid: View {
    let items: [(title: String, detail: String, systemImage: String)]
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(items, id: \.title) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)

                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))

                    Text(item.detail)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: 600)
    }
}

private struct PermissionSetupRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Open") {
                action()
            }
            .buttonStyle(.bordered)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        }
    }
}

private struct OnboardingChecklistItem: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
        }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveWindow(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveWindow(for: nsView, coordinator: context.coordinator)
    }

    private func resolveWindow(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            guard coordinator.resolvedWindow !== window else {
                return
            }

            coordinator.resolvedWindow = window
            onResolve(window)
        }
    }

    final class Coordinator {
        weak var resolvedWindow: NSWindow?
    }
}

private struct SettingsTabPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1)
            }
        }
    }
}

private struct PrivacyNoticeRow: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProviderPolicyLinksView: View {
    let links: [ProviderPrivacyLink]
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Provider policy links")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(links) { policy in
                    if let url = policy.url {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(policy.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(policy.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(policy.urlString)
                    }
                }
            }
        }
    }
}

private struct PermissionReasonList: View {
    let reasons: [PermissionReason]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Why Hover asks for permissions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(reasons) { reason in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: reason.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(reason.permission)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(reason.reason)
                                .font(.system(size: 11))
                                .lineSpacing(1.5)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 174, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 188)
    }
}

private struct PremiumTextField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(fieldBackground)
            .overlay(fieldStroke)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.86))
    }

    private var fieldStroke: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.85), lineWidth: 1)
    }
}

private struct PremiumSecureField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        SecureField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.86))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.85), lineWidth: 1)
            }
    }
}

private struct PresetPicker: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EndpointPreset.allCases) { preset in
                Button {
                    viewModel.applyPreset(preset)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preset.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(preset.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .background(background(for: preset))
                    .overlay(stroke(for: preset))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func background(for preset: EndpointPreset) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(viewModel.isCurrentPreset(preset) ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func stroke(for preset: EndpointPreset) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(
                viewModel.isCurrentPreset(preset)
                    ? Color.accentColor.opacity(0.45)
                    : Color(nsColor: .separatorColor).opacity(0.8),
                lineWidth: 1
            )
    }
}

private struct ModelField: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        let options = viewModel.selectedProviderModelOptions

        if options.isEmpty {
            PremiumTextField(
                prompt: viewModel.selectedPreset.modelName,
                text: $viewModel.modelName
            )
        } else {
            Picker("", selection: $viewModel.modelName) {
                ForEach(options, id: \.self) { model in
                    Text(model)
                        .tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct ShortcutPreview: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 28, minHeight: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.88))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.85), lineWidth: 1)
                    }
            }
        }
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}
