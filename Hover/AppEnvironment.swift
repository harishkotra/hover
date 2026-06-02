//
//  AppEnvironment.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Wires together shared services for the menu bar app without leaking dependencies into views.
//

import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppEnvironment {
    let settingsViewModel: SettingsViewModel
    let updateController: UpdateController

    private let llmClient: LLMClient
    private let screenContextService: ScreenContextService
    private let globalTriggerManager: GlobalTriggerManager
    private let floatingPanelController: FloatingPanelController
    private var onboardingWindow: NSWindow?

    init() {
        let keychainStore = KeychainStore()
        let settingsViewModel = SettingsViewModel(keychainStore: keychainStore)
        let llmClient = LLMClient()
        let screenContextService = ScreenContextService()
        let updateController = UpdateController()
        let floatingPanelController = FloatingPanelController(
            llmClient: llmClient,
            screenContextService: screenContextService,
            settingsProvider: settingsViewModel
        )
        let globalTriggerManager = GlobalTriggerManager()

        self.settingsViewModel = settingsViewModel
        self.updateController = updateController
        self.llmClient = llmClient
        self.screenContextService = screenContextService
        self.floatingPanelController = floatingPanelController
        self.globalTriggerManager = globalTriggerManager

        self.globalTriggerManager.onSelectionCaptured = { [weak floatingPanelController] context in
            floatingPanelController?.present(context: context)
        }

        self.globalTriggerManager.onCaptureFailed = { [weak floatingPanelController] message, point in
            floatingPanelController?.present(errorMessage: message, at: point)
        }

        self.settingsViewModel.onListenerPreferenceChanged = { [weak self] isEnabled in
            self?.globalTriggerManager.setEnabled(isEnabled)
        }

        self.settingsViewModel.onTripleRightClickPreferenceChanged = { [weak self] isEnabled in
            self?.globalTriggerManager.setTripleRightClickEnabled(isEnabled)
        }
    }

    func start() {
        globalTriggerManager.setTripleRightClickEnabled(settingsViewModel.isTripleRightClickEnabled)
        globalTriggerManager.setEnabled(settingsViewModel.isGlobalListenerEnabled)

        if !settingsViewModel.isOnboardingCompleted {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                presentOnboarding()
            }
        }
    }

    func stop() {
        globalTriggerManager.setEnabled(false)
    }

    func presentOnboardingFromMenu() {
        // MenuBarExtra actions run while AppKit is still tearing down the menu.
        // Opening an accessory app window in that tracking cycle can briefly flash
        // and then lose ordering, so defer to the next foreground-safe moment.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            presentOnboarding()
        }
    }

    func presentOnboarding() {
        // Keep onboarding as a separate AppKit window rather than another Settings tab so
        // first-run users see permissions and provider setup before entering the full app.
        if let onboardingWindow {
            bringOnboardingWindowForward(onboardingWindow)
            return
        }

        let contentView = OnboardingView(
            viewModel: settingsViewModel,
            onFinish: { [weak self] in
                self?.settingsViewModel.completeOnboarding()
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Hover"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        onboardingWindow = window
        bringOnboardingWindowForward(window)
    }

    private func bringOnboardingWindowForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
