//
//  HoverAction.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Defines user-facing AI actions and the context summary shown before/after a request.
//

import Foundation

enum HoverActionPreset: String, CaseIterable, Identifiable {
    case explain
    case rewrite
    case summarize
    case reply
    case translate
    case fixGrammar
    case ask

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .explain:
            "Explain"
        case .rewrite:
            "Rewrite"
        case .summarize:
            "Summarize"
        case .reply:
            "Reply"
        case .translate:
            "Translate"
        case .fixGrammar:
            "Fix grammar"
        case .ask:
            "Ask"
        }
    }

    var systemImage: String {
        switch self {
        case .explain:
            "lightbulb"
        case .rewrite:
            "pencil.and.scribble"
        case .summarize:
            "text.alignleft"
        case .reply:
            "arrowshape.turn.up.left"
        case .translate:
            "globe"
        case .fixGrammar:
            "text.badge.checkmark"
        case .ask:
            "questionmark.circle"
        }
    }

    var prompt: String {
        switch self {
        case .explain:
            "Explain the selected text in clear, simple language. Keep it useful and concise."
        case .rewrite:
            "Rewrite the selected text to be clearer, sharper, and more polished. Return only the rewritten version."
        case .summarize:
            "Summarize the selected text into the few most important points."
        case .reply:
            "Draft a concise, helpful reply to the selected text. Match the tone and context."
        case .translate:
            "Translate the selected text into natural English unless another target language is obvious from my request."
        case .fixGrammar:
            "Fix grammar, spelling, and clarity in the selected text. Return only the corrected version."
        case .ask:
            ""
        }
    }
}

struct HoverContextSummary: Equatable {
    let selectedText: Bool
    let screenText: Bool
    let screenshot: Bool
    let remoteProvider: Bool

    var label: String {
        var parts: [String] = []

        if selectedText {
            parts.append("Selected text")
        }

        if screenText {
            parts.append("Screen text")
        }

        if screenshot {
            parts.append("Screenshot")
        }

        if parts.isEmpty {
            parts.append("Prompt only")
        }

        let destination = remoteProvider ? "sent to provider" : "kept on local endpoint"
        return "\(parts.joined(separator: " + ")) \(destination)"
    }
}
