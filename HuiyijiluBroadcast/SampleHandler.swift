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
    static let appGroupID = "group.com.test.testwatch"
    static let audioFileName = "broadcast_recording.m4a"
    static let recordingFlagFile = "is_recording"  // exists while recording
    static let debugLogFile = "broadcast_debug.log"

    // MARK: - Writer State
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var isSessionStarted = false
    private var sessionStartTime: CMTime = .zero
    private var sampleCount: Int = 0
    private let writeQueue = DispatchQueue(label: "com.huiyijilu.broadcast.writeQueue")
    
    /// The temporary URL where AVAssetWriter writes audio in the extension's own sandbox.
    /// After recording, this file is copied to the shared App Group container.
    private var tempAudioURL: URL {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("broadcast_temp_recording.m4a")
    }

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
    }

    private var audioFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.audioFileName)
    }

    private var flagFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.recordingFlagFile)
    }
    
    private var debugLogURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.debugLogFile)
    }

    /// Write debug logs to both NSLog and a shared file the main app can read
    private func debugLog(_ msg: String) {
        NSLog("[Broadcast] %@", msg)
        guard let url = debugLogURL else { return }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        sampleCount = 0

        // Clear previous debug log
        if let url = debugLogURL {
            try? FileManager.default.removeItem(at: url)
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? "unknown"
        debugLog("broadcastStarted — extension bundle ID: \(ownBundleID)")
        debugLog("ℹ️  主 App 需要在 BroadcastPickerView.preferredExtension 中设置为: \(ownBundleID)")
        
        // Verify shared container is accessible
        if let containerURL = sharedContainerURL {
            debugLog("✅ Shared container: \(containerURL.path)")
            if let files = try? FileManager.default.contentsOfDirectory(atPath: containerURL.path) {
                debugLog("Container contents before setup: \(files)")
            }
        } else {
            debugLog("⛔ Shared container NOT accessible!")
        }
        
        setupWriter()
        
        // Create a flag file to signal the main app that recording is active
        if let flagURL = flagFileURL {
            try? Data().write(to: flagURL)
            debugLog("Flag file created")
        }
        
        // Post Darwin notification
        postNotification("com.huiyijilu.broadcast.started")
    }

    override func broadcastPaused() {
        debugLog("paused")
    }

    override func broadcastResumed() {
        debugLog("resumed")
    }

    override func broadcastFinished() {
        debugLog("finished — total samples written: \(sampleCount)")
        finalizeWriter()
        
        // Copy finalized audio from temp directory to shared App Group container
        copyAudioToSharedContainer()
        
        // Remove flag file
        if let flagURL = flagFileURL {
            try? FileManager.default.removeItem(at: flagURL)
        }
        // Notify main app
        postNotification("com.huiyijilu.broadcast.stopped")
    }
    
    /// Copy the finalized audio file from the extension's temp directory to the shared container
    private func copyAudioToSharedContainer() {
        let sourceURL = tempAudioURL
        guard let destURL = audioFileURL else {
            debugLog("⛔ Cannot copy — shared container URL is nil")
            return
        }
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            debugLog("⛔ Temp audio file not found at \(sourceURL.path)")
            return
        }
        
        // Check source file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let size = attrs[.size] as? UInt64 {
            debugLog("Temp audio file size: \(size) bytes")
        }
        
        // Remove existing file in shared container
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            debugLog("✅ Audio copied to shared container: \(destURL.lastPathComponent)")
            
            // Verify copy
            if let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
               let size = attrs[.size] as? UInt64 {
                debugLog("✅ Shared container audio verified: \(size) bytes")
            }
        } catch {
            debugLog("⛔ Failed to copy audio to shared container: \(error)")
        }
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: sourceURL)
        
        // List final container contents
        if let containerURL = sharedContainerURL,
           let files = try? FileManager.default.contentsOfDirectory(atPath: containerURL.path) {
            debugLog("Final container contents: \(files)")
        }
    }

    // MARK: - Sample Processing

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .audioApp:
            writeQueue.sync {
                sampleCount += 1
                writeSample(sampleBuffer, source: "app")
            }
        case .audioMic:
            writeQueue.sync {
                sampleCount += 1
                writeSample(sampleBuffer, source: "mic")
            }
        case .video:
            break  // Ignore video frames — we only need audio
        @unknown default:
            break
        }
    }

    // MARK: - AVAssetWriter Setup

    private func setupWriter() {
        let outputURL = tempAudioURL

        debugLog("Setting up writer at TEMP path: \(outputURL.path)")

        // Remove existing temp file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
                debugLog("Removed existing temp audio file")
            } catch {
                debugLog("⚠️ Failed to remove existing temp file: \(error)")
            }
        }

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
            debugLog("✅ AVAssetWriter created for temp path")
        } catch {
            debugLog("⛔ AVAssetWriter init failed: \(error)")
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

        guard let writer = assetWriter, let input = audioInput else {
            debugLog("⛔ Writer or input is nil after creation")
            return
        }

        if writer.canAdd(input) {
            writer.add(input)
            debugLog("✅ Audio input added to writer")
        } else {
            debugLog("⛔ Cannot add audio input to writer!")
            return
        }

        // Start writing IMMEDIATELY — this creates the output file on disk
        let success = writer.startWriting()
        if success {
            debugLog("✅ Writer.startWriting() succeeded — temp file created")
        } else {
            debugLog("⛔ Writer.startWriting() failed: \(writer.error?.localizedDescription ?? "unknown")")
            debugLog("⛔ Writer error detail: \(String(describing: writer.error))")
        }
        
        isSessionStarted = false
    }

    private func writeSample(_ sampleBuffer: CMSampleBuffer, source: String) {
        guard let writer = assetWriter, let input = audioInput else {
            if sampleCount <= 3 {
                debugLog("⚠️ writeSample called but writer/input is nil (source: \(source))")
            }
            return
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            if sampleCount <= 3 {
                debugLog("⚠️ Sample buffer data not ready (source: \(source))")
            }
            return
        }
        
        guard writer.status == .writing else {
            if writer.status == .failed {
                if sampleCount <= 5 {
                    debugLog("⛔ Writer in failed state: \(writer.error?.localizedDescription ?? "?") (source: \(source))")
                }
            } else {
                if sampleCount <= 3 {
                    debugLog("⚠️ Writer status is \(writer.status.rawValue), not writing (source: \(source))")
                }
            }
            return
        }

        if !isSessionStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: startTime)
            sessionStartTime = startTime
            isSessionStarted = true
            
            // Log format description for debugging
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                debugLog("✅ Session started (source: \(source)) at \(startTime.seconds)s, format: \(mediaType)/\(mediaSubType)")
            } else {
                debugLog("✅ Session started (source: \(source)) at \(startTime.seconds)s")
            }
        }

        if input.isReadyForMoreMediaData {
            let appended = input.append(sampleBuffer)
            if !appended && sampleCount <= 5 {
                debugLog("⚠️ Failed to append sample #\(sampleCount) (source: \(source))")
            }
        } else if sampleCount <= 5 {
            debugLog("⚠️ Input not ready for more data at sample #\(sampleCount)")
        }
        
        // Log progress periodically
        if sampleCount == 1 {
            debugLog("✅ First audio sample written! (source: \(source))")
        } else if sampleCount % 500 == 0 {
            debugLog("Progress: \(sampleCount) samples written")
        }
    }

    private func finalizeWriter() {
        guard let writer = assetWriter else {
            debugLog("⚠️ No writer to finalize")
            return
        }
        
        guard isSessionStarted else {
            debugLog("⚠️ Writer session was never started (no audio samples received)")
            debugLog("Writer status: \(writer.status.rawValue)")
            // Cancel the writer if it was started but no session began
            if writer.status == .writing {
                writer.cancelWriting()
                debugLog("Writer cancelled (no session)")
            }
            return
        }

        audioInput?.markAsFinished()
        
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { [weak self] in
            self?.debugLog("✅ Writer finalized — status: \(writer.status.rawValue)")
            if writer.status == .failed {
                self?.debugLog("⛔ Writer error: \(writer.error?.localizedDescription ?? "unknown")")
            }
            semaphore.signal()
        }
        
        // Wait up to 5 seconds for finalization
        let result = semaphore.wait(timeout: .now() + 5)
        if result == .timedOut {
            debugLog("⚠️ Writer finalization timed out!")
        }
    }

    // MARK: - Darwin Notification

    private func postNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = name as CFString
        CFNotificationCenterPostNotification(center, CFNotificationName(cfName), nil, nil, true)
    }
}
