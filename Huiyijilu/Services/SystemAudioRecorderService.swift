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

    // MARK: - Constants
    static let appGroupID = "group.com.ceshi.ceshimainapp"
    static let audioFileName = "broadcast_recording.m4a"
    static let recordingFlagFile = "is_recording"
    /// Must match the value in HuiyijiluBroadcast target's bundle id in .pbxproj
    static let broadcastExtensionBundleID = "com.ceshi.ceshimainapp.widget"

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
        log("⏹ Broadcast stopped")
        stopTimer()
        isRecording = false
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

    // MARK: - Collect Audio

    /// Copy the recorded audio from the shared container to the app's Recordings directory.
    /// Returns the local file name and duration.
    func collectRecordedAudio() async throws -> (fileName: String, duration: TimeInterval) {
        let duration = recordingTime
        recordingTime = 0
        startDate = nil

        guard let sourceURL = sharedAudioURL,
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SystemRecordingError.noAudioTrack
        }

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
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Clean up shared audio
        try? FileManager.default.removeItem(at: sourceURL)

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

    var errorDescription: String? {
        switch self {
        case .notAvailable:     return "系统内录在当前设备上不可用"
        case .notRecording:     return "当前没有在录制"
        case .noAudioTrack:     return "未找到录制的音频文件"
        case .exportFailed:     return "音频导出失败"
        case .permissionDenied: return "录制权限被拒绝"
        }
    }
}
