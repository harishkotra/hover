//
//  HoverApp.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Defines the background application lifecycle and exposes the native Settings scene.
//

import AppKit
import SwiftUI

@main
struct HoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            HoverMenuView(
                viewModel: appDelegate.environment.settingsViewModel,
                updateController: appDelegate.environment.updateController,
                openOnboarding: {
                    appDelegate.environment.presentOnboardingFromMenu()
                }
            )
        } label: {
            Image("HoverMenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Hover")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(viewModel: appDelegate.environment.settingsViewModel)
        }
    }
}

@MainActor
enum SettingsWindowPresenter {
    static func bringSettingsForwardSoon() {
        NSApp.activate(ignoringOtherApps: true)
        scheduleSettingsWindowActivation(after: 0.05)
        scheduleSettingsWindowActivation(after: 0.25)
    }

    static func bringSettingsWindowForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func scheduleSettingsWindowActivation(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard let window = NSApp.windows.first(where: { candidate in
                candidate.title.localizedCaseInsensitiveContains("settings")
            }) else {
                return
            }

            bringSettingsWindowForward(window)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }
}

private struct HoverMenuView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var updateController: UpdateController
    let openOnboarding: () -> Void

    var body: some View {
        Button {
            viewModel.isGlobalListenerEnabled.toggle()
        } label: {
            Label(listenerTitle, systemImage: viewModel.isGlobalListenerEnabled ? "pause.circle" : "play.circle")
        }

        Divider()

        Button {
            openOnboarding()
        } label: {
            Label("Setup Guide...", systemImage: "wand.and.stars")
        }

        SettingsLink {
            Label("Settings...", systemImage: "gearshape")
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                SettingsWindowPresenter.bringSettingsForwardSoon()
            }
        )
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button {
            updateController.checkForUpdates()
        } label: {
            Label("Check for Updates...", systemImage: "arrow.down.circle")
        }
        .disabled(!updateController.isUpdaterAvailable)

        Toggle(isOn: automaticUpdateCheckBinding) {
            Label("Automatically Check for Updates", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!updateController.isUpdaterAvailable)

        Toggle(isOn: automaticUpdateInstallBinding) {
            Label("Download and Install Updates Automatically", systemImage: "square.and.arrow.down")
        }
        .disabled(!updateController.isUpdaterAvailable || !updateController.allowsAutomaticUpdates)

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Hover", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private var listenerTitle: String {
        viewModel.isGlobalListenerEnabled
            ? "Disable Global Listener"
            : "Enable Global Listener"
    }

    private var automaticUpdateCheckBinding: Binding<Bool> {
        Binding(
            get: { updateController.automaticallyChecksForUpdates },
            set: { updateController.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticUpdateInstallBinding: Binding<Bool> {
        Binding(
            get: { updateController.automaticallyDownloadsUpdates },
            set: { updateController.setAutomaticallyDownloadsUpdates($0) }
        )
    }
}
