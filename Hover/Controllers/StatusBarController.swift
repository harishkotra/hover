//
//  StatusBarController.swift
//  Hover
//
//  Created by Hover Contributors on 2026-05-26.
//  Owns the menu bar item, listener toggle, Settings entry point, and Quit action.
//

import AppKit
import Foundation
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var settingsViewModel: SettingsViewModel?
    private weak var toggleItem: NSMenuItem?

    init(settingsViewModel: SettingsViewModel) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.settingsViewModel = settingsViewModel
        super.init()
    }

    func install() {
        configureButton()
        rebuildMenu()
    }

    func refreshMenuState() {
        guard let settingsViewModel else {
            return
        }

        toggleItem?.title = settingsViewModel.isGlobalListenerEnabled
            ? "Disable Global Listener"
            : "Enable Global Listener"
        toggleItem?.state = settingsViewModel.isGlobalListenerEnabled ? .on : .off
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        let preferredImage = NSImage(named: "HoverMenuBarIcon")
            ?? NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Hover")
        let fallbackImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Hover")
        let image = preferredImage ?? fallbackImage
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Hover"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(
            title: "Disable Global Listener",
            action: #selector(toggleGlobalListener),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        self.toggleItem = toggleItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem()
        settingsItem.view = NSHostingView(rootView: StatusBarSettingsLink())
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Hover",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    @objc private func toggleGlobalListener() {
        settingsViewModel?.isGlobalListenerEnabled.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private struct StatusBarSettingsLink: View {
    var body: some View {
        SettingsLink {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .frame(width: 16)

                Text("Settings...")

                Spacer(minLength: 24)

                Text("⌘,")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 210, height: 24)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                SettingsWindowPresenter.bringSettingsForwardSoon()
            }
        )
        .buttonStyle(.plain)
    }
}
