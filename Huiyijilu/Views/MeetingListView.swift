//
//  MeetingListView.swift
//  Huiyijilu
//

import SwiftUI
import SwiftData

/// Home page - list of all meetings with search
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""
    @State private var showRecording = false
    @State private var showSettings = false

    var filteredMeetings: [Meeting] {
        if searchText.isEmpty { return meetings }
        return meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(searchText) ||
            meeting.transcript.localizedCaseInsensitiveContains(searchText) ||
            meeting.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if meetings.isEmpty {
                    emptyStateView
                } else {
                    meetingListContent
                }
            }
            .navigationTitle("Meeting Notes")
            .searchable(text: $searchText, prompt: "Search meetings...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                newMeetingButton
            }
            .fullScreenCover(isPresented: $showRecording) {
                RecordingView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("No Meetings Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the button below to start\nrecording your first meeting")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 100)
    }

    // MARK: - Meeting List
    private var meetingListContent: some View {
        List {
            ForEach(filteredMeetings) { meeting in
                NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                    MeetingRowView(meeting: meeting)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteMeetings)

            // Bottom spacer for FAB
            Color.clear
                .frame(height: 80)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - New Meeting Button
    private var newMeetingButton: some View {
        Button {
            showRecording = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                Text("New Meeting")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.red)
                    .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
            )
        }
        .padding(.bottom, 30)
    }

    private func deleteMeetings(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let meeting = filteredMeetings[index]
                // Delete audio file
                if let url = meeting.audioFileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                modelContext.delete(meeting)
            }
        }
    }
}

// MARK: - Meeting Row (Card Style)
struct MeetingRowView: View {
    let meeting: Meeting

    // MARK: - Status helpers
    private var statusColor: Color {
        switch meeting.status {
        case .recording:   return .red
        case .transcribing: return .orange
        case .summarizing:  return .purple
        case .completed:    return .green
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
        case .completed:    return "已完成"
        case .failed:       return "失败"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // — Top Row: Title + Status Pill
            HStack(alignment: .top, spacing: 8) {
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Spacer()

                // Status pill
                HStack(spacing: 4) {
                    if meeting.status != .completed {
                        Image(systemName: statusIcon)
                            .font(.caption2)
                    }
                    Text(statusLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
            }

            // — Tags Row: Date + Duration
            HStack(spacing: 8) {
                tagView(icon: "calendar", text: meeting.date.formatted(date: .abbreviated, time: .shortened))
                if meeting.duration > 0 {
                    tagView(icon: "clock", text: meeting.formattedDuration)
                }
                if !meeting.richNotes.isEmpty {
                    tagView(icon: "sparkles", text: "图文纪要")
                        .foregroundStyle(.purple)
                }
            }

            // — Summary preview
            if !meeting.summary.isEmpty {
                Text(meeting.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // — Divider + Action items badge
            if !meeting.actionItems.isEmpty {
                Divider()
                let completed = meeting.actionItems.filter(\.isCompleted).count
                let total     = meeting.actionItems.count
                HStack(spacing: 4) {
                    Image(systemName: completed == total ? "checklist.checked" : "checklist")
                    Text("\(completed)/\(total) 任务")
                    if completed == total {
                        Text("· 全部完成").foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
    }

    private func tagView(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }
}

#Preview {
    MeetingListView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
