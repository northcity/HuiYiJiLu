//
//  MeetingDetailView.swift
//  Huiyijilu
//
//  重构后的会议详情页 — 长滚动页，合并3路AI纪要为统一展示

import SwiftUI
import SwiftData
import SafariServices

/// Lightweight Identifiable wrapper so we can use .sheet(item:) with a URL
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// Meeting detail page - unified scrollable layout replacing 5-tab design
struct MeetingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting

    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var aiService = AIService()
    @StateObject private var workflowService = BailianWorkflowService()
    @StateObject private var tingwuService = TingWuService()
    @StateObject private var asrService = AliyunASRService()

    @State private var isRetrying = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var openWebURL: IdentifiableURL? = nil
    @State private var isTranscriptExpanded = false
    @State private var showGenerateOptions = false
    @State private var selectedAITasks: Set<AIProcessingTask> = [.title, .summary, .actionItems]

    /// Extract the first https:// URL from arbitrary text using NSDataDetector
    private func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.first?.url
    }

    // MARK: - Unified Notes Priority

    /// Determines which AI output to show as the primary notes
    private enum NotesSource {
        case tingwu       // 通义听悟（最完整）
        case richNotes    // 百炼工作流 / AI Markdown
        case summary      // 基础AI摘要
        case none         // 无任何AI输出
    }

    private var bestNotesSource: NotesSource {
        if !meeting.tingwuNotes.isEmpty { return .tingwu }
        if !meeting.richNotes.isEmpty { return .richNotes }
        if !meeting.summary.isEmpty { return .summary }
        return .none
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Header info
                headerSection

                // 2. Audio player
                if meeting.audioFileURL != nil {
                    AudioPlayerView(audioURL: meeting.audioFileURL!)
                        .padding(.horizontal)
                }

                // 2.5 Bookmarks list (if any)
                if !meeting.bookmarksList.isEmpty {
                    bookmarksSection
                }

                // 3. Processing status (transcribing/processing)
                if meeting.status == .transcribing || meeting.status == .processing || meeting.status == .summarizing {
                    processingStatusView
                }

                // 3.5 Transcription entry (for saved meetings)
                if meeting.status == .saved {
                    transcriptionEntrySection
                }

                // 3.6 AI processing panel (for transcribed meetings)
                if meeting.status == .transcribed {
                    aiProcessingSection
                }

                // 4. Unified AI notes section
                if meeting.status == .completed || !meeting.summary.isEmpty || !meeting.richNotes.isEmpty || !meeting.tingwuNotes.isEmpty {
                    unifiedNotesSection
                }

                // 5. Key Points (if available and not already in tingwu/richNotes)
                if bestNotesSource == .summary && !meeting.keyPointsList.isEmpty {
                    keyPointsSection
                }

                // 6. Action Items
                actionItemsSection

                // 7. Transcript (collapsed by default)
                transcriptSection

                // 8. More actions
                moreActionsSection
            }
            .padding(.vertical)
        }
        .navigationTitle(meeting.title.isEmpty ? "会议记录" : meeting.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        shareMeeting()
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(item: $openWebURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                    Text(meeting.date.formatted(date: .long, time: .shortened))
                }

                if meeting.duration > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                        Text(meeting.formattedDuration)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Processing Status

    private var processingStatusView: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(processingTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(processingSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.06))
        )
        .padding(.horizontal)
    }

    private var processingTitle: String {
        switch meeting.status {
        case .recording:    return "录音中"
        case .transcribing: return "AI 转写中..."
        case .summarizing:  return "AI 分析中..."
        case .processing:   return "AI 处理中..."
        default:            return "处理中..."
        }
    }

    private var processingSubtitle: String {
        switch meeting.status {
        case .transcribing: return asrService.statusText.isEmpty ? "正在将录音转为文字" : asrService.statusText
        case .summarizing:  return "正在生成会议纪要和待办事项"
        case .processing:   return "正在使用 AI 处理转录内容"
        default:            return "请稍候"
        }
    }

    // MARK: - Bookmarks Section

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                Text("录音标记")
                    .font(.headline)
                Spacer()
                Text("\(meeting.bookmarksList.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(meeting.bookmarksList) { bookmark in
                HStack(spacing: 10) {
                    Image(systemName: bookmark.displayIcon)
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .frame(width: 20)

                    Text(bookmark.formattedTimestamp)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(bookmark.displayLabel)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
        .padding(.horizontal)
    }

    // MARK: - Transcription Entry (for .saved meetings)

    private var transcriptionEntrySection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                Text("录音已保存，可以开始转录")
                    .font(.headline)

                Text("使用阿里云 AI 将录音转为文字，支持多语言和说话人识别")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                startTranscription()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.badge.xmark")
                    Text("开始 AI 转录")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
            }

            // 本地转录备选
            Button {
                startTranscription(useLocal: true)
            } label: {
                Text("使用本地识别（免费，质量有限）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.04))
        )
        .padding(.horizontal)
    }

    // MARK: - AI Processing Section (for .transcribed meetings)

    private var aiProcessingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI 处理")
                    .font(.headline)
                Spacer()
            }

            Text("选择要执行的 AI 处理功能")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Task checkboxes
            ForEach(AIProcessingTask.allCases) { task in
                Button {
                    if selectedAITasks.contains(task) {
                        selectedAITasks.remove(task)
                    } else {
                        selectedAITasks.insert(task)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedAITasks.contains(task) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedAITasks.contains(task) ? .purple : .secondary)
                        Image(systemName: task.icon)
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text(task.displayName)
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                }
            }

            // Process button
            Button {
                startAIProcessing()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text("开始 AI 处理")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    selectedAITasks.isEmpty ? Color.gray : Color.purple,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .disabled(selectedAITasks.isEmpty)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.04))
        )
        .padding(.horizontal)
    }

    // MARK: - Transcription & AI Actions

    private func startTranscription(useLocal: Bool = false) {
        Task {
            await MeetingProcessingService.shared.transcribe(
                meeting: meeting,
                modelContext: modelContext,
                useLocalASR: useLocal
            )
        }
    }

    private func startAIProcessing() {
        guard !selectedAITasks.isEmpty else { return }
        Task {
            await MeetingProcessingService.shared.processWithAI(
                meeting: meeting,
                modelContext: modelContext,
                tasks: selectedAITasks
            )
        }
    }

    // MARK: - Unified Notes Section

    private var unifiedNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch bestNotesSource {
            case .tingwu:
                tingwuNotesCard
            case .richNotes:
                richNotesCard
            case .summary:
                summaryCard
            case .none:
                if meeting.status == .completed || meeting.status == .failed {
                    emptyNotesView
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: Tingwu Notes Card

    private var tingwuNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source badge
            HStack(spacing: 6) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.caption)
                Text("智能纪要 · 通义听悟")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.indigo)

            // Preview text
            let previewText = String(meeting.tingwuNotes.prefix(300))
            if !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(previewText + (meeting.tingwuNotes.count > 300 ? "..." : ""))
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            // Detail navigation
            NavigationLink {
                TingWuDetailView(meeting: meeting)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 16))
                    Text("查看完整智能纪要")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("对话 · 概要 · 思维导图")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.indigo.opacity(0.06))
                )
                .foregroundStyle(.indigo)
            }

            // If also have richNotes or summary, show as secondary
            if !meeting.richNotes.isEmpty || !meeting.summary.isEmpty {
                secondaryNotesCollapsed
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    @State private var showSecondaryNotes = false

    private var secondaryNotesCollapsed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSecondaryNotes.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showSecondaryNotes ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("其他纪要版本")
                        .font(.caption)
                    Spacer()
                    if !meeting.richNotes.isEmpty {
                        Text("图文纪要")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.1)))
                    }
                    if !meeting.summary.isEmpty {
                        Text("AI摘要")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.1)))
                    }
                }
                .foregroundStyle(.secondary)
            }

            if showSecondaryNotes {
                if !meeting.richNotes.isEmpty {
                    richNotesInline
                }
                if !meeting.summary.isEmpty {
                    summaryInline
                }
            }
        }
    }

    // MARK: Rich Notes Card (primary when no tingwu)

    private var richNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source badge
            let isHTML = meeting.richNotes.isHTML
            HStack(spacing: 6) {
                Image(systemName: isHTML ? "globe" : "text.alignleft")
                    .font(.caption)
                Text(isHTML ? "图文纪要 · 百炼工作流" : "图文纪要 · AI 生成")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.purple)

            richNotesContent

            // If also have summary, show collapsed
            if !meeting.summary.isEmpty {
                summaryCollapsed
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var richNotesContent: some View {
        Group {
            if meeting.richNotes.isHTML {
                AutoHeightHTMLView(html: meeting.richNotes)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                MarkdownText(text: meeting.richNotes)
                    .textSelection(.enabled)
            }

            // URL link
            if let webURL = extractFirstURL(from: meeting.richNotes) {
                Button {
                    openWebURL = IdentifiableURL(url: webURL)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text("查看网页版")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.06))
                    )
                    .foregroundStyle(.purple)
                }
            }
        }
    }

    private var richNotesInline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("图文纪要")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.purple)

            richNotesContent
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: Summary Card (primary when no tingwu and no richNotes)

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.caption)
                Text("AI 摘要")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.blue)

            MarkdownText(text: meeting.summary)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var summaryInline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.caption)
                Text("AI 摘要")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.blue)

            MarkdownText(text: meeting.summary)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    @State private var showSummaryDetail = false

    private var summaryCollapsed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSummaryDetail.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showSummaryDetail ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("AI 摘要")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }

            if showSummaryDetail {
                summaryInline
            }
        }
    }

    // MARK: Empty Notes

    private var emptyNotesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("暂无 AI 纪要")
                .font(.headline)
            Text("录音结束后将自动生成，或手动触发生成")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            generateButtons
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var generateButtons: some View {
        VStack(spacing: 10) {
            if !meeting.transcript.isEmpty {
                Button {
                    retryAISummary()
                } label: {
                    Label("生成 AI 摘要", systemImage: "sparkles")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)

                if !meeting.transcript.isEmpty {
                    Button {
                        generateRichNotes()
                    } label: {
                        Label("生成图文纪要", systemImage: "doc.richtext")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if meeting.audioFileURL != nil && tingwuService.isConfigured {
                Button {
                    generateTingWuNotes()
                } label: {
                    Label("生成智能纪要（听悟）", systemImage: "waveform.badge.magnifyingglass")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
        }
    }

    // MARK: - Key Points Section

    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.circle")
                    .foregroundStyle(.blue)
                Text("关键要点")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(meeting.keyPointsList, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        MarkdownText(text: point)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }

    // MARK: - Action Items Section

    private var actionItemsSection: some View {
        Group {
            if !meeting.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .foregroundStyle(.orange)
                        Text("待办事项")
                            .font(.headline)

                        Spacer()

                        let done = meeting.actionItems.filter(\.isCompleted).count
                        let total = meeting.actionItems.count
                        Text("\(done)/\(total)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(done == total ? .green : .orange)
                    }

                    ForEach(meeting.actionItems) { item in
                        ActionItemRow(item: item)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Transcript Section (Collapsed)

    private var transcriptSection: some View {
        Group {
            if !meeting.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isTranscriptExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text("原始转写")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(meeting.transcript.count) 字")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: isTranscriptExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isTranscriptExpanded {
                        Text(meeting.transcript)
                            .font(.body)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        // Preview first 100 chars
                        Text(String(meeting.transcript.prefix(100)) + "...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - More Actions Section

    private var moreActionsSection: some View {
        VStack(spacing: 10) {
            // Workflow error banners
            if !workflowService.lastError.isEmpty && !workflowService.isRunning {
                errorBanner(title: "图文纪要生成失败", detail: workflowService.lastError)
            }
            if !tingwuService.lastError.isEmpty && !tingwuService.isProcessing {
                errorBanner(title: "智能纪要生成失败", detail: tingwuService.lastError)
            }

            // Processing indicators
            if workflowService.isRunning {
                processingBanner(text: "正在生成图文纪要...")
            }
            if tingwuService.isProcessing {
                processingBanner(text: "正在生成智能纪要...")
            }

            // Generate actions (when we already have some notes but want alternatives)
            if meeting.status == .completed || meeting.status == .failed {
                HStack(spacing: 12) {
                    if !meeting.transcript.isEmpty {
                        Button {
                            retryAISummary()
                        } label: {
                            Label("重新摘要", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            generateRichNotes()
                        } label: {
                            Label("生成图文", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.purple)
                    }

                    if meeting.audioFileURL != nil && tingwuService.isConfigured {
                        Button {
                            generateTingWuNotes()
                        } label: {
                            Label("智能纪要", systemImage: "waveform.badge.magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.indigo)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func errorBanner(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
    }

    private func processingBanner(text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
    }

    // MARK: - Actions

    private func generateTingWuNotes() {
        guard let audioURL = meeting.audioFileURL else {
            errorMessage = "没有录音文件"
            showError = true
            return
        }
        Task {
            do {
                let result = try await tingwuService.generateSmartNotes(audioFileURL: audioURL)
                meeting.tingwuNotes = result.meetingNotes
                meeting.tingwuDataId = result.dataId

                if let rawData = try? JSONSerialization.data(withJSONObject: result.rawResults),
                   let rawStr = String(data: rawData, encoding: .utf8) {
                    meeting.tingwuRawResults = rawStr
                }

                if meeting.transcript.isEmpty && !result.transcription.isEmpty {
                    meeting.transcript = result.transcription
                }
                try? modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func generateRichNotes() {
        guard !meeting.transcript.isEmpty || meeting.audioFileURL != nil else { return }
        Task {
            do {
                guard let audioURL = meeting.audioFileURL else {
                    throw WorkflowError.networkError("No audio file")
                }
                let notes = try await workflowService.generateRichNotes(audioFileURL: audioURL)
                if notes.contains("视频为空") || notes.contains("请提供视频") || notes.count < 20 {
                    throw WorkflowError.serverError("WorkflowIncompatible",
                        "工作流返回异常，正在改用 AI 模型直接生成")
                }
                meeting.richNotes = notes
                try? modelContext.save()
            } catch {
                guard !meeting.transcript.isEmpty else {
                    errorMessage = "无音频文件且无转写文本"
                    showError = true
                    return
                }
                do {
                    let notes = try await aiService.generateRichNotes(transcript: meeting.transcript)
                    meeting.richNotes = notes
                    try? modelContext.save()
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func retryAISummary() {
        guard !meeting.transcript.isEmpty else {
            errorMessage = "没有转写文本可供分析"
            showError = true
            return
        }

        isRetrying = true
        meeting.status = .summarizing

        Task {
            do {
                let result = try await aiService.generateSummary(transcript: meeting.transcript)
                meeting.title = result.title
                meeting.summary = result.summary
                meeting.keyPointsList = result.keyPoints

                for item in meeting.actionItems {
                    modelContext.delete(item)
                }
                for item in result.actionItems {
                    let actionItem = ActionItem(title: item.title, assignee: item.assignee, meeting: meeting)
                    modelContext.insert(actionItem)
                }

                meeting.status = .completed
                try? modelContext.save()
            } catch {
                meeting.status = .completed
                errorMessage = error.localizedDescription
                showError = true
            }
            isRetrying = false
        }
    }

    private func shareMeeting() {
        var text = "# \(meeting.title)\n"
        text += "\(meeting.date.formatted(date: .long, time: .shortened))\n\n"

        if !meeting.summary.isEmpty {
            text += "## 摘要\n\(meeting.summary)\n\n"
        }

        if !meeting.keyPointsList.isEmpty {
            text += "## 关键要点\n"
            for point in meeting.keyPointsList {
                text += "- \(point)\n"
            }
            text += "\n"
        }

        if !meeting.actionItems.isEmpty {
            text += "## 待办事项\n"
            for item in meeting.actionItems {
                let check = item.isCompleted ? "x" : " "
                let assignee = item.assignee.isEmpty ? "" : " (@\(item.assignee))"
                text += "- [\(check)] \(item.title)\(assignee)\n"
            }
            text += "\n"
        }

        if !meeting.transcript.isEmpty {
            text += "## 转写原文\n\(meeting.transcript)\n"
        }

        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - String + HTML Detection
private extension String {
    var isHTML: Bool {
        let lower = lowercased()
        return lower.contains("<html") || lower.contains("<!doctype")
            || lower.contains("<div") || lower.contains("<p>")
            || lower.contains("<table") || lower.contains("<ul")
            || lower.contains("<ol") || lower.contains("<h1")
            || lower.contains("<h2") || lower.contains("<strong")
            || lower.contains("<br") || lower.contains("<span")
    }
}

// MARK: - Section Card Component
struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Action Item Row
struct ActionItemRow: View {
    @Bindable var item: ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation { item.isCompleted.toggle() }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if !item.assignee.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                        Text(item.assignee)
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    NavigationStack {
        MeetingDetailView(meeting: {
            let m = Meeting(title: "产品需求评审", date: Date(), duration: 1234)
            m.summary = "团队讨论了Q2产品路线图，确定了三个核心功能的优先级排序。"
            m.keyPointsList = ["日活留存率定为北极星指标", "8月前完成灰度发布", "需要增加A/B测试方案"]
            m.transcript = "这是一段会议转写的示例文本，包含了完整的讨论内容..."
            m.status = .completed
            return m
        }())
    }
    .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
