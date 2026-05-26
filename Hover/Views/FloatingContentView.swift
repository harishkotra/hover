//
//  FloatingContentView.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Renders the premium floating response panel with loading, streaming, copy, and dismiss states.
//

import AppKit
import SwiftUI

@MainActor
final class FloatingResponseViewModel: ObservableObject {
    enum Phase: Equatable {
        case composing
        case loading
        case streaming
        case complete
        case failed(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var responseText: String
    @Published var promptText: String
    @Published private(set) var isTranscribing = false
    @Published private(set) var contextSummary: HoverContextSummary?

    private let selectedText: String?
    private let sourceApplicationProcessIdentifier: pid_t?
    private let llmClient: LLMClient?
    private let speechTranscriptionService: SpeechTranscriptionService?
    private let configurationProvider: (() throws -> LLMConfiguration)?
    private let screenContextProvider: (() async -> ScreenContext?)?
    private var streamTask: Task<Void, Never>?

    init(
        selectedText: String?,
        sourceApplicationProcessIdentifier: pid_t?,
        llmClient: LLMClient,
        speechTranscriptionService: SpeechTranscriptionService?,
        configurationProvider: @escaping () throws -> LLMConfiguration,
        screenContextProvider: @escaping () async -> ScreenContext?
    ) {
        self.selectedText = selectedText
        self.sourceApplicationProcessIdentifier = sourceApplicationProcessIdentifier
        self.llmClient = llmClient
        self.speechTranscriptionService = speechTranscriptionService
        self.configurationProvider = configurationProvider
        self.screenContextProvider = screenContextProvider
        self.phase = .composing
        self.responseText = ""
        self.promptText = ""
    }

    init(errorMessage: String) {
        self.selectedText = nil
        self.sourceApplicationProcessIdentifier = nil
        self.llmClient = nil
        self.speechTranscriptionService = nil
        self.configurationProvider = nil
        self.screenContextProvider = nil
        self.phase = .failed(errorMessage)
        self.responseText = ""
        self.promptText = ""
    }

    deinit {
        streamTask?.cancel()
    }

    var canCopy: Bool {
        !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSelectedText: Bool {
        selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var canPasteResult: Bool {
        canCopy && sourceApplicationProcessIdentifier != nil
    }

    var canUseVoiceInput: Bool {
        speechTranscriptionService != nil
    }

    var statusText: String {
        switch phase {
        case .composing:
            "Ask"
        case .loading:
            "Thinking"
        case .streaming:
            "Streaming"
        case .complete:
            "Ready"
        case .failed:
            "Attention"
        }
    }

    var statusColor: Color {
        switch phase {
        case .composing:
            .accentColor
        case .loading, .streaming:
            .accentColor
        case .complete:
            .green
        case .failed:
            .orange
        }
    }

    func start() {
        contextSummary = HoverContextSummary(
            selectedText: hasSelectedText,
            screenText: false,
            screenshot: false,
            remoteProvider: false
        )
    }

    func submitPrompt() {
        submit(userPrompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func submitPreset(_ preset: HoverActionPreset) {
        guard preset != .ask else {
            return
        }

        submit(userPrompt: preset.prompt)
    }

    private func submit(userPrompt: String) {
        guard streamTask == nil,
              let llmClient,
              let configurationProvider,
              let screenContextProvider else {
            return
        }

        guard hasSelectedText || !userPrompt.isEmpty else {
            return
        }

        responseText = ""
        phase = .loading
        streamTask = Task { [weak self] in
            await self?.runStream(
                userPrompt: userPrompt.isEmpty ? nil : userPrompt,
                llmClient: llmClient,
                configurationProvider: configurationProvider,
                screenContextProvider: screenContextProvider
            )
        }
    }

    func toggleVoiceInput() {
        guard let speechTranscriptionService else {
            return
        }

        if isTranscribing {
            speechTranscriptionService.stop()
            isTranscribing = false
            return
        }

        Task { @MainActor in
            do {
                try await speechTranscriptionService.start(
                    onText: { [weak self] text in
                        self?.promptText = text
                    },
                    onFinish: { [weak self] in
                        self?.isTranscribing = false
                    }
                )
                isTranscribing = true
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func copyResult() {
        guard canCopy else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(responseText, forType: .string)
    }

    func pasteResultToSourceApplication() {
        guard canPasteResult,
              let sourceApplicationProcessIdentifier else {
            return
        }

        // Paste is intentionally implemented through the system pasteboard and Command-V.
        // That keeps compatibility broad across native apps, browsers, Electron apps, and
        // text fields without requiring app-specific Accessibility mutation code.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(responseText, forType: .string)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)

            if let app = NSRunningApplication(processIdentifier: sourceApplicationProcessIdentifier) {
                app.activate(options: [.activateAllWindows])
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            Self.postPasteKeystroke()
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        speechTranscriptionService?.stop()
        isTranscribing = false
    }

    private func runStream(
        userPrompt: String?,
        llmClient: LLMClient,
        configurationProvider: () throws -> LLMConfiguration,
        screenContextProvider: () async -> ScreenContext?
    ) async {
        do {
            let configuration = try configurationProvider()
            let screenContext = await screenContextProvider()
            // The panel shows this summary so users understand whether Hover is sending
            // only a prompt, selected text, screen text, or screenshot context.
            contextSummary = HoverContextSummary(
                selectedText: selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                screenText: screenContext?.accessibilityText?.isEmpty == false,
                screenshot: screenContext?.screenshotDataURL?.isEmpty == false,
                remoteProvider: Self.isRemoteProvider(configuration.baseURL)
            )
            var didReceiveToken = false

            let requestContext = LLMRequestContext(
                userPrompt: userPrompt,
                selectedText: selectedText,
                screenContext: screenContext
            )

            for try await token in llmClient.streamCompletion(for: requestContext, configuration: configuration) {
                if !didReceiveToken {
                    didReceiveToken = true
                    phase = .streaming
                }

                withAnimation(.easeOut(duration: 0.10)) {
                    responseText += token
                }
            }

            if responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                phase = .failed("The model returned an empty response.")
            } else {
                phase = .complete
            }
        } catch is CancellationError {
            phase = .complete
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }

        return error.localizedDescription
    }

    private static func isRemoteProvider(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return true
        }

        return host != "localhost"
            && host != "127.0.0.1"
            && host != "::1"
            && host != "0.0.0.0"
    }

    private static func postPasteKeystroke() {
        // 0x09 is the virtual key code for V. Posting Command-V mirrors a normal user paste
        // and lets the destination app decide whether it replaces selection or inserts.
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

struct FloatingContentView: View {
    @ObservedObject var viewModel: FloatingResponseViewModel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)

            VStack(spacing: 0) {
                header

                Divider()
                    .opacity(0.5)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .frame(width: 560, height: 380)
        .task {
            viewModel.start()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image("HoverLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.14), radius: 8, y: 2)
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Hover")
                        .font(.system(size: 13, weight: .semibold))
                    Text(viewModel.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(viewModel.statusColor)
                }

                Spacer(minLength: 0)

                PhaseIndicator(phase: viewModel.phase, color: viewModel.statusColor)

                if viewModel.hasSelectedText {
                    PanelIconButton(
                        systemImage: "text.cursor",
                        help: "Replace selection",
                        isDisabled: !viewModel.canPasteResult
                    ) {
                        viewModel.pasteResultToSourceApplication()
                        onDismiss()
                    }
                }

                PanelIconButton(
                    systemImage: "arrow.down.doc",
                    help: "Paste to active app",
                    isDisabled: !viewModel.canPasteResult
                ) {
                    viewModel.pasteResultToSourceApplication()
                    onDismiss()
                }

                PanelIconButton(
                    systemImage: "doc.on.doc",
                    help: "Copy result",
                    isDisabled: !viewModel.canCopy
                ) {
                    viewModel.copyResult()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                PanelIconButton(systemImage: "xmark", help: "Dismiss") {
                    viewModel.cancel()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if let contextSummary = viewModel.contextSummary {
                ContextSummaryBadge(summary: contextSummary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .composing:
            PromptComposerView(viewModel: viewModel)
                .padding(18)
        case .loading:
            ShimmerLoadingView()
                .padding(20)
        case .failed(let message):
            ErrorContentView(message: message)
                .padding(20)
        case .streaming, .complete:
            MarkdownContentView(markdown: viewModel.responseText)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.08))
        }
    }
}

private struct PanelIconButton: View {
    let systemImage: String
    let help: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isDisabled ? 0.25 : 0.76))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        }
        .disabled(isDisabled)
        .help(help)
    }
}

private struct PhaseIndicator: View {
    let phase: FloatingResponseViewModel.Phase
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }

    private var label: String {
        switch phase {
        case .composing:
            "Ready"
        case .loading:
            "Starting"
        case .streaming:
            "Live"
        case .complete:
            "Complete"
        case .failed:
            "Issue"
        }
    }
}

private struct ContextSummaryBadge: View {
    let summary: HoverContextSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: summary.remoteProvider ? "arrow.up.right.circle" : "lock.shield")
                .font(.system(size: 10, weight: .semibold))
            Text(summary.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(summary.remoteProvider ? .orange : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
    }
}

private struct PromptComposerView: View {
    @ObservedObject var viewModel: FloatingResponseViewModel
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.hasSelectedText {
                Text("Choose an action")
                    .font(.system(size: 15, weight: .semibold))

                ActionPresetGrid { preset in
                    if preset == .ask {
                        isPromptFocused = true
                    } else {
                        viewModel.submitPreset(preset)
                    }
                }
            } else {
                Text("Ask Hover")
                    .font(.system(size: 15, weight: .semibold))
            }

            TextEditor(text: $viewModel.promptText)
                .font(.system(size: 14))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: viewModel.hasSelectedText ? 104 : 150)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.58))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                }
                .focused($isPromptFocused)

            HStack(spacing: 10) {
                if viewModel.canUseVoiceInput {
                    Button {
                        viewModel.toggleVoiceInput()
                    } label: {
                        Label(viewModel.isTranscribing ? "Stop" : "Voice", systemImage: viewModel.isTranscribing ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                Button {
                    viewModel.submitPrompt()
                } label: {
                    Label(viewModel.hasSelectedText ? "Ask with Selection" : "Ask", systemImage: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(viewModel.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            isPromptFocused = true
        }
    }
}

private struct ActionPresetGrid: View {
    let onSelect: (HoverActionPreset) -> Void
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(HoverActionPreset.allCases) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    Label(preset.title, systemImage: preset.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .padding(.horizontal, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.58), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ErrorContentView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.14))

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }
            .frame(width: 38, height: 38)

            Text("Request Failed")
                .font(.system(size: 15, weight: .semibold))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MarkdownContentView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(MarkdownInlineParser.parse(text))
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 2 : 4)

        case .paragraph(let text):
            Text(MarkdownInlineParser.parse(text))
                .font(.system(size: 14))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    listRow(marker: "•", text: item)
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    listRow(marker: "\(item.number).", text: item.text)
                }
            }

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.62))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)

