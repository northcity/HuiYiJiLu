//
//  MeetingListView.swift
//  云雀记 (LarkNote)
//
//  全新设计的首页 — iOS 17+ 风格，卡片式会议列表
//  设计理念：高级感 · 信息层级清晰 · 快速操作
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Design Tokens

private enum Design {
    static let accent     = Color(red: 0.13, green: 0.47, blue: 1.0)   // #2178FF
    static let bgPrimary  = Color(.systemGroupedBackground)
    static let bgCard     = Color(.systemBackground)
    static let textTitle  = Color(.label)
    static let textBody   = Color(.secondaryLabel)
    static let textMuted  = Color(.tertiaryLabel)
    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let horizontalPadding: CGFloat = 20
    static let cardShadow = Color.black.opacity(0.06)
    static let titleFont  = Font.system(size: 34, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let bodyFont   = Font.system(size: 15, weight: .regular)
    static let captionFont = Font.system(size: 13, weight: .medium)
}

// MARK: - Home View

struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    
    @State private var searchText = ""
    @State private var showRecording = false
    @State private var showSettings = false
    @State private var showAudioImporter = false
    
    // MARK: - Filtering & Grouping
    
    private var filteredMeetings: [Meeting] {
        var list = meetings
        if !searchText.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.transcript.localizedCaseInsensitiveContains(searchText) ||
                $0.summary.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }
    
    private var todayMeetings: [Meeting] {
        filteredMeetings.filter { Calendar.current.isDateInToday($0.date) }
    }
    private var weekMeetings: [Meeting] {
        filteredMeetings.filter { !Calendar.current.isDateInToday($0.date) && isThisWeek($0.date) }
    }
    private var olderMeetings: [Meeting] {
        filteredMeetings.filter { !isThisWeek($0.date) }
    }
    
    private func isThisWeek(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Design.bgPrimary.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerView
                        quickActionsBar
                        searchBarView
                        
                        if meetings.isEmpty {
                            emptyStateView
                        } else if filteredMeetings.isEmpty {
                            noResultsView
                        } else {
                            meetingListContent
                        }
                    }
                    .padding(.bottom, 100)
                }
                .refreshable { /* Pull to refresh */ }
                
                fabButton
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showRecording) { RecordingView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
                allowsMultipleSelection: false
            ) { result in
                importAudioFile(result: result)
            }
        }
    }
    
    // =======
    // MARK: - Header
    // =======
    
    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greetingText)
                    .font(Design.headlineFont)
                    .foregroundStyle(Design.textBody)
                
                Text("云雀记")
                    .font(Design.titleFont)
                    .foregroundStyle(Design.textTitle)
                    .tracking(-0.5)
                
                if !meetings.isEmpty {
                    Text(statsText)
                        .font(Design.captionFont)
                        .foregroundStyle(Design.textMuted)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Design.textBody)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, Design.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "美好清晨 ☀️"
        case 12..<14: return "午间稍息 🌤"
        case 14..<18: return "高效午后 ☁️"
        case 18..<22: return "夜间沉淀 🌙"
        default:      return "静谧深夜 🌃"
        }
    }
    
    private var statsText: String {
        let today = todayMeetings.count
        if today > 0 {
            return "今天 \(today) 场会议 · 共 \(meetings.count) 条记录"
        }
        return "共 \(meetings.count) 条会议记录"
    }
    
    // =======
    // MARK: - Quick Actions
    // =======
    
    private var quickActionsBar: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                icon: "mic.fill",
                label: "开始会议",
                color: Design.accent,
                style: .primary
            ) {
                showRecording = true
            }
            
            QuickActionButton(
                icon: "square.and.arrow.down",
                label: "导入录音",
                color: .secondary,
                style: .secondary
            ) {
                showAudioImporter = true
            }
        }
        .padding(.horizontal, Design.horizontalPadding)
        .padding(.vertical, 12)
    }
    
    // =======
    // MARK: - Search Bar
    // =======
    
    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Design.textMuted)
                .font(.system(size: 15, weight: .medium))
            
            TextField("搜索会议记录...", text: $searchText)
                .font(Design.bodyFont)
                .autocorrectionDisabled()
            
            if !searchText.isEmpty {
                Button { withAnimation { searchText = "" } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.systemGray3))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, Design.horizontalPadding)
        .padding(.bottom, 8)
    }
    
    // =======
    // MARK: - Meeting List Content
    // =======
    
    private var meetingListContent: some View {
        LazyVStack(spacing: 16) {
            if !searchText.isEmpty {
                meetingCards(for: filteredMeetings)
            } else {
                if !todayMeetings.isEmpty {
                    sectionGroup(title: "今天", meetings: todayMeetings)
                }
                if !weekMeetings.isEmpty {
                    sectionGroup(title: "本周", meetings: weekMeetings)
                }
                if !olderMeetings.isEmpty {
                    sectionGroup(title: "更早", meetings: olderMeetings)
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func sectionGroup(title: String, meetings: [Meeting]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.textMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(meetings.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Design.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5), in: Capsule())
            }
            .padding(.horizontal, Design.horizontalPadding + 4)
            
            meetingCards(for: meetings)
        }
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private func meetingCards(for list: [Meeting]) -> some View {
        ForEach(list) { meeting in
            NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                MeetingCardView(meeting: meeting)
            }
            .buttonStyle(CardButtonStyle())
            .padding(.horizontal, Design.horizontalPadding)
            .contextMenu {
                Button { /* TODO: Pin */ } label: {
                    Label("置顶", systemImage: "pin")
                }
                Divider()
                Button(role: .destructive) { deleteMeeting(meeting) } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
    
    // =======
    // MARK: - Empty States
    // =======
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 48)
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Design.accent.opacity(0.12), Design.accent.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Design.accent.opacity(0.6))
            }
            
            VStack(spacing: 10) {
                Text("开始你的第一次会议")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.textTitle)
                
                Text("所有会议纪要都将被 AI 自动整理，\n帮你回顾每一个关键时刻。")
                    .font(Design.bodyFont)
                    .foregroundStyle(Design.textBody)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 40)
            
            Button {
                showRecording = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("开始录音")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Design.accent, in: Capsule())
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 48)
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Design.textMuted)
            Text("未找到相关记录")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Design.textBody)
            Text("尝试修改搜索关键词")
                .font(.system(size: 14))
                .foregroundStyle(Design.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // =======
    // MARK: - FAB
    // =======
    
    private var fabButton: some View {
        Button { showRecording = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("开始录音")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Design.accent, Design.accent.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: Design.accent.opacity(0.35), radius: 16, y: 8)
        }
        .padding(.bottom, 28)
        .opacity(meetings.isEmpty ? 0 : 1)
    }
    
    // =======
    // MARK: - Actions
    // =======
    
    private func deleteMeeting(_ meeting: Meeting) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let url = meeting.audioFileURL { try? FileManager.default.removeItem(at: url) }
            modelContext.delete(meeting)
        }
    }
    
    private func importAudioFile(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let sourceURL = urls.first else { return }
        guard sourceURL.startAccessingSecurityScopedResource() else { return }
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let fileName = "imported_\(timestamp).\(ext)"
        let destURL = recordingsDir.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("[Import] Failed to copy audio: \(error)")
            return
        }
        
        let meeting = Meeting(title: "导入: \(sourceURL.deletingPathExtension().lastPathComponent)", date: Date())
        meeting.audioFileName = fileName
        meeting.status = .completed
        modelContext.insert(meeting)
        try? modelContext.save()
    }
}

