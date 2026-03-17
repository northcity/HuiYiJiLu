//
//  MeetingListView.swift
//  Huiyijilu
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Home page — Modern, clean, Dribbble-inspired Meeting List
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""
    @State private var showRecording = false
    @State private var showSettings = false
    @State private var showAudioImporter = false
    
    // Theme Colors
    private let primaryBlue = Color(red: 0/255, green: 132/255, blue: 255/255) // #0084FF
    private let bgLight = Color(red: 248/255, green: 249/255, blue: 251/255)    // #F8F9FB
    private let textDark = Color(red: 26/255, green: 26/255, blue: 26/255)      // #1A1A1A
    private let textGray = Color(red: 102/255, green: 102/255, blue: 102/255)   // #666666

    // MARK: - Filtering & Grouping

    var filteredMeetings: [Meeting] {
        guard !searchText.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.transcript.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var todayMeetings:  [Meeting] { filteredMeetings.filter { Calendar.current.isDateInToday($0.date) } }
    private var weekMeetings:   [Meeting] { filteredMeetings.filter { !Calendar.current.isDateInToday($0.date) && isThisWeek($0.date) } }
    private var olderMeetings:  [Meeting] { filteredMeetings.filter { !isThisWeek($0.date) } }

    private func isThisWeek(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                bgLight.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerSection
                    searchBar
                    
                    if meetings.isEmpty {
                        emptyStateView
                    } else {
                        meetingListContent
                    }
                }

                newMeetingButton
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showRecording) { RecordingView() }
            .sheet(isPresented: $showSettings)       { SettingsView() }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
                allowsMultipleSelection: false
            ) { result in
                importAudioFile(result: result)
            }
        }
    }

    // MARK: - App Header
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greetingText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(textGray)
                Text("云雀记")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(textDark)
                    .tracking(-0.5)
            }
            Spacer()
            
            HStack(spacing: 12) {
                Button { showAudioImporter = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(textDark)
                    }
                }
                
                Button { showSettings = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(textDark)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "美好清晨 ☀️"
        case 12..<14: return "午间稍息 🌤"
        case 14..<18: return "高效午后 🌥"
        case 18..<22: return "夜间沉淀 🌙"
        default:      return "静谧深夜 🌃"
        }
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(textGray.opacity(0.6))
                .font(.system(size: 16, weight: .medium))
            TextField("搜索会议记录...", text: $searchText)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(textDark)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.systemGray3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.02), radius: 8, y: 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Meeting List (grouped sections)
    private var meetingListContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20, pinnedViews: []) {
                if !searchText.isEmpty {
                    cardRows(for: filteredMeetings)
                    Spacer().frame(height: 120)
                } else {
                    if !todayMeetings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("今天")
                            cardRows(for: todayMeetings)
                        }
                    }
                    if !weekMeetings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("本周")
                            cardRows(for: weekMeetings)
                        }
                    }
                    if !olderMeetings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("更早之前")
                            cardRows(for: olderMeetings)
                        }
                    }
                    Spacer().frame(height: 120)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func cardRows(for list: [Meeting]) -> some View {
        ForEach(list) { meeting in
            NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                MeetingRowView(meeting: meeting)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)
            .contextMenu {
                Button(role: .destructive) { deleteMeeting(meeting) } label: {
                    Label("删除记录", systemImage: "trash")
                }
            }
            // For swipe to delete
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { deleteMeeting(meeting) } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(textGray.opacity(0.8))
            .padding(.horizontal, 28)
            .padding(.top, 8)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)
            
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.03), radius: 20, y: 10)
                
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(textGray.opacity(0.4))
            }

            VStack(spacing: 8) {
                Text("暂无录音记录")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(textDark)

                Text("所有的思绪与会议，都将在这里被妥善保存。\n点击下方按钮，留住这一刻的声音。")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textGray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - FAB
    private var newMeetingButton: some View {
        Button { showRecording = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .bold))
                Text("开始录音")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .background(primaryBlue)
            .clipShape(Capsule())
            .shadow(color: primaryBlue.opacity(0.3), radius: 16, y: 8)
        }
        .padding(.bottom, 32)
    }

    // MARK: - Delete
    private func deleteMeeting(_ meeting: Meeting) {
        withAnimation {
            if let url = meeting.audioFileURL { try? FileManager.default.removeItem(at: url) }
            modelContext.delete(meeting)
        }
    }

    // MARK: - Import Audio File
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

// MARK: - Meeting Row Card
struct MeetingRowView: View {
    let meeting: Meeting
    
    private let primaryBlue = Color(red: 0/255, green: 132/255, blue: 255/255)
    private let textDark = Color(red: 26/255, green: 26/255, blue: 26/255)
    private let textGray = Color(red: 102/255, green: 102/255, blue: 102/255)
    
    private var statusColor: Color {
        switch meeting.status {
        case .recording:    return .red
        case .transcribing: return .orange
        case .summarizing:  return .purple
        case .completed:    return primaryBlue
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
            // Header: Title & Status Pill
            HStack(alignment: .top, spacing: 12) {
                Text(meeting.title.isEmpty ? "未命名记录" : meeting.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(textDark)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 8)
                
                if meeting.status != .completed {
                    statusPill
                }
            }
            
            // Preview Content
            if !meeting.summary.isEmpty {
                Text(meeting.summary)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textGray)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !meeting.transcript.isEmpty {
                Text(meeting.transcript)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textGray)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(meeting.status == .completed ? "无摘要内容" : "正在处理数据...")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textGray.opacity(0.5))
                    .italic()
            }
            
            // Bottom Meta Row
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                    Text(relativeDate)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(textGray.opacity(0.8))
                
                if meeting.duration > 0 {
                    Spacer().frame(width: 16)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                        Text(meeting.formattedDuration)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(textGray.opacity(0.8))
                }
                
                Spacer()
                
                // Action Items Badge
                if !meeting.actionItems.isEmpty {
                    let done = meeting.actionItems.filter(\.isCompleted).count
                    let total = meeting.actionItems.count
                    let isAllDone = done == total
                    
                    HStack(spacing: 4) {
                        Image(systemName: isAllDone ? "checkmark.circle.fill" : "checklist")
                            .font(.system(size: 12))
                        Text("\(done)/\(total)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isAllDone ? Color.green.opacity(0.1) : primaryBlue.opacity(0.1))
                    .foregroundStyle(isAllDone ? Color.green : primaryBlue)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 15, y: 8)
    }
    
    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 4) {
            if meeting.status == .recording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
            }
            Text(statusLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .foregroundStyle(statusColor)
        .clipShape(Capsule())
    }
}

#Preview {
    MeetingListView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
