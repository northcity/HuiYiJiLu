//
//  SystemAudioRecorderService.swift
//  Huiyijilu
//
//  管理 ReplayKit Broadcast Extension 的生命周期。
//  通过 App Group 共享容器读取扩展录制的音频文件，
//  通过 Darwin Notification 感知扩展的开始/停止事件。
//

import Foundation
import ReplayKit
import AVFoundation
import Combine
import ActivityKit

/// Manages the ReplayKit Broadcast Extension lifecycle.
/// The extension writes audio to the App Group shared container;
/// this service monitors for start/stop events and copies the audio
/// to the app's Recordings directory for processing.
@MainActor
class SystemAudioRecorderService: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    /// Set to true when broadcast stops and audio is ready to be collected
    @Published var hasPendingAudio = false

    // MARK: - Constants
    static let appGroupID = "group.com.test.testwatch"
    static let audioFileName = "broadcast_recording.m4a"
    static let recordingFlagFile = "is_recording"
    static let debugLogFile = "broadcast_debug.log"
    /// Must match the PRODUCT_BUNDLE_IDENTIFIER of the HuiyijiluBroadcast target in project.pbxproj.
    /// Debug:   com.ceshi.ceshimainapp.watchkitapp.widget
    /// Release: com.ceshi.ceshimainapp.widget
    #if DEBUG
    static let broadcastExtensionBundleID = "com.ceshi.ceshimainapp.watchkitapp.widget"
    static let currentBuildConfig = "DEBUG"
    #else
    static let broadcastExtensionBundleID = "com.ceshi.ceshimainapp.widget"
    static let currentBuildConfig = "RELEASE"
    #endif

    // MARK: - Internal
    private var timer: Timer?
    private var startDate: Date?
    private(set) var currentFileName: String = ""
    private var liveActivity: Activity<RecordingAttributes>?

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
    }

    private var sharedAudioURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.audioFileName)
    }

    private var flagFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.recordingFlagFile)
    }
    
    private var debugLogURL: URL? {
        sharedContainerURL?.appendingPathComponent(Self.debugLogFile)
    }

    private var recordingsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Recordings")
    }

    /// Whether the device supports screen recording (ReplayKit).
    /// Uses RPScreenRecorder system check — NOT app-group availability.
    var isAvailable: Bool { RPScreenRecorder.shared().isAvailable }

    /// Whether the App Group shared container is accessible.
    /// If false, the broadcast extension can start but cannot save audio.
    var isAppGroupConfigured: Bool { sharedContainerURL != nil }

    private func log(_ msg: String) { print("[SystemRec] \(msg)") }

    // MARK: - Init / Deinit

    override init() {
        super.init()
        log("Device supports recording: \(RPScreenRecorder.shared().isAvailable)")
        log("App Group configured: \(sharedContainerURL != nil)")
        log("📌 broadcastExtensionBundleID = \(Self.broadcastExtensionBundleID)")
        log("📌 Build config: \(Self.currentBuildConfig)")
        if let url = sharedContainerURL {
            log("Shared container: \(url.path)")
        } else {
            log("⚠️ App Group container NOT accessible — 请在 Apple Developer Portal 配置 App Group")
        }
        // Register for Darwin notifications from the broadcast extension
        registerDarwinNotifications()
        // Check if a broadcast was already running (e.g. app relaunched during broadcast)
        checkExistingBroadcast()
    }

    // MARK: - Darwin Notification Observers

    private func registerDarwinNotifications() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        // Broadcast started
        CFNotificationCenterAddObserver(
            center, Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let service = Unmanaged<SystemAudioRecorderService>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    service.handleBroadcastStarted()
                }
            },
            "com.huiyijilu.broadcast.started" as CFString,
            nil, .deliverImmediately
        )

        // Broadcast stopped
        CFNotificationCenterAddObserver(
            center, Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let service = Unmanaged<SystemAudioRecorderService>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    service.handleBroadcastStopped()
                }
            },
            "com.huiyijilu.broadcast.stopped" as CFString,
            nil, .deliverImmediately
        )
    }

    private func checkExistingBroadcast() {
        if let flagURL = flagFileURL, FileManager.default.fileExists(atPath: flagURL.path) {
            log("🔄 Detected ongoing broadcast — resuming tracking")
            handleBroadcastStarted()
        }
    }

    // MARK: - Broadcast Events

    private func handleBroadcastStarted() {
        guard !isRecording else { return }
        log("▶ Broadcast started")
        isRecording = true
        startDate = Date()
        startTimer()
        startLiveActivity()
    }

    private func handleBroadcastStopped() {
        guard isRecording else { return }
        log("⏹ Broadcast stopped — audio pending for collection")
        stopTimer()
        isRecording = false
        hasPendingAudio = true
        endLiveActivity()
    }

    // MARK: - Live Activity (Dynamic Island)

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("⚠️ Live Activities not enabled on this device")
            return
        }

        let attributes = RecordingAttributes(startDate: Date())
        let initialState = RecordingAttributes.ContentState(
            elapsedSeconds: 0,
            mode: "内录",
            isActive: true
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            liveActivity = try Activity<RecordingAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            log("✅ Live Activity started: \(liveActivity?.id ?? "nil")")
        } catch {
            log("❌ Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    private func updateLiveActivity() {
        guard let activity = liveActivity else { return }
        let state = RecordingAttributes.ContentState(
            elapsedSeconds: Int(recordingTime),
            mode: "内录",
            isActive: true
        )
        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        let finalState = RecordingAttributes.ContentState(
            elapsedSeconds: Int(recordingTime),
            mode: "内录",
            isActive: false
        )
        Task {
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .default)
            log("✅ Live Activity ended")
        }
        liveActivity = nil
    }

    // MARK: - Wait for Broadcast to Stop

    /// Wait until the broadcast has fully stopped (flag file removed) or timeout.
    /// Call this before collectRecordedAudio() to ensure the extension has finished.
    func waitForBroadcastToStop(timeout: TimeInterval = 10) async {
        guard isRecording else {
            log("Broadcast already stopped")
            return
        }
        log("⏳ Waiting for broadcast to stop (timeout: \(timeout)s)...")
        let start = Date()
        while isRecording && Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        }
        if isRecording {
            log("⚠️ Broadcast did not stop within timeout — forcing state reset")
            stopTimer()
            isRecording = false
            endLiveActivity()
        } else {
            log("✅ Broadcast stopped")
        }
    }

    // MARK: - Collect Audio

    /// Copy the recorded audio from the shared container to the app's Recordings directory.
    /// Includes a polling mechanism to wait for the extension to finish writing the file.
    /// Returns the local file name and duration.
    func collectRecordedAudio() async throws -> (fileName: String, duration: TimeInterval) {
        // Save duration BEFORE resetting (don't lose it on error)
        let duration = recordingTime

        guard let containerURL = sharedContainerURL else {
            log("⛔ App Group container is nil — entitlements misconfigured")
            throw SystemRecordingError.appGroupNotAccessible
        }

        guard let sourceURL = sharedAudioURL else {
            throw SystemRecordingError.noAudioTrack
        }

        log("📂 Looking for audio at: \(sourceURL.path)")
        log("📂 Shared container: \(containerURL.path)")

        // List files in shared container for debugging
        if let files = try? FileManager.default.contentsOfDirectory(atPath: containerURL.path) {
            log("📂 Container contents: \(files)")
        }

        // Poll for the audio file to appear (extension may still be finalizing)
        let maxWait: TimeInterval = 8
        let pollInterval: UInt64 = 500_000_000 // 0.5s in nanoseconds
        let startTime = Date()
        var fileFound = false

        while Date().timeIntervalSince(startTime) < maxWait {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                // Also check file size > 0 to ensure it's not an empty placeholder
                if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
                   let size = attrs[.size] as? UInt64, size > 0 {
                    log("✅ Audio file found (\(size) bytes) after \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s")
                    fileFound = true
                    break
                } else {
                    log("⏳ File exists but is empty, waiting for writer to flush...")
                }
            } else {
                log("⏳ File not yet available, polling... (\(String(format: "%.1f", Date().timeIntervalSince(startTime)))s)")
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }

        guard fileFound else {
            log("⛔ Audio file not found after \(maxWait)s wait")
            // List container contents again for diagnosis
            if let files = try? FileManager.default.contentsOfDirectory(atPath: containerURL.path) {
                log("📂 Final container contents: \(files)")
            }
            // Read broadcast extension's debug log for diagnostics
            if let logURL = debugLogURL,
               let logContent = try? String(contentsOf: logURL, encoding: .utf8) {
                log("📋 Broadcast Extension Log:\n\(logContent)")
            }
            throw SystemRecordingError.noAudioTrack
        }

        // NOW reset state (only after confirming file exists)
        recordingTime = 0
        startDate = nil
        hasPendingAudio = false

        // Ensure recordings directory
        if !FileManager.default.fileExists(atPath: recordingsDir.path) {
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        currentFileName = "meeting_sys_\(fmt.string(from: Date())).m4a"
        let destURL = recordingsDir.appendingPathComponent(currentFileName)

        // Remove existing
        try? FileManager.default.removeItem(at: destURL)

        // Copy from shared container to app sandbox
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            log("⛔ Failed to copy file: \(error)")
            throw SystemRecordingError.exportFailed
        }

        // Verify copied file
        guard FileManager.default.fileExists(atPath: destURL.path) else {
            log("⛔ Copied file not found at destination")
            throw SystemRecordingError.exportFailed
        }

        // Clean up shared audio
        try? FileManager.default.removeItem(at: sourceURL)
        // Also clean up flag file if still present
        if let flagURL = flagFileURL {
            try? FileManager.default.removeItem(at: flagURL)
        }

        log("✅ Audio copied → \(currentFileName) (\(String(format: "%.1f", duration))s)")
        return (fileName: currentFileName, duration: duration)
    }

    // MARK: - Timer

    private func startTimer() {
        var lastActivityUpdate: Int = -1
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startDate else { return }
                self.recordingTime = Date().timeIntervalSince(start)
                let wave = sin(self.recordingTime * 4) * 0.25 + 0.35
                self.audioLevel = Float(max(0, min(1, wave + Double.random(in: -0.08...0.08))))

                // Update Live Activity every second (not every 0.1s to avoid throttling)
                let currentSecond = Int(self.recordingTime)
                if currentSecond != lastActivityUpdate {
                    lastActivityUpdate = currentSecond
                    self.updateLiveActivity()
                }
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
    case appGroupNotAccessible

    var errorDescription: String? {
        switch self {
        case .notAvailable:         return "系统内录在当前设备上不可用"
        case .notRecording:         return "当前没有在录制"
        case .noAudioTrack:         return "录制的音频文件未找到。请确保:\n1. 先点击停止录制按钮结束录制\n2. 等待几秒后再点击处理"
        case .exportFailed:         return "音频导出失败"
        case .permissionDenied:     return "录制权限被拒绝"
        case .appGroupNotAccessible: return "App Group 共享容器不可用，请检查 Entitlements 配置"
        }
    }
}