// MARK: - Quick Action Button Component

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let style: ActionStyle
    let action: () -> Void
    
    enum ActionStyle { case primary, secondary }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(style == .primary ? .white : Design.textTitle)
            .background(
                style == .primary
                    ? AnyShapeStyle(Design.accent)
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: style == .primary ? Design.accent.opacity(0.25) : .clear, radius: 8, y: 4)
        }
    }
}

// MARK: - Meeting Card View Component

struct MeetingCardView: View {
    let meeting: Meeting
    
    private var statusColor: Color {
        switch meeting.status {
        case .recording:    return .red
        case .transcribing: return .orange
        case .summarizing:  return .purple
        case .completed:    return Design.accent
        case .failed:       return Color(.systemGray)
        }
    }
    
    private var statusLabel: String {
        switch meeting.status {
        case .recording:    return "录音中"
        case .transcribing: return "转写中"
        case .summarizing:  return "处理中"
        case .completed:    return "已完成"
        case .failed:       return "失败"
        }
    }
    
    private var relativeDate: String {
        if Calendar.current.isDateInToday(meeting.date) {
            return meeting.date.formatted(date: .omitted, time: .shortened)
        } else if Calendar.current.isDateInYesterday(meeting.date) {
            return "昨天 " + meeting.date.formatted(date: .omitted, time: .shortened)
        }
        return meeting.date.formatted(date: .abbreviated, time: .shortened)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Title & Status
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor.opacity(meeting.status == .completed ? 0.5 : 1.0))
                    .frame(width: 4, height: 44)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title.isEmpty ? "未命名记录" : meeting.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Design.textTitle)
                        .lineLimit(2)
                    
                    Text(relativeDate)
                        .font(Design.captionFont)
                        .foregroundStyle(Design.textMuted)
                }
                
                Spacer(minLength: 8)
                
                if meeting.status != .completed {
                    statusPill
                }
            }
            
            // Summary preview
            if !meeting.summary.isEmpty {
                Text(meeting.summary)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Design.textBody)
                    .lineLimit(2)
                    .lineSpacing(2)
            } else if !meeting.transcript.isEmpty {
                Text(meeting.transcript)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Design.textBody)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            
            // Bottom row
            HStack(alignment: .center, spacing: 16) {
                if meeting.duration > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 12))
                        Text(meeting.formattedDuration).font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(Design.textMuted)
                }
                
                if !meeting.tingwuNotes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.circle").font(.system(size: 12))
                        Text("智能纪要").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.teal)
                }
                
                Spacer()
                
                if !meeting.actionItems.isEmpty {
                    let done = meeting.actionItems.filter(\.isCompleted).count
                    let total = meeting.actionItems.count
                    let allDone = done == total
                    
                    HStack(spacing: 4) {
                        Image(systemName: allDone ? "checkmark.circle.fill" : "checklist")
                            .font(.system(size: 12))
                        Text("\(done)/\(total)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(allDone ? Color.green.opacity(0.1) : Design.accent.opacity(0.08))
                    .foregroundStyle(allDone ? .green : Design.accent)
                    .clipShape(Capsule())
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.textMuted)
            }
        }
        .padding(Design.cardPadding)
        .background(Design.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
        .shadow(color: Design.cardShadow, radius: 10, y: 4)
    }
    
    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 4) {
            if meeting.status == .recording {
                Circle().fill(Color.red).frame(width: 6, height: 6)
            } else {
                ProgressView().scaleEffect(0.6)
            }
            Text(statusLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.1))
        .foregroundStyle(statusColor)
        .clipShape(Capsule())
    }
}

// MARK: - Card Button Style

private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    MeetingListView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
