//
//  ScreenContextService.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Captures lightweight screen and Accessibility context only when Hover is triggered.
//

import AppKit
import ApplicationServices
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenContext: Equatable {
    let activeApplicationName: String?
    let focusedWindowTitle: String?
    let accessibilityText: String?
    let screenshotDataURL: String?
}

final class ScreenContextService {
    private let maxTextLength = 8_000
    private let maxScreenshotWidth = 1_280

    func captureContext(at point: CGPoint, includeScreenshot: Bool) async -> ScreenContext {
        // AX text and screenshot capture are independent, so gather both concurrently.
        // The caller decides whether screenshot context is allowed for the current request.
        async let appContext = activeApplicationContext()
        async let screenshot = includeScreenshot ? captureScreenshotDataURL(at: point) : nil

        let resolvedAppContext = await appContext
        return ScreenContext(
            activeApplicationName: resolvedAppContext.appName,
            focusedWindowTitle: resolvedAppContext.windowTitle,
            accessibilityText: resolvedAppContext.text,
            screenshotDataURL: await screenshot
        )
    }

    private func activeApplicationContext() -> (appName: String?, windowTitle: String?, text: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil, nil)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedElement = copyAXElement(attribute: kAXFocusedUIElementAttribute, from: appElement)
        let focusedWindow = copyAXElement(attribute: kAXFocusedWindowAttribute, from: appElement)

        let windowTitle = stringAttribute(kAXTitleAttribute, from: focusedWindow)
        let text = [focusedElement, focusedWindow]
            .compactMap(extractText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            app.localizedName,
            windowTitle,
            text.isEmpty ? nil : String(text.prefix(maxTextLength))
        )
    }

    private func extractText(from element: AXUIElement?) -> String? {
        guard let element else {
            return nil
        }

        let attributes = [
            kAXSelectedTextAttribute,
            kAXValueAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute
        ]

        let text = attributes
            .compactMap { stringAttribute($0, from: element) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    private func copyAXElement(attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else {
            return nil
        }

        guard let value else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement?) -> String? {
        guard let element else {
            return nil
        }

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else {
            return nil
        }

        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let attributedString = value as? NSAttributedString {
            return attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func captureScreenshotDataURL(at point: CGPoint) async -> String? {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { display in
                display.frame.contains(point)
            }) ?? content.displays.first else {
                return nil
            }

            let excludedWindows = content.windows.filter { window in
                window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }

            let configuration = SCStreamConfiguration()
            configuration.width = min(display.width, maxScreenshotWidth)
            configuration.height = max(1, Int(Double(configuration.width) * Double(display.height) / Double(display.width)))
            configuration.showsCursor = true

            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            return jpegDataURL(from: image)
        } catch {
            return nil
        }
    }

    private func jpegDataURL(from image: CGImage) -> String? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.58] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
