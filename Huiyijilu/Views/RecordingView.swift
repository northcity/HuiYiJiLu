//
//  RecordingView.swift
//  Huiyijilu
//

import SwiftUI
import SwiftData
import ReplayKit

// MARK: - Recording Mode

enum RecordingMode: String, CaseIterable {
    case microphone = "麦克风"
    case system     = "内录"
}

/// Full-screen recording view with timer and controls.
/// Supports two modes: microphone-only (AVAudioRecorder) and system recording (ReplayKit).
struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var recorder = AudioRecorderService()
    @StateObject private var systemRecorder = SystemAudioRecorderService()
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var aiService = AIService()
    @StateObject private var workflowService = BailianWorkflowService()

    @AppStorage("recording_mode") private var recordingMode: String = RecordingMode.microphone.rawValue
    private var mode: RecordingMode { RecordingMode(rawValue: recordingMode) ?? .microphone }

    @State private var isProcessing = false
    @State private var processingStage = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentMeeting: Meeting?

    // Unified accessors
    private var isRecordingActive: Bool {
        mode == .microphone ? recorder.isRecording : systemRecorder.isRecording
    }
    private var isPaused: Bool { mode == .microphone ? recorder.isPaused : false }
    private var currentTime: TimeInterval {
        mode == .microphone ? recorder.recordingTime : systemRecorder.recordingTime
    }
    private var currentLevel: Float {
        mode == .microphone ? recorder.audioLevel : systemRecorder.audioLevel
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: isRecordingActive && !isPaused
                    ? (mode == .system
                        ? [Color.purple.opacity(0.1), Color(.systemBackground)]
                        : [Color.red.opacity(0.1), Color(.systemBackground)])
                    : [Color(.systemBackground), Color(.systemBackground)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                // Header
                HStack {
                    Button("取消") {
                        cancelRecording()
                    }
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal)

                Spacer()

                if isProcessing {
                    processingView
                } else {
                    recordingContent
                }

                Spacer()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Recording Content

    private var recordingContent: some View {
        VStack(spacing: 36) {

            // Mode picker (only shown before recording starts)
            if !isRecordingActive {
                modePicker
            } else {
                // Active mode badge
                HStack(spacing: 6) {
                    Image(systemName: mode == .system ? "record.circle" : "mic.fill")
                        .font(.caption)
                    Text(mode == .system ? "系统内录模式" : "麦克风录音")
                        .font(.caption).fontWeight(.medium)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(mode == .system ? Color.purple.opacity(0.15) : Color.red.opacity(0.15))
                .foregroundStyle(mode == .system ? .purple : .red)
                .clipShape(Capsule())
            }

            // Waveform
            waveformView

            // Timer
            Text(formatTime(currentTime))
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(isRecordingActive && !isPaused ? .primary : .secondary)

            // Status text
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)

            // Controls
            recordingControls
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        VStack(spacing: 10) {
            Picker("录音模式", selection: $recordingMode) {
                ForEach(RecordingMode.allCases, id: \.rawValue) { m in
                    Text(m.rawValue).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Group {
                if mode == .system {
                    if systemRecorder.isAvailable {
                        Label("录制系统声音 + 麦克风", systemImage: "speaker.wave.2.fill")
                            .foregroundStyle(.purple)
                    } else {
                        Label("当前设备不支持内录", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label("仅录制麦克风音频", systemImage: "mic.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    private var statusText: String {
        if !isRecordingActive {
            return mode == .system ? "点击开始系统内录" : "点击开始录音"
        }
        if isPaused { return "已暂停" }
        return mode == .system ? "系统录制中..." : "录音中..."
    }

    // MARK: - Waveform

    private var waveformView: some View {
        HStack(spacing: 4) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecordingActive && !isPaused
                          ? (mode == .system ? Color.purple : Color.red)
                          : Color.gray.opacity(0.3))
                    .frame(width: 4, height: barHeight(for: i))
                    .animation(
                        .easeInOut(duration: 0.3).delay(Double(i) * 0.02),
                        value: currentLevel
                    )
            }
        }
        .frame(height: 60)
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isRecordingActive && !isPaused else { return 8 }
        let base: CGFloat = 8
        let variation = CGFloat(currentLevel) * 52
        let offset = sin(Double(index) * 0.5 + currentTime * 3) * 0.5 + 0.5
        return base + variation * CGFloat(offset)
    }

    // MARK: - Controls

    private var recordingControls: some View {
        HStack(spacing: 50) {
            if isRecordingActive {
                // Pause / Resume (only for microphone mode)
                if mode == .microphone {
                    Button {
                        if recorder.isPaused {
                            recorder.resumeRecording()
                        } else {
                            recorder.pauseRecording()
                        }
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.gray))
                    }
                }

                if mode == .system {
                    // System mode: show broadcast picker again (user taps to end broadcast)
                    VStack(spacing: 8) {
                        BroadcastButton(isRecording: true)
                        Text("点击结束录制")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Also show a "Process" button to collect audio after broadcast ends
                    Button {
                        stopAndProcess()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                            Text("处理")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color.blue))
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                    }
                } else {
                    // Mic mode: Stop button
                    Button {
                        stopAndProcess()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(Color.red))
                            .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
                    }
                }
            } else {
                if mode == .system {
                    // System mode: show broadcast picker (triggers "开始直播" dialog)
                    VStack(spacing: 12) {
                        BroadcastButton(isRecording: false)
                        Text("点击开始系统录制")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Mic mode: Start button
                    Button {
                        startRecording()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(Circle().fill(Color.red))
                            .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
                    }
                }
            }
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text(processingStage)
                .font(.headline)

            if transcriptionService.isTranscribing {
                ProgressView(value: transcriptionService.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        Task {
            let authorized = await TranscriptionService.requestAuthorization()
            guard authorized else {
                errorMessage = "语音识别权限未授权"
                showError = true
                return
            }

            do {
                // System mode uses broadcast picker — no programmatic start needed
                try recorder.startRecording()
            } catch {
                errorMessage = "录音启动失败: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func cancelRecording() {
        if mode == .microphone && recorder.isRecording {
            recorder.stopRecording()
        }
        // System mode: can't programmatically stop broadcast; user must tap broadcast picker
        dismiss()
    }

    private func stopAndProcess() {
        Task {
            var fileName: String
            var duration: TimeInterval

            if mode == .system {
                // Collect audio from the broadcast extension's shared container
                do {
                    let result = try await systemRecorder.collectRecordedAudio()
                    fileName = result.fileName
                    duration = result.duration
                } catch {
                    errorMessage = "获取录制音频失败: \(error.localizedDescription)"
                    showError = true
                    return
                }
            } else {
                let result = recorder.stopRecording()
                fileName = result.fileName
                duration = result.duration
            }

            isProcessing = true

            // Create meeting
            let meeting = Meeting(title: "Processing...", date: Date(), duration: duration)
            meeting.audioFileName = fileName
            meeting.status = .transcribing
            modelContext.insert(meeting)
            try? modelContext.save()
            currentMeeting = meeting

            await processRecording(meeting: meeting)
        }
    }

    private func processRecording(meeting: Meeting) async {
        // Step 1: Transcribe
        processingStage = "转写音频中..."
        meeting.status = .transcribing

        guard let audioURL = meeting.audioFileURL else {
            meeting.status = .failed
            errorMessage = "找不到音频文件"
            showError = true
            isProcessing = false
            return
        }

        do {
            let transcript = try await transcriptionService.transcribe(audioFileURL: audioURL)
            meeting.transcript = transcript

            // Step 2: AI Summary
            processingStage = "AI 分析中..."
            meeting.status = .summarizing

            if !UserDefaults.standard.string(forKey: "openai_api_key").isNilOrEmpty {
                let summaryResult = try await aiService.generateSummary(transcript: transcript)
                meeting.title = summaryResult.title
                meeting.summary = summaryResult.summary
                meeting.keyPointsList = summaryResult.keyPoints

                for item in summaryResult.actionItems {
                    let actionItem = ActionItem(title: item.title, assignee: item.assignee, meeting: meeting)
                    modelContext.insert(actionItem)
                }

                // Step 3: Rich notes (workflow → LLM fallback)
                processingStage = "生成图文纪要..."
                await generateRichNotesWithFallback(for: meeting, transcript: transcript)
            } else {
                meeting.title = generateBasicTitle(from: transcript)
                meeting.summary = "请在设置中配置 API Key 以启用 AI 总结"
            }

            meeting.status = .completed
            try? modelContext.save()
            isProcessing = false
            dismiss()

        } catch {
            meeting.status = .failed
            meeting.title = "会议 \(meeting.date.formatted(date: .abbreviated, time: .shortened))"
            try? modelContext.save()
            errorMessage = error.localizedDescription
            showError = true
            isProcessing = false
            dismiss()
        }
    }

    /// Try Bailian workflow first; fall back to LLM.
    private func generateRichNotesWithFallback(for meeting: Meeting, transcript: String) async {
        if workflowService.isConfigured, let audioURL = meeting.audioFileURL {
            if let notes = try? await workflowService.generateRichNotes(audioFileURL: audioURL),
               !notes.contains("视频为空"), !notes.contains("请提供视频"), notes.count > 30 {
                meeting.richNotes = notes
                return
            }
        }
        if let notes = try? await aiService.generateRichNotes(transcript: transcript) {
            meeting.richNotes = notes
        }
    }

    private func generateBasicTitle(from transcript: String) -> String {
        let words = transcript.prefix(50).components(separatedBy: .whitespacesAndNewlines).prefix(6)
        let title = words.joined(separator: " ")
        return title.isEmpty ? "会议 \(Date().formatted(date: .abbreviated, time: .shortened))" : title + "..."
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - String Extension

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
