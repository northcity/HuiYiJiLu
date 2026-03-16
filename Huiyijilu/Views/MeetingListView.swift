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
            }
            .onDelete(perform: deleteMeetings)

            // Bottom spacer for FAB
            Color.clear
                .frame(height: 80)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
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

// MARK: - Meeting Row
struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                statusBadge
            }

            HStack(spacing: 12) {
                Label(meeting.date.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if meeting.duration > 0 {
                    Label(meeting.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !meeting.summary.isEmpty {
                Text(meeting.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !meeting.actionItems.isEmpty {
                let completed = meeting.actionItems.filter(\.isCompleted).count
                let total = meeting.actionItems.count
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text("\(completed)/\(total) tasks")
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch meeting.status {
        case .recording:
            Label("Recording", systemImage: "mic.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .transcribing:
            Label("Transcribing", systemImage: "text.bubble")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .summarizing:
            Label("Summarizing", systemImage: "brain")
                .font(.caption2)
                .foregroundStyle(.purple)
        case .completed:
            EmptyView()
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    MeetingListView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
