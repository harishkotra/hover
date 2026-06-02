//
//  UpdateController.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-06-02.
//  Wraps Sparkle so Hover can check GitHub-hosted appcasts without leaking
//  updater implementation details into the app menu or settings views.
//

import Foundation
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var isUpdaterAvailable: Bool
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var automaticallyDownloadsUpdates: Bool
    @Published private(set) var allowsAutomaticUpdates: Bool

    private let updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        guard Self.hasUsableSparkleConfiguration(in: bundle) else {
            self.updaterController = nil
            self.isUpdaterAvailable = false
            self.automaticallyChecksForUpdates = false
            self.automaticallyDownloadsUpdates = false
            self.allowsAutomaticUpdates = false
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        self.updaterController = controller
        self.isUpdaterAvailable = true
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        self.allowsAutomaticUpdates = controller.updater.allowsAutomaticUpdates
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard let updater = updaterController?.updater else {
            return
        }

        updater.automaticallyChecksForUpdates = isEnabled

        if !isEnabled {
            updater.automaticallyDownloadsUpdates = false
        }

        syncUpdaterPreferences()
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        guard let updater = updaterController?.updater else {
            return
        }

        if isEnabled && !updater.automaticallyChecksForUpdates {
            updater.automaticallyChecksForUpdates = true
        }

        updater.automaticallyDownloadsUpdates = isEnabled && updater.allowsAutomaticUpdates
        syncUpdaterPreferences()
    }

    private func syncUpdaterPreferences() {
        guard let updater = updaterController?.updater else {
            isUpdaterAvailable = false
            automaticallyChecksForUpdates = false
            automaticallyDownloadsUpdates = false
            allowsAutomaticUpdates = false
            return
        }

        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
    }

    private static func hasUsableSparkleConfiguration(in bundle: Bundle) -> Bool {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""

        return isConcreteBuildSetting(feedURL) && isConcreteBuildSetting(publicKey)
    }

    private static func isConcreteBuildSetting(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedValue.isEmpty && !trimmedValue.contains("$(")
    }
}
