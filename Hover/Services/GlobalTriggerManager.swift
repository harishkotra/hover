//
//  GlobalTriggerManager.swift
//  Hover
//
//  Created by Hover Contributors on 2026-05-26.
//  Registers the global shortcut, copies the active text selection, and reports cursor coordinates.
//

import AppKit
import ApplicationServices
import Carbon
import Foundation

struct SelectionContext: Equatable {
    let selectedText: String?
    let mouseLocation: CGPoint
    let capturedAt: Date
    let sourceApplicationProcessIdentifier: pid_t?
}

@MainActor
final class GlobalTriggerManager {
    var onSelectionCaptured: ((SelectionContext) -> Void)?
    var onCaptureFailed: ((String, CGPoint) -> Void)?

    private static let maxSelectionCharacters = 24_000
    private static let hotKeySignature = OSType(fourCharacterCode("PAIX"))
    private static let tripleRightClickInterval: TimeInterval = 0.72
    private static let tripleRightClickMovementTolerance: CGFloat = 18

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var rightClickMonitor: Any?
    private var isEnabled = false
    private var isTripleRightClickEnabled = false
    private var isCaptureInFlight = false
    private var rightClickCount = 0
    private var lastRightClickDate = Date.distantPast
    private var firstRightClickLocation = CGPoint.zero

    deinit {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }

