//
//  FloatingPanel.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Provides a borderless non-activating panel and coordinator for pointer-positioned responses.
//

import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private let llmClient: LLMClient
    private let screenContextService: ScreenContextService
    private weak var settingsProvider: SettingsViewModel?
    private var panel: FloatingPanel?

    init(
        llmClient: LLMClient,
        screenContextService: ScreenContextService,
        settingsProvider: SettingsViewModel
    ) {
        self.llmClient = llmClient
        self.screenContextService = screenContextService
        self.settingsProvider = settingsProvider
    }

    func present(context: SelectionContext) {
        let viewModel = FloatingResponseViewModel(
            selectedText: context.selectedText,
            sourceApplicationProcessIdentifier: context.sourceApplicationProcessIdentifier,
            llmClient: llmClient,
            speechTranscriptionService: settingsProvider?.isVoiceInputEnabled == true ? SpeechTranscriptionService() : nil,
            configurationProvider: { [weak settingsProvider] in
                guard let settingsProvider else {
                    throw FloatingPanelError.settingsUnavailable
                }

                return try settingsProvider.makeConfiguration()
            },
            screenContextProvider: { [weak self, weak settingsProvider] in
                guard let self,
                      settingsProvider?.isScreenContextEnabled == true else {
                    return nil
                }

                return await self.screenContextService.captureContext(
                    at: context.mouseLocation,
                    includeScreenshot: settingsProvider?.isScreenshotContextEnabled == true
                        && LLMClient.supportsImageInput(modelName: settingsProvider?.modelName ?? "")
                )
            }
        )

        present(viewModel: viewModel, at: context.mouseLocation)
    }

    func present(errorMessage: String, at point: CGPoint) {
        let viewModel = FloatingResponseViewModel(errorMessage: errorMessage)
        present(viewModel: viewModel, at: point)
    }

    private func present(viewModel: FloatingResponseViewModel, at point: CGPoint) {
        panel?.dismiss(animated: false)

        let size = CGSize(width: 560, height: 380)
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let contentView = FloatingContentView(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.panel?.dismiss(animated: true)
            }
        )

        panel.contentView = NSHostingView(rootView: contentView)
        panel.onClose = { [weak self, weak panel] in
            guard self?.panel === panel else {
                return
            }

            self?.panel = nil
        }

        self.panel = panel
        panel.present(at: point, preferredSize: size)
    }
}

final class FloatingPanel: NSPanel {
    var onClose: (() -> Void)?

    private var didNotifyClose = false
    private var isDismissInProgress = false

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow
    }

    func present(at cursorLocation: CGPoint, preferredSize: CGSize) {
        setFrame(frameNearCursor(cursorLocation, size: preferredSize), display: false)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func dismiss(animated: Bool) {
        guard !isDismissInProgress else {
            return
        }

        isDismissInProgress = true

        guard animated, isVisible else {
            close()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.close()
        }
    }

    override func resignKey() {
        super.resignKey()
        dismiss(animated: true)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(animated: true)
    }

    override func close() {
        super.close()
        notifyClosed()
    }

    private func notifyClosed() {
        guard !didNotifyClose else {
            return
        }

        didNotifyClose = true
        onClose?()
    }

    private func frameNearCursor(_ cursorLocation: CGPoint, size: CGSize) -> NSRect {
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(cursorLocation)
        } ?? NSScreen.main

        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let margin: CGFloat = 12
        let pointerOffset: CGFloat = 16

        // Prefer the lower-right of the cursor, then clamp into the visible screen frame.
        var origin = CGPoint(
            x: cursorLocation.x + pointerOffset,
            y: cursorLocation.y - size.height - pointerOffset
        )

        if origin.y < visibleFrame.minY + margin {
            origin.y = cursorLocation.y + pointerOffset
        }

        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - size.width - margin
        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - size.height - margin

        origin.x = min(max(origin.x, minX), max(minX, maxX))
        origin.y = min(max(origin.y, minY), max(minY, maxY))

        return NSRect(origin: origin, size: size)
    }
}

enum FloatingPanelError: LocalizedError {
    case settingsUnavailable

    var errorDescription: String? {
        switch self {
        case .settingsUnavailable:
            "Hover settings are unavailable."
        }
    }
}
