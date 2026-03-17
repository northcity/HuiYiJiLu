//
//  MeetingDetailView.swift
//  Huiyijilu
//

import SwiftUI
import SwiftData
import SafariServices

/// Lightweight Identifiable wrapper so we can use .sheet(item:) with a URL
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// Meeting detail page - shows transcript, AI summary, action items, audio player
struct MeetingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting

    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var aiService = AIService()
    @StateObject private var workflowService = BailianWorkflowService()
    @State private var selectedTab = 0
    @State private var isRetrying = false
    @State private var showShareSheet = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var openWebURL: IdentifiableURL? = nil

    /// Extract the first https:// URL from arbitrary text using NSDataDetector
    private func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.first?.url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header info
                headerSection

                // Audio player
                if meeting.audioFileURL != nil {
                    AudioPlayerView(audioURL: meeting.audioFileURL!)
                        .padding(.horizontal)
                }

                // Status indicator for processing meetings
                if meeting.status != .completed && meeting.status != .failed {
                    processingStatusView
                }

                // Tab picker
                Picker("Section", selection: $selectedTab) {
                    Text("Summary").tag(0)
                    Text("Transcript").tag(1)
                    Text("Tasks").tag(2)
                    Text("图文纪要").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Tab content
                Group {
                    switch selectedTab {
                    case 0: summarySection
                    case 1: transcriptSection
                    case 2: actionItemsSection
                    case 3: richNotesSection
                    default: EmptyView()
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(meeting.title.isEmpty ? "Meeting" : meeting.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        shareMeeting()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    if meeting.status == .failed || (meeting.status == .completed && meeting.summary.isEmpty) {
                        Button {
                            retryAISummary()
                        } label: {
                            Label("Retry AI Summary", systemImage: "arrow.clockwise")
                        }
                    }

                    if !meeting.transcript.isEmpty {
                        Button {
                            generateRichNotes()
                        } label: {
                            Label("生成图文纪要", systemImage: "sparkles")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
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
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(meeting.date.formatted(date: .long, time: .shortened))
                    .foregroundStyle(.secondary)
            }

            if meeting.duration > 0 {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Duration: \(meeting.formattedDuration)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal)
    }

    // MARK: - Processing Status
    private var processingStatusView: some View {
        HStack {
            ProgressView()
            Text(meeting.status == .transcribing ? "Transcribing..." : "AI Analyzing...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    // MARK: - Summary Tab
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if meeting.summary.isEmpty && meeting.status == .completed {
                noAISummaryView
            } else if !meeting.summary.isEmpty {
                // Summary
                SectionCard(title: "Summary", icon: "text.quote") {
                    MarkdownText(text: meeting.summary)
                        .textSelection(.enabled)
                }

                // Key Points
                if !meeting.keyPointsList.isEmpty {
                    SectionCard(title: "Key Points", icon: "list.bullet.circle") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(meeting.keyPointsList, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    MarkdownText(text: point)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var noAISummaryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No AI Summary")
                .font(.headline)
            Text("Set your API Key in Settings to enable AI meeting summaries")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !meeting.transcript.isEmpty {
                Button("Generate Summary Now") {
                    retryAISummary()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Transcript Tab
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if meeting.transcript.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No transcript available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                SectionCard(title: "Full Transcript", icon: "doc.text") {
                    Text(meeting.transcript)
                        .font(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Action Items Tab
    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if meeting.actionItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No action items")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(meeting.actionItems) { item in
                    ActionItemRow(item: item)
                }
            }
        }
    }

    // MARK: - Rich Notes Tab (Bailian Workflow)
    private var richNotesSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            // --- Last API error banner ---
            if !workflowService.lastError.isEmpty && !workflowService.isRunning {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("工作流调用失败，已改用 AI 直接生成")
                            .font(.subheadline).fontWeight(.semibold)
                        Text(workflowService.lastError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            UIPasteboard.general.string = workflowService.lastError
                        } label: {
                            Label("复制错误信息", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                        Text("Xcode Console 过滤关键字 [Bailian] 查看完整日志")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            }

            if workflowService.isRunning {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在生成图文纪要...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !workflowService.streamingText.isEmpty {
                        SectionCard(title: "生成中...", icon: "sparkles") {
                            Text(workflowService.streamingText)
                                .font(.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else if !meeting.richNotes.isEmpty {
                // Source badge
                let isHTML = meeting.richNotes.isHTML
                HStack(spacing: 6) {
                    Image(systemName: isHTML ? "globe" : "text.alignleft")
                        .font(.caption)
                    Text(isHTML ? "百炼工作流 · HTML 格式" : "AI 生成 · Markdown 格式")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

                if isHTML {
                    // Render HTML from Bailian workflow
                    VStack(alignment: .leading, spacing: 8) {
                        AutoHeightHTMLView(html: meeting.richNotes)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                } else {
                    // Render plain Markdown text (LLM fallback / qwen-flash final output)
                    SectionCard(title: "图文纪要", icon: "sparkles") {
                        MarkdownText(text: meeting.richNotes)
                            .textSelection(.enabled)
                    }

                    // If the text contains a URL (e.g. EdgeOne share link), show open button
                    if let webURL = extractFirstURL(from: meeting.richNotes) {
                        Button {
                            openWebURL = IdentifiableURL(url: webURL)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                Text("在 App 内查看网页版图文纪要")
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.purple.opacity(0.1))
                            )
                            .foregroundStyle(.purple)
                        }
                    }
                }

                Button {
                    generateRichNotes()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .foregroundStyle(.blue)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(.purple)
                    Text("图文纪要")
                        .font(.title3).fontWeight(.semibold)
                    Text("使用百炼「会议图文纪要」工作流\n自动生成结构化丰富的会议记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if !workflowService.isConfigured {
                        Text("请先在「设置」中配置 API Key 和 App ID")
                            .font(.caption).foregroundStyle(.orange)
                    } else if meeting.transcript.isEmpty {
                        Text("需要先有转写文本才能生成纪要")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button {
                            generateRichNotes()
                        } label: {
                            Label("生成图文纪要", systemImage: "sparkles").fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent).tint(.purple)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
    }

    // MARK: - Actions
    private func generateRichNotes() {
        guard !meeting.transcript.isEmpty || meeting.audioFileURL != nil else { return }
        Task {
            do {
                // Try Bailian workflow with audio file
                guard let audioURL = meeting.audioFileURL else {
                    throw WorkflowError.networkError("No audio file")
                }
                let notes = try await workflowService.generateRichNotes(audioFileURL: audioURL)
                if notes.contains("视频为空") || notes.contains("请提供视频") || notes.count < 20 {
                    throw WorkflowError.serverError("WorkflowIncompatible",
                        "工作流返回异常，正在改用 AI 模型直接生成")
                }
                meeting.richNotes = notes
                selectedTab = 3
                try? modelContext.save()
            } catch {
                // Fallback: use Qwen/LLM to generate from transcript text
                guard !meeting.transcript.isEmpty else {
                    errorMessage = "无音频文件且无转写文本"
                    showError = true
                    return
                }
                do {
                    let notes = try await aiService.generateRichNotes(transcript: meeting.transcript)
                    meeting.richNotes = notes
                    selectedTab = 3
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
            errorMessage = "No transcript to analyze"
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

                // Remove old action items
                for item in meeting.actionItems {
                    modelContext.delete(item)
                }

                // Add new action items
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
            text += "## Summary\n\(meeting.summary)\n\n"
        }

        if !meeting.keyPointsList.isEmpty {
            text += "## Key Points\n"
            for point in meeting.keyPointsList {
                text += "- \(point)\n"
            }
            text += "\n"
        }

        if !meeting.actionItems.isEmpty {
            text += "## Action Items\n"
            for item in meeting.actionItems {
                let check = item.isCompleted ? "x" : " "
                let assignee = item.assignee.isEmpty ? "" : " (@\(item.assignee))"
                text += "- [\(check)] \(item.title)\(assignee)\n"
            }
            text += "\n"
        }

        if !meeting.transcript.isEmpty {
            text += "## Transcript\n\(meeting.transcript)\n"
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
    /// Returns true if the string appears to contain HTML markup.
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    NavigationStack {
        MeetingDetailView(meeting: {
            let m = Meeting(title: "Product Launch Discussion", date: Date(), duration: 1234)
            m.summary = "The team discussed the upcoming product launch timeline and key milestones."
            m.keyPointsList = ["UI needs optimization", "Beta release next week", "Marketing plan ready"]
            m.transcript = "This is a sample transcript of the meeting discussion..."
            m.status = .completed
            return m
        }())
    }
    .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