        isEnabled = enabled
        enabled ? registerHotKey() : unregisterHotKey()
        updateRightClickMonitor()
    }

    func setTripleRightClickEnabled(_ enabled: Bool) {
        guard enabled != isTripleRightClickEnabled else {
            return
        }

        isTripleRightClickEnabled = enabled
        resetRightClickGesture()
        updateRightClickMonitor()
    }

    static func requestAccessibilityTrustIfNeeded() {
        guard !hasCopyAutomationPermission() else {
            return
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if #available(macOS 10.15, *) {
            _ = CGRequestPostEventAccess()
        }
    }

    private func registerHotKey() {
        guard eventHandlerRef == nil, hotKeyRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            onCaptureFailed?("Hover could not install the global shortcut handler.", NSEvent.mouseLocation)
            eventHandlerRef = nil
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_X),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            onCaptureFailed?("Hover could not register Command-Shift-X. Another app may already own it.", NSEvent.mouseLocation)
            unregisterHotKey()
            return
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func updateRightClickMonitor() {
        let shouldMonitor = isEnabled && isTripleRightClickEnabled

        if shouldMonitor, rightClickMonitor == nil {
            rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                Task { @MainActor in
                    self?.handleRightMouseDown(event)
                }
            }
        } else if !shouldMonitor, let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }
    }

    private func handleRightMouseDown(_ event: NSEvent) {
        guard isEnabled, isTripleRightClickEnabled, !isCaptureInFlight else {
            return
        }

        let now = Date()
        let location = NSEvent.mouseLocation
        let isContinuation = now.timeIntervalSince(lastRightClickDate) <= Self.tripleRightClickInterval
            && distance(from: firstRightClickLocation, to: location) <= Self.tripleRightClickMovementTolerance

        if isContinuation {
            rightClickCount += 1
        } else {
            rightClickCount = 1
            firstRightClickLocation = location
        }

        lastRightClickDate = now

        guard rightClickCount >= 3 else {
            return
        }

        resetRightClickGesture()
        handleTriggerPressed(mouseLocation: location, dismissContextMenuBeforeCopy: true)
    }

    private func handleHotKeyPressed() {
        handleTriggerPressed(mouseLocation: NSEvent.mouseLocation, dismissContextMenuBeforeCopy: false)
    }

    private func handleTriggerPressed(mouseLocation: CGPoint, dismissContextMenuBeforeCopy: Bool) {
        guard isEnabled, !isCaptureInFlight else {
            return
        }

        isCaptureInFlight = true

        Task { @MainActor in
            defer {
                isCaptureInFlight = false
            }

            let selectedText: String?
            do {
                let copiedText = try await copySelectedTextPreservingPasteboard(
                    dismissContextMenuFirst: dismissContextMenuBeforeCopy
                )
                let sanitizedText = Self.sanitize(copiedText)
                selectedText = sanitizedText.isEmpty ? nil : sanitizedText
            } catch TriggerError.copyTimedOut {
                selectedText = nil
            } catch {
                onCaptureFailed?(Self.message(for: error), mouseLocation)
                return
            }

            onSelectionCaptured?(
                SelectionContext(
                    selectedText: selectedText,
                    mouseLocation: mouseLocation,
                    capturedAt: Date(),
                    sourceApplicationProcessIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier
                )
            )
        }
    }

    private func copySelectedTextPreservingPasteboard(dismissContextMenuFirst: Bool) async throws -> String {
        let hadAutomationPermission = Self.hasCopyAutomationPermission()
        if !hadAutomationPermission {
            Self.requestAccessibilityTrustIfNeeded()
        }

        // Hover needs selected text, but it should not permanently overwrite the user's
        // clipboard. Snapshot and restore all pasteboard item types, not just plain text.
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let startingChangeCount = pasteboard.changeCount

        defer {
            snapshot.restore(to: pasteboard)
        }

        if dismissContextMenuFirst {
            postEscapeKeystroke()
            try await Task.sleep(nanoseconds: 90_000_000)
        }

        try postCopyKeystroke()

        let deadline = Date().addingTimeInterval(0.9)
        while Date() < deadline {
            try Task.checkCancellation()

            if pasteboard.changeCount != startingChangeCount {
                return pasteboard.string(forType: .string) ?? ""
            }

            try await Task.sleep(nanoseconds: 35_000_000)
        }

        if !hadAutomationPermission && !Self.hasCopyAutomationPermission() {
            throw TriggerError.copyAutomationPermissionMissing(Self.permissionRecoveryMessage())
        }

        throw TriggerError.copyTimedOut
    }

    private func postCopyKeystroke() throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            throw TriggerError.copyEventCreationFailed
        }

        // The active application receives a normal Command-C, so Hover works with standard text views
        // without Accessibility element scraping or app-specific integrations.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postEscapeKeystroke() {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_Escape), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_Escape), keyDown: false) else {
            return
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func resetRightClickGesture() {
        rightClickCount = 0
        lastRightClickDate = .distantPast
        firstRightClickLocation = .zero
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func sanitize(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > maxSelectionCharacters else {
            return normalized
        }

        return String(normalized.prefix(maxSelectionCharacters))
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }

        return error.localizedDescription
    }

    private static func hasCopyAutomationPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        if #available(macOS 10.15, *) {
            return CGPreflightPostEventAccess()
        }

        return false
    }

    private static func permissionRecoveryMessage() -> String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Hover"
        return """
        macOS is still blocking keyboard automation for this running build. Quit \(appName), remove \(appName) from System Settings > Privacy & Security > Accessibility, run the current build again, and add it back. If you launch from Xcode, enable Xcode in Accessibility too.
        """
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<GlobalTriggerManager>
            .fromOpaque(userData)
            .takeUnretainedValue()

        Task { @MainActor in
            manager.handleHotKeyPressed()
        }

        return noErr
    }

    private static func fourCharacterCode(_ string: String) -> FourCharCode {
        string.unicodeScalars.reduce(FourCharCode(0)) { result, scalar in
            (result << 8) + FourCharCode(scalar.value)
        }
    }
}

private enum TriggerError: LocalizedError {
    case copyAutomationPermissionMissing(String)
    case copyEventCreationFailed
    case copyTimedOut

    var errorDescription: String? {
        switch self {
        case .copyAutomationPermissionMissing(let message):
            message
        case .copyEventCreationFailed:
            "Hover could not create the system copy event."
        case .copyTimedOut:
            "Hover did not receive copied text from the active application."
        }
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        self.items = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                result[type] = item.data(forType: type)
            }
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.map { storedTypes in
            let item = NSPasteboardItem()
            storedTypes.forEach { type, data in
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
