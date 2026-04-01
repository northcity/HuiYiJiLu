//
//  RecordingView.swift
//  Huiyijilu
//
//  重构 v2：竞品风格录音页面
//  - 录音结束后直接保存，不触发 AI 处理
//  - 新增录音打点、笔记、拍照功能
//  - 圆形波纹动画 + REC 指示 + 日期显示 + 语言选择

import SwiftUI
import SwiftData
import ReplayKit

// MARK: - Recording Mode

enum RecordingMode: String, CaseIterable {
    case microphone = "麦克风"
    case system     = "内录"
}

// MARK: - Language Option

struct LanguageOption: Identifiable, Hashable {
    let id: String          // language_hints 值
    let label: String       // 显示名称
    let short: String       // 短显示

    static let options: [LanguageOption] = [
        .init(id: "zh", label: "中文", short: "中文"),
        .init(id: "en", label: "English", short: "英文"),
        .init(id: "zh-en", label: "中英混合", short: "中英"),
        .init(id: "ja", label: "日本語", short: "日语"),
        .init(id: "ko", label: "한국어", short: "韩语"),
        .init(id: "yue", label: "粤语", short: "粤语"),
        .init(id: "auto", label: "自动检测", short: "自动"),
    ]
}

/// 竞品风格全屏录音页面
struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var recorder = AudioRecorderService()
    @StateObject private var systemRecorder = SystemAudioRecorderService()

    @AppStorage("recording_mode") private var recordingMode: String = RecordingMode.microphone.rawValue
    @AppStorage("recording_language") private var selectedLanguage: String = "zh"
    private var mode: RecordingMode { RecordingMode(rawValue: recordingMode) ?? .microphone }

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    // 录音打点/笔记数据
    @State private var bookmarks: [RecordingBookmark] = []
    @State private var showBookmarkFeedback = false

    // REC 闪烁
    @State private var recBlink = false

    // Unified accessors
    private var isRecordingActive: Bool {
        mode == .microphone ? recorder.isRecording : (systemRecorder.isRecording || systemRecorder.hasPendingAudio)
    }
    private var isPaused: Bool { mode == .microphone ? recorder.isPaused : false }
    private var currentTime: TimeInterval {
        mode == .microphone ? recorder.recordingTime : systemRecorder.recordingTime
    }
    private var currentLevel: Float {
        mode == .microphone ? recorder.audioLevel : systemRecorder.audioLevel
    }
    private var accentColor: Color {
        mode == .system ? .purple : Color(red: 0.95, green: 0.3, blue: 0.2)
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    isRecordingActive && !isPaused
                        ? accentColor.opacity(0.06)
                        : Color(UIColor.secondarySystemBackground).opacity(0.5)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if isSaving {
                    Spacer()
                    savingView
                    Spacer()
                } else {
                    // === Top info area ===
                    topInfoArea
                        .padding(.top, 8)

                    Spacer()

                    // === Central wave + timer ===
                    centralArea

                    Spacer()

                    // === Control buttons ===
                    controlButtons
                        .padding(.bottom, 16)

                    // === Bottom toolbar (only when recording) ===
                    if isRecordingActive && !isPaused {
                        RecordingToolbar(currentTime: currentTime) { bookmark in
                            bookmarks.append(bookmark)
                            flashBookmarkFeedback()
                        }
                    }
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: systemRecorder.hasPendingAudio) { _, hasPending in
            if hasPending && mode == .system && !isSaving {
                stopAndSave()
            }
        }
        .onAppear {
            // REC 闪烁动画
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                recBlink = true
            }
        }
    }

    // MARK: - Top Info Area

    private var topInfoArea: some View {
        VStack(spacing: 10) {
            // Row 1: REC indicator + drag handle
            HStack {
                // REC 指示
                if isRecordingActive && !isPaused {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(recBlink ? 1.0 : 0.3)
                        Text("REC")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                } else if isPaused {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("暂停")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                // 拖拽指示条
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(.systemGray3))
                    .frame(width: 40, height: 5)

                Spacer()

                // 打点计数
                if !bookmarks.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                        Text("\(bookmarks.count)")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 20)

            // Row 2: Date + volume bars + language picker + reserved buttons
            HStack(alignment: .center, spacing: 12) {
                // 日期
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateString)
                        .font(.system(size: 22, weight: .bold))
                    // 音量条
                    volumeBars
                }

                Spacer()

                // 语言选择器
                if !isRecordingActive {
                    languagePicker
                } else {
                    // 录音中显示当前语言标签
                    let lang = LanguageOption.options.first(where: { $0.id == selectedLanguage })
                    Text(lang?.short ?? "中文")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                // 预留按钮: 文字转录
                Button { } label: {
                    Image(systemName: "a.square")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(.systemGray3))
                }
                .disabled(true)

                // 预留按钮: 说话人
                Button { } label: {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(.systemGray3))
                }
                .disabled(true)
            }
            .padding(.horizontal, 20)

            // Mode picker (only shown before recording starts)
            if !isRecordingActive {
                modePicker
                    .padding(.top, 4)
            }
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: Date())
    }

    // MARK: - Volume Bars (compact vertical style)

    private var volumeBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isRecordingActive && !isPaused ? Color.green : Color(.systemGray4))
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.easeInOut(duration: 0.15), value: currentLevel)
            }
        }
        .frame(height: 16)
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isRecordingActive && !isPaused else { return 4 }
        let base: CGFloat = 4
        let variation = CGFloat(currentLevel) * 12
        let offset = sin(Double(index) * 0.6 + currentTime * 4) * 0.5 + 0.5
        return base + variation * CGFloat(offset)
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        Menu {
            ForEach(LanguageOption.options) { lang in
                Button {
                    selectedLanguage = lang.id
                } label: {
                    HStack {
                        Text(lang.label)
                        if selectedLanguage == lang.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                let lang = LanguageOption.options.first(where: { $0.id == selectedLanguage })
                Text(lang?.short ?? "中文")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        VStack(spacing: 8) {
            Picker("录音模式", selection: $recordingMode) {
                ForEach(RecordingMode.allCases, id: \.rawValue) { m in
                    Text(m.rawValue).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

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

    // MARK: - Central Area (wave + timer)

    private var centralArea: some View {
        ZStack {
            // 圆形波纹动画
            CircularWaveView(
                audioLevel: currentLevel,
                isActive: isRecordingActive && !isPaused,
                accentColor: accentColor
            )

            // 计时器
            VStack(spacing: 4) {
                Text(formatTime(currentTime))
                    .font(.system(size: 52, weight: .light, design: .monospaced))
                    .foregroundStyle(isRecordingActive && !isPaused ? .primary : .secondary)

                if !isRecordingActive {
                    Text(mode == .system ? "点击开始系统内录" : "点击开始录音")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 50) {
            if isRecordingActive {
                // 左: 取消/关闭 (✕)
                Button {
                    cancelRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color(.systemGray5)))
                }

                // 中: 停止 (■)
                if mode == .system {
                    if systemRecorder.hasPendingAudio {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("正在获取录音...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 72, height: 72)
                    } else {
                        VStack(spacing: 6) {
                            BroadcastButton(isRecording: true)
                            Text("点击结束")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        stopAndSave()
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor)
                            .frame(width: 28, height: 28)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(.white))
                            .clipShape(Circle())
                            .shadow(color: accentColor.opacity(0.3), radius: 8, y: 4)
                    }
                }

                // 右: 暂停/继续 (⏸/▶) — 仅麦克风模式
                if mode == .microphone {
                    Button {
                        if recorder.isPaused {
                            recorder.resumeRecording()
                        } else {
                            recorder.pauseRecording()
                        }
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color(.systemGray5)))
                    }
                }
            } else {
                // 未录音状态：开始按钮
                if mode == .system {
                    VStack(spacing: 10) {
                        BroadcastButton(isRecording: false)
                        Text("点击开始系统录制")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        startRecording()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(Circle().fill(accentColor))
                            .shadow(color: accentColor.opacity(0.3), radius: 8, y: 4)
                    }
                }
            }
        }
    }

    // MARK: - Saving View

    private var savingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("录音已保存")
                .font(.title2)
                .fontWeight(.semibold)

            if !bookmarks.isEmpty {
                Text("包含 \(bookmarks.count) 个标记")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        do {
            try recorder.startRecording()
        } catch {
            errorMessage = "录音启动失败: \(error.localizedDescription)"
            showError = true
        }
    }

    private func cancelRecording() {
        if mode == .microphone && recorder.isRecording {
            recorder.stopRecording()
            // 删除取消的录音文件
            if !recorder.currentFileName.isEmpty {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let fileURL = docs.appendingPathComponent("Recordings").appendingPathComponent(recorder.currentFileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        dismiss()
    }

    /// 停止录音 → 直接保存 → dismiss（不触发 AI 处理）
    private func stopAndSave() {
        Task {
            var fileName: String
            var duration: TimeInterval

            if mode == .system {
                isSaving = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                do {
                    let result = try await systemRecorder.collectRecordedAudio()
                    fileName = result.fileName
                    duration = result.duration
                } catch {
                    errorMessage = "获取录制音频失败: \(error.localizedDescription)"
                    showError = true
                    isSaving = false
                    return
                }
            } else {
                let result = recorder.stopRecording()
                fileName = result.fileName
                duration = result.duration
                isSaving = true
            }

            // 创建 Meeting，状态为 saved（不触发 AI）
            let dateStr = Date().formatted(date: .abbreviated, time: .shortened)
            let meeting = Meeting(title: "录音 \(dateStr)", date: Date(), duration: duration)
            meeting.audioFileName = fileName
            meeting.status = .saved
            meeting.languageCode = selectedLanguage
            meeting.sourceType = mode == .system ? "system" : "microphone"
            meeting.bookmarksList = bookmarks
            modelContext.insert(meeting)
            try? modelContext.save()

            // 短暂展示保存成功，然后 dismiss
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        }
    }

    private func flashBookmarkFeedback() {
        withAnimation(.easeInOut(duration: 0.2)) { showBookmarkFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation { showBookmarkFeedback = false }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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
