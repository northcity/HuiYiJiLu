//
//  MeetingListView.swift
//  Huiyijilu
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Home page — greeting header + grouped, card-style meeting list
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""
    @State private var showRecording = false
    @State private var showSettings = false
    @State private var showAudioImporter = false

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

    private var thisWeekCount: Int {
        meetings.filter { isThisWeek($0.date) || Calendar.current.isDateInToday($0.date) }.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                    if meetings.isEmpty {
                        emptyStateView
                    } else {
                        meetingListContent
                    }
                }

                newMeetingButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { EmptyView() }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showAudioImporter = true } label: {
                        Image(systemName: "doc.badge.plus").foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear").foregroundStyle(.secondary)
                    }
                }
            }
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

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索会议记录...", text: $searchText).autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Meeting List (grouped sections)

    private var meetingListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {

                headerSection.padding(.bottom, 4)

                if !searchText.isEmpty {
                    // Flat list while searching
                    cardRows(for: filteredMeetings)
                    Spacer().frame(height: 110)
                } else {
                    if !todayMeetings.isEmpty {
                        Section {
                            cardRows(for: todayMeetings)
                        } header: {
                            sectionLabel("今天", count: todayMeetings.count)
                        }
                    }
                    if !weekMeetings.isEmpty {
                        Section {
                            cardRows(for: weekMeetings)
                        } header: {
                            sectionLabel("本周", count: weekMeetings.count)
                        }
                    }
                    if !olderMeetings.isEmpty {
                        Section {
                            cardRows(for: olderMeetings)
                        } header: {
                            sectionLabel("更早", count: olderMeetings.count)
                        }
                    }
                    Spacer().frame(height: 110)
                }
            }
        }
    }

    @ViewBuilder
    private func cardRows(for list: [Meeting]) -> some View {
        ForEach(list) { meeting in
            NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                MeetingRowView(meeting: meeting)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { deleteMeeting(meeting) } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - App Header

    private var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("会议记录")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(thisWeekCount)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                Text("本周")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 54, height: 54)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "早上好 ☀️"
        case 12..<14: return "中午好 🌤"
        case 14..<18: return "下午好 🌥"
        case 18..<22: return "晚上好 🌙"
        default:      return "深夜好 🌃"
        }
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            headerSection

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue.opacity(0.4))
            }

            VStack(spacing: 8) {
                Text("还没有会议记录").font(.title3.bold())
                Text("点击下方按钮开始第一次录音")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 100)
    }

    // MARK: - FAB

    private var newMeetingButton: some View {
        Button { showRecording = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill").font(.headline)
                Text("开始录音").fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 1, green: 0.25, blue: 0.25), Color(red: 0.85, green: 0.1, blue: 0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: .red.opacity(0.35), radius: 12, y: 6)
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

        // Start security-scoped access
        guard sourceURL.startAccessingSecurityScopedResource() else { return }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        // Copy file to Recordings directory
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

        // Create a new Meeting with the imported audio
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

    private var statusColor: Color {
        switch meeting.status {
        case .recording:    return .red
        case .transcribing: return .orange
        case .summarizing:  return .purple
        case .completed:    return .blue
        case .failed:       return Color(.systemGray)
        }
    }

    private var statusIcon: String {
        switch meeting.status {
        case .recording:    return "mic.fill"
        case .transcribing: return "text.bubble"
        case .summarizing:  return "brain"
        case .completed:    return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }

    private var statusLabel: String {
        switch meeting.status {
        case .recording:    return "录音中"
        case .transcribing: return "转写中"
        case .summarizing:  return "分析中"
        case .completed:    return "完成"
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
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 4)
                .padding(.vertical, 16)
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 8) {

                // Title + Status pill
                HStack(alignment: .top, spacing: 6) {
                    Text(meeting.title.isEmpty ? "未命名会议" : meeting.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    statusPill
                }

                // Date + Duration tags
                HStack(spacing: 6) {
                    chip(icon: "calendar", text: relativeDate)
                    if meeting.duration > 0 { chip(icon: "clock", text: meeting.formattedDuration) }
                }

                // Summary preview
                if !meeting.summary.isEmpty {
                    Text(meeting.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Bottom badges
                if !meeting.actionItems.isEmpty || !meeting.richNotes.isEmpty || !meeting.tingwuNotes.isEmpty {
                    HStack(spacing: 10) {
                        if !meeting.actionItems.isEmpty {
                            let done  = meeting.actionItems.filter(\.isCompleted).count
                            let total = meeting.actionItems.count
                            badge(icon: done == total ? "checkmark.circle.fill" : "circle",
                                  text: "\(done)/\(total) 任务",
                                  color: done == total ? .green : .blue)
                        }
                        if !meeting.richNotes.isEmpty {
                            badge(icon: "sparkles", text: "图文纪要", color: .purple)
                        }
                        if !meeting.tingwuNotes.isEmpty {
                            badge(icon: "waveform.badge.magnifyingglass", text: "智能纪要", color: .indigo)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 4) {
            if meeting.status != .completed {
                Image(systemName: statusIcon).font(.caption2)
            }
            Text(statusLabel).font(.caption2).fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12))
        .foregroundStyle(statusColor)
        .clipShape(Capsule())
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }

    private func badge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2).fontWeight(.medium)
        }
        .foregroundStyle(color)
    }
}

#Preview {
    MeetingListView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
