//
//  TranscriptionService.swift
//  Huiyijilu
//

import Foundation
import Combine
import Speech
import AVFoundation

/// Speech-to-text transcription using iOS Speech framework (free, on-device)
class TranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var progress: Double = 0

    private var recognizer: SFSpeechRecognizer?

    init() {
        // Support Chinese and English
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        if recognizer?.isAvailable != true {
            recognizer = SFSpeechRecognizer(locale: Locale.current)
        }
    }

    /// Request speech recognition authorization
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Transcribe an audio file to text
    func transcribe(audioFileURL: URL) async throws -> String {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        await MainActor.run { isTranscribing = true; progress = 0 }

        defer {
            Task { @MainActor in
                self.isTranscribing = false
                self.progress = 1.0
            }
        }

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        // Get audio duration for progress tracking
        let asset = AVURLAsset(url: audioFileURL)
        let durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))

        return try await withCheckedThrowingContinuation { continuation in
            var fullTranscript = ""
            var lastTimestamp: TimeInterval = 0

            recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result = result {
                    fullTranscript = result.bestTranscription.formattedString

                    // Update progress based on segments
                    if let lastSegment = result.bestTranscription.segments.last {
                        lastTimestamp = lastSegment.timestamp + lastSegment.duration
                        let currentProgress = min(lastTimestamp / max(durationSeconds, 1), 0.95)
                        Task { @MainActor in
                            self?.progress = currentProgress
                        }
                    }

                    if result.isFinal {
                        continuation.resume(returning: fullTranscript)
                    }
                } else if let error = error {
                    if fullTranscript.isEmpty {
                        continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    } else {
                        // Return partial result if we have some text
                        continuation.resume(returning: fullTranscript)
                    }
                }
            }
        }
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        }
    }
}
