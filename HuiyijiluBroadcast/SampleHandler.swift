//
//  SampleHandler.swift
//  HuiyijiluBroadcast
//
//  ReplayKit Broadcast Upload Extension — captures system-wide audio
//  and writes it to the App Group shared container.
//

import ReplayKit
import AVFoundation

/// Receives system-wide audio/video buffers from ReplayKit broadcast.
/// Writes audio (app audio + microphone) to a shared .m4a file
/// in the App Group container so the main app can access it.
class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - App Group Config
    static let appGroupID = "group.com.ceshi.ceshimainapp"
    static let audioFileName = "broadcast_recording.m4a"
    static let recordingFlagFile = "is_recording"  // exists while recording

    // MARK: - Writer State
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var isWriterStarted = false
    private var sessionStartTime: CMTime = .zero

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
    }

    private var audioFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.audioFileName)
    }

    private var flagFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.recordingFlagFile)
    }

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        NSLog("[Broadcast] broadcastStarted")
        setupWriter()
        // Create a flag file to signal the main app that recording is active
        if let flagURL = flagFileURL {
            try? Data().write(to: flagURL)
        }
        // Post Darwin notification
        postNotification("com.huiyijilu.broadcast.started")
    }

    override func broadcastPaused() {
        NSLog("[Broadcast] paused")
    }

    override func broadcastResumed() {
        NSLog("[Broadcast] resumed")
    }

    override func broadcastFinished() {
        NSLog("[Broadcast] finished — finalizing audio")
        finalizeWriter()
        // Remove flag file
        if let flagURL = flagFileURL {
            try? FileManager.default.removeItem(at: flagURL)
        }
        // Notify main app
        postNotification("com.huiyijilu.broadcast.stopped")
    }

    // MARK: - Sample Processing

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .audioApp:
            writeSample(sampleBuffer)
        case .audioMic:
            writeSample(sampleBuffer)
        case .video:
            break  // Ignore video frames — we only need audio
        @unknown default:
            break
        }
    }

    // MARK: - AVAssetWriter Setup

    private func setupWriter() {
        guard let outputURL = audioFileURL else {
            NSLog("[Broadcast] ⛔ No shared container URL")
            return
        }

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            NSLog("[Broadcast] ⛔ AVAssetWriter init failed: \(error)")
            return
        }

        // Audio settings: AAC, 44.1kHz, mono
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        guard let writer = assetWriter, let input = audioInput else { return }

        if writer.canAdd(input) {
            writer.add(input)
        }

        isWriterStarted = false
        NSLog("[Broadcast] ✅ Writer configured → \(outputURL.lastPathComponent)")
    }

    private func writeSample(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter, let input = audioInput else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if !isWriterStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: startTime)
            sessionStartTime = startTime
            isWriterStarted = true
            NSLog("[Broadcast] ✅ Writer started at \(startTime.seconds)s")
        }

        guard writer.status == .writing else {
            if writer.status == .failed {
                NSLog("[Broadcast] ⛔ Writer failed: \(writer.error?.localizedDescription ?? "?")")
            }
            return
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    private func finalizeWriter() {
        guard let writer = assetWriter, isWriterStarted else { return }

        audioInput?.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            NSLog("[Broadcast] ✅ Writer finalized — status: \(writer.status.rawValue)")
            semaphore.signal()
        }
        semaphore.wait()
    }

    // MARK: - Darwin Notification

    private func postNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = name as CFString
        CFNotificationCenterPostNotification(center, CFNotificationName(cfName), nil, nil, true)
    }
}
