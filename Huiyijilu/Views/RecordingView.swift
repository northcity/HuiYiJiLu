//
//  RecordingView.swift
//  Huiyijilu
//

import SwiftUI
import SwiftData

/// Full-screen recording view with timer and controls
struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var recorder = AudioRecorderService()
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var aiService = AIService()
    @StateObject private var workflowService = BailianWorkflowService()

    @State private var isProcessing = false
    @State private var processingStage = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentMeeting: Meeting?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: recorder.isRecording && !recorder.isPaused
                    ? [Color.red.opacity(0.1), Color(.systemBackground)]
                    : [Color(.systemBackground), Color(.systemBackground)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                // Header
                HStack {
                    Button("Cancel") {
                        if recorder.isRecording {
                            recorder.stopRecording()
                        }
                        dismiss()
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
        VStack(spacing: 40) {
            // Waveform indicator
            waveformView

            // Timer
            Text(formatTime(recorder.recordingTime))
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(recorder.isRecording && !recorder.isPaused ? .primary : .secondary)

            // Status text
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)

            // Controls
            recordingControls
        }
    }

    private var statusText: String {
        if !recorder.isRecording { return "Tap to start recording" }
        if recorder.isPaused { return "Paused" }
        return "Recording..."
    }

    // MARK: - Waveform
    private var waveformView: some View {
        HStack(spacing: 4) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(recorder.isRecording && !recorder.isPaused ? Color.red : Color.gray.opacity(0.3))
                    .frame(width: 4, height: barHeight(for: i))
                    .animation(
                        .easeInOut(duration: 0.3).delay(Double(i) * 0.02),
                        value: recorder.audioLevel
                    )
            }
        }
        .frame(height: 60)
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard recorder.isRecording && !recorder.isPaused else { return 8 }
        let base: CGFloat = 8
        let variation = CGFloat(recorder.audioLevel) * 52
        let offset = sin(Double(index) * 0.5 + recorder.recordingTime * 3) * 0.5 + 0.5
        return base + variation * CGFloat(offset)
    }

    // MARK: - Controls
    private var recordingControls: some View {
        HStack(spacing: 50) {
            if recorder.isRecording {
                // Pause / Resume
                Button {
                    if recorder.isPaused {
                        recorder.resumeRecording()
                    } else {
                        recorder.pauseRecording()
                    }
                } label: {
                    Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.gray))
                }

                // Stop
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
            } else {
                // Start
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
                errorMessage = "Speech recognition permission is required"
                showError = true
                return
            }

            do {
                try recorder.startRecording()
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func stopAndProcess() {
        let result = recorder.stopRecording()
        isProcessing = true

        // Create meeting immediately
        let meeting = Meeting(title: "Processing...", date: Date(), duration: result.duration)
        meeting.audioFileName = result.fileName
        meeting.status = .transcribing
        modelContext.insert(meeting)
        try? modelContext.save()
        currentMeeting = meeting

        // Process in background
        Task {
            await processRecording(meeting: meeting)
        }
    }

    private func processRecording(meeting: Meeting) async {
        // Step 1: Transcribe
        processingStage = "Transcribing audio..."
        meeting.status = .transcribing

        guard let audioURL = meeting.audioFileURL else {
            meeting.status = .failed
            errorMessage = "Audio file not found"
            showError = true
            isProcessing = false
            return
        }

        do {
            let transcript = try await transcriptionService.transcribe(audioFileURL: audioURL)
            meeting.transcript = transcript

            // Step 2: AI Summary
            processingStage = "AI analyzing meeting..."
            meeting.status = .summarizing

            if !UserDefaults.standard.string(forKey: "openai_api_key").isNilOrEmpty {
                let summaryResult = try await aiService.generateSummary(transcript: transcript)
                meeting.title = summaryResult.title
                meeting.summary = summaryResult.summary
                meeting.keyPointsList = summaryResult.keyPoints

                // Create action items
                for item in summaryResult.actionItems {
                    let actionItem = ActionItem(title: item.title, assignee: item.assignee, meeting: meeting)
                    modelContext.insert(actionItem)
                }

                // Step 3: Rich notes (workflow → LLM fallback)
                processingStage = "生成图文纪要..."
                await generateRichNotesWithFallback(for: meeting, transcript: transcript)
            } else {
                // No API key - use basic title
                meeting.title = generateBasicTitle(from: transcript)
                meeting.summary = "Set up API Key in Settings to enable AI summaries"
            }

            meeting.status = .completed
            try? modelContext.save()

            isProcessing = false
            dismiss()

        } catch {
            meeting.status = .failed
            meeting.title = "Meeting \(meeting.date.formatted(date: .abbreviated, time: .shortened))"
            try? modelContext.save()

            errorMessage = error.localizedDescription
            showError = true
            isProcessing = false
            dismiss()
        }
    }

    /// Try Bailian workflow (with audio file) first; fall back to LLM text-based generation.
    private func generateRichNotesWithFallback(for meeting: Meeting, transcript: String) async {
        // 1. Try workflow with audio file
        if workflowService.isConfigured, let audioURL = meeting.audioFileURL {
            if let notes = try? await workflowService.generateRichNotes(audioFileURL: audioURL),
               !notes.contains("视频为空"), !notes.contains("请提供视频"), notes.count > 30 {
                meeting.richNotes = notes
                return
            }
        }
        // 2. Fallback: LLM direct generation from transcript
        if let notes = try? await aiService.generateRichNotes(transcript: transcript) {
            meeting.richNotes = notes
        }
    }

    private func generateBasicTitle(from transcript: String) -> String {
        let words = transcript.prefix(50).components(separatedBy: .whitespacesAndNewlines).prefix(6)
        let title = words.joined(separator: " ")
        return title.isEmpty ? "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))" : title + "..."
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