                Text(MarkdownInlineParser.parse(text))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .rule:
            Divider()
                .opacity(0.55)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Text(MarkdownInlineParser.parse(text))
                .font(.system(size: 14))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            18
        case 2:
            16
        default:
            14
        }
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([OrderedMarkdownItem])
        case codeBlock(String)
        case quote(String)
        case rule
    }

    let id = UUID()
    let kind: Kind
}

private struct OrderedMarkdownItem: Identifiable {
    let id = UUID()
    let number: Int
    let text: String
}

private enum MarkdownInlineParser {
    static func parse(_ source: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: source,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(source)
        }
    }
}

private enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalizedSource = unwrapMarkdownFenceIfNeeded(source)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSource.isEmpty else {
            return []
        }

        let lines = normalizedSource.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [OrderedMarkdownItem] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var isReadingCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else {
                return
            }

            blocks.append(MarkdownBlock(kind: .paragraph(paragraphLines.joined(separator: " "))))
            paragraphLines.removeAll()
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else {
                return
            }

            blocks.append(MarkdownBlock(kind: .unorderedList(unorderedItems)))
            unorderedItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else {
                return
            }

            blocks.append(MarkdownBlock(kind: .orderedList(orderedItems)))
            orderedItems.removeAll()
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else {
                return
            }

            blocks.append(MarkdownBlock(kind: .quote(quoteLines.joined(separator: "\n"))))
            quoteLines.removeAll()
        }

        func flushLooseBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushQuote()
        }

        for rawLine in lines {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                if isReadingCodeBlock {
                    blocks.append(MarkdownBlock(kind: .codeBlock(codeLines.joined(separator: "\n"))))
                    codeLines.removeAll()
                    isReadingCodeBlock = false
                } else {
                    flushLooseBlocks()
                    isReadingCodeBlock = true
                }
                continue
            }

            if isReadingCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if trimmedLine.isEmpty {
                flushLooseBlocks()
                continue
            }

            if isRule(trimmedLine) {
                flushLooseBlocks()
                blocks.append(MarkdownBlock(kind: .rule))
                continue
            }

            if let heading = heading(from: trimmedLine) {
                flushLooseBlocks()
                blocks.append(MarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
                continue
            }

            if let unorderedText = unorderedListText(from: trimmedLine) {
                flushParagraph()
                flushOrderedList()
                flushQuote()
                unorderedItems.append(unorderedText)
                continue
            }

            if let orderedItem = orderedListItem(from: trimmedLine) {
                flushParagraph()
                flushUnorderedList()
                flushQuote()
                orderedItems.append(orderedItem)
                continue
            }

            if let quoteText = quoteText(from: trimmedLine) {
                flushParagraph()
                flushUnorderedList()
                flushOrderedList()
                quoteLines.append(quoteText)
                continue
            }

            flushUnorderedList()
            flushOrderedList()
            flushQuote()
            paragraphLines.append(trimmedLine)
        }

        if isReadingCodeBlock {
            blocks.append(MarkdownBlock(kind: .codeBlock(codeLines.joined(separator: "\n"))))
        }

        flushLooseBlocks()
        return blocks
    }

    private static func unwrapMarkdownFenceIfNeeded(_ source: String) -> String {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedSource = trimmedSource.lowercased()

        guard (lowercasedSource.hasPrefix("```markdown\n") || lowercasedSource.hasPrefix("```md\n")),
              trimmedSource.hasSuffix("```") else {
            return source
        }

        guard let firstNewline = trimmedSource.firstIndex(of: "\n") else {
            return source
        }

        let bodyStart = trimmedSource.index(after: firstNewline)
        let bodyEnd = trimmedSource.index(trimmedSource.endIndex, offsetBy: -3)
        guard bodyStart <= bodyEnd else {
            return source
        }

        return String(trimmedSource[bodyStart..<bodyEnd])
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              line.dropFirst(markerCount).first == " " else {
            return nil
        }

        let text = line
            .dropFirst(markerCount + 1)
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (markerCount, text)
    }

    private static func unorderedListText(from line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    private static func orderedListItem(from line: String) -> OrderedMarkdownItem? {
        guard let separatorRange = line.range(of: ". ") else {
            return nil
        }

        let numberText = String(line[..<separatorRange.lowerBound])
        guard let number = Int(numberText) else {
            return nil
        }

        let text = String(line[separatorRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : OrderedMarkdownItem(number: number, text: text)
    }

    private static func quoteText(from line: String) -> String? {
        guard line.hasPrefix(">") else {
            return nil
        }

        return String(line.dropFirst())
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isRule(_ line: String) -> Bool {
        let strippedLine = line.replacingOccurrences(of: " ", with: "")
        return strippedLine.count >= 3
            && Set(strippedLine).count == 1
            && ["-", "*", "_"].contains(String(strippedLine.first ?? " "))
    }
}

private struct ShimmerLoadingView: View {
    @State private var shimmerOffset: CGFloat = -180

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                shimmerLine(width: proxy.size.width * 0.84)
                shimmerLine(width: proxy.size.width * 0.95)
                shimmerLine(width: proxy.size.width * 0.72)
                shimmerLine(width: proxy.size.width * 0.88)
                shimmerLine(width: proxy.size.width * 0.48)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                shimmerOffset = 620
            }
        }
    }

    private func shimmerLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .frame(width: width, height: 13)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.24), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 110)
                .offset(x: shimmerOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
