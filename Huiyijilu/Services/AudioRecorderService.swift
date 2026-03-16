//
//  AudioRecorderService.swift
//  Huiyijilu
//

import Foundation
import AVFoundation
import Combine

/// Audio recording service - handles microphone recording
@MainActor
class AudioRecorderService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private var accumulatedTime: TimeInterval = 0

    private(set) var currentFileName: String = ""

    override init() {
        super.init()
    }

    /// Setup audio session for recording
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }

    /// Start a new recording
    func startRecording() throws {
        try setupAudioSession()

        // Create recordings directory
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        if !FileManager.default.fileExists(atPath: recordingsDir.path) {
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        // Generate unique file name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        currentFileName = "meeting_\(dateFormatter.string(from: Date())).m4a"
        let fileURL = recordingsDir.appendingPathComponent(currentFileName)

        // Audio settings - high quality for speech
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        isRecording = true
        isPaused = false
        accumulatedTime = 0
        startTime = Date()

        startTimer()
    }

    /// Pause recording
    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        if let start = startTime {
            accumulatedTime += Date().timeIntervalSince(start)
        }
        startTime = nil
        stopTimer()
    }

    /// Resume recording
    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        startTime = Date()
        startTimer()
    }

    /// Stop recording and return file name
    @discardableResult
    func stopRecording() -> (fileName: String, duration: TimeInterval) {
        audioRecorder?.stop()
        stopTimer()

        if let start = startTime {
            accumulatedTime += Date().timeIntervalSince(start)
        }

        let result = (fileName: currentFileName, duration: accumulatedTime)

        isRecording = false
        isPaused = false
        let finalTime = recordingTime
        recordingTime = 0
        startTime = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        return (fileName: currentFileName, duration: finalTime)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if let start = self.startTime {
                    self.recordingTime = self.accumulatedTime + Date().timeIntervalSince(start)
                }
                self.audioRecorder?.updateMeters()
                let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                // Normalize from -160..0 to 0..1
                self.audioLevel = max(0, min(1, (level + 50) / 50))
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
