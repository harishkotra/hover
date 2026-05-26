//
//  SpeechTranscriptionService.swift
//  Hover
//
//  Created by OpenAI Codex on 2026-05-26.
//  Provides push-to-talk transcription with no idle audio work.
//

import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriptionService {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var isRecording: Bool {
        audioEngine.isRunning
    }

    func start(
        onText: @escaping @MainActor (String) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) async throws {
        guard !audioEngine.isRunning else {
            return
        }

        guard await Self.requestPermissions() else {
            throw SpeechTranscriptionError.permissionDenied
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    onText(text)
                }
            }

            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stop()
                    onFinish()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        guard audioEngine.isRunning || recognitionTask != nil else {
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    static func requestPermissions() async -> Bool {
        async let speechAllowed = requestSpeechPermission()
        async let microphoneAllowed = requestMicrophonePermission()
        let resolvedSpeechAllowed = await speechAllowed
        let resolvedMicrophoneAllowed = await microphoneAllowed
        return resolvedSpeechAllowed && resolvedMicrophoneAllowed
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

enum SpeechTranscriptionError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Enable Microphone and Speech Recognition permissions for Hover to use voice input."
        }
    }
}
