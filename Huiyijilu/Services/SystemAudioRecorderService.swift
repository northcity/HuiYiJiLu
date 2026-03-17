//
//  SystemAudioRecorderService.swift
//  Huiyijilu
//
//  使用 ReplayKit 实现系统内录功能（屏幕录制 → 提取音频）。
//  可录制系统声音 + 麦克风，适用于录制在线会议等场景。
//

import Foundation
import ReplayKit
import AVFoundation
import Combine

/// ReplayKit-based system audio recorder.
/// Uses `RPScreenRecorder.startRecording()` to capture system audio + microphone,
/// then extracts audio from the screen recording video as .m4a.
@MainActor
class SystemAudioRecorderService: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0

    // MARK: - Internal
    private let screenRecorder = RPScreenRecorder.shared()
    private var timer: Timer?
    private var startDate: Date?
    private(set) var currentFileName: String = ""

    /// Whether screen recording is available on this device.
    var isAvailable: Bool { screenRecorder.isAvailable }

    // MARK: - Paths

    private var tempVideoURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rp_screen_recording.mp4")
    }

    private var recordingsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Recordings")
    }

    private func log(_ msg: String) { print("[SystemRec] \(msg)") }

    // MARK: - Start Recording

    func startRecording() async throws {
        guard screenRecorder.isAvailable else {
            log("⛔ Screen recording not available")
            throw SystemRecordingError.notAvailable
        }

        // Clean up any previous temp video
        try? FileManager.default.removeItem(at: tempVideoURL)

        // Enable microphone so we capture device mic + system audio
        screenRecorder.isMicrophoneEnabled = true

        log("▶ Requesting screen recording permission...")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            screenRecorder.startRecording { [weak self] error in
                if let error = error {
                    self?.log("⛔ startRecording failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    self?.log("✅ Screen recording started")
                    continuation.resume()
                }
            }
        }

        isRecording = true
        startDate = Date()
        startTimer()
    }

    // MARK: - Stop Recording

    /// Stop recording, extract audio from video, return file name and duration.
    func stopRecording() async throws -> (fileName: String, duration: TimeInterval) {
        guard isRecording else {
            throw SystemRecordingError.notRecording
        }

        let duration = recordingTime
        stopTimer()

        // Ensure recordings directory exists
        if !FileManager.default.fileExists(atPath: recordingsDir.path) {
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        // Generate unique file name
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        currentFileName = "meeting_sys_\(fmt.string(from: Date())).m4a"
        let audioOutputURL = recordingsDir.appendingPathComponent(currentFileName)

        let videoURL = tempVideoURL
        log("⏹ Stopping screen recording → \(videoURL.lastPathComponent)")

        // Stop screen recording → save to temp video file
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            screenRecorder.stopRecording(withOutput: videoURL) { [weak self] error in
                if let error = error {
                    self?.log("⛔ stopRecording failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    self?.log("✅ Screen recording saved")
                    continuation.resume()
                }
            }
        }

        // Extract audio from video → .m4a
        log("🔄 Extracting audio...")
        try await extractAudio(from: videoURL, to: audioOutputURL)
        log("✅ Audio extracted → \(currentFileName)")

        // Clean up temp video
        try? FileManager.default.removeItem(at: videoURL)

        isRecording = false
        recordingTime = 0
        startDate = nil

        return (fileName: currentFileName, duration: duration)
    }

    // MARK: - Audio Extraction

    /// Extract audio track from a video file and export as .m4a (AAC).
    private func extractAudio(from videoURL: URL, to audioURL: URL) async throws {
        let asset = AVAsset(url: videoURL)

        // Verify the asset has an audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            log("⚠️ No audio track found in recording")
            throw SystemRecordingError.noAudioTrack
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SystemRecordingError.exportFailed
        }

        // Remove existing file
        try? FileManager.default.removeItem(at: audioURL)

        exportSession.outputURL = audioURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if let error = exportSession.error {
            log("⛔ Export error: \(error.localizedDescription)")
            throw error
        }

        guard exportSession.status == .completed else {
            log("⛔ Export status: \(exportSession.status.rawValue)")
            throw SystemRecordingError.exportFailed
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startDate else { return }
                self.recordingTime = Date().timeIntervalSince(start)
                // Simulate audio level animation (ReplayKit doesn't provide real-time metering)
                let wave = sin(self.recordingTime * 4) * 0.25 + 0.35
                self.audioLevel = Float(max(0, min(1, wave + Double.random(in: -0.08...0.08))))
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Errors

enum SystemRecordingError: LocalizedError {
    case notAvailable
    case notRecording
    case noAudioTrack
    case exportFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .notAvailable:    return "屏幕录制在当前设备上不可用（模拟器不支持）"
        case .notRecording:    return "当前没有在录制"
        case .noAudioTrack:    return "录制的视频中没有音频轨道"
        case .exportFailed:    return "音频导出失败"
        case .permissionDenied: return "屏幕录制权限被拒绝，请在系统设置中打开"
        }
    }
}
