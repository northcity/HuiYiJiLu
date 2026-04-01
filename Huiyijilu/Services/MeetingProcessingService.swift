//
//  MeetingProcessingService.swift
//  Huiyijilu
//
//  重构 v2：按需分步处理
//  - transcribe(): 用户手动触发转录（阿里云 ASR / 本地）
//  - processWithAI(): 用户按需选择 AI 处理功能
//  - processInBackground(): 旧版兼容（deprecated）

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - AI Task Types

/// AI 大模型处理任务类型
enum AIProcessingTask: String, CaseIterable, Identifiable {
    case title = "title"
    case summary = "summary"
    case chapters = "chapters"
    case actionItems = "actionItems"
    case decisions = "decisions"
    case polish = "polish"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title:       return "生成标题"
        case .summary:     return "全文摘要"
        case .chapters:    return "章节总结"
        case .actionItems: return "提取待办"
        case .decisions:   return "关键决策"
        case .polish:      return "文字润色"
        }
    }

    var icon: String {
        switch self {
        case .title:       return "textformat"
        case .summary:     return "doc.text"
        case .chapters:    return "list.bullet.rectangle"
        case .actionItems: return "checklist"
        case .decisions:   return "lightbulb"
        case .polish:      return "wand.and.stars"
        }
    }
}

@MainActor
final class MeetingProcessingService: ObservableObject {
    static let shared = MeetingProcessingService()

    @Published var processingMeetingIds: Set<UUID> = []
    @Published var transcribingMeetingIds: Set<UUID> = []

    private let transcriptionService = TranscriptionService()
    private let asrService = AliyunASRService()
    private let aiService = AIService()
    private let workflowService = BailianWorkflowService()

    private init() {}

    // =========================================================================
    // MARK: - 阶段二：AI 转录（用户手动触发）
    // =========================================================================

    /// 转录音频（阿里云 ASR 或本地）
    /// - Parameters:
    ///   - meeting: 要转录的会议
    ///   - modelContext: SwiftData 上下文
    ///   - useLocalASR: 是否使用本地 SFSpeechRecognizer（默认 false，使用阿里云）
    func transcribe(meeting: Meeting, modelContext: ModelContext, useLocalASR: Bool = false) async {
        transcribingMeetingIds.insert(meeting.id)
        meeting.status = .transcribing
        try? modelContext.save()

        defer {
            Task { @MainActor in
                self.transcribingMeetingIds.remove(meeting.id)
            }
        }

        guard let audioURL = meeting.audioFileURL else {
            meeting.status = .failed
            try? modelContext.save()
            print("[MeetingProcessing] No audio file for meeting \(meeting.id)")
            return
        }

        do {
            if useLocalASR {
                // 本地转录（免费但质量有限）
                let transcript = try await transcriptionService.transcribe(audioFileURL: audioURL)
                meeting.transcript = transcript
                meeting.transcriptProvider = "local"
            } else {
                // 阿里云 ASR 转录
                let languageHints = resolveLanguageHints(meeting.languageCode)
                let asrModel: AliyunASRService.ASRModel = {
                    let saved = UserDefaults.standard.string(forKey: "asr_model") ?? "paraformer-v2"
                    return AliyunASRService.ASRModel(rawValue: saved) ?? .paraformerV2
                }()
                let enableDiarization = UserDefaults.standard.bool(forKey: "enable_speaker_diarization")

                let result = try await asrService.transcribe(
                    audioFileURL: audioURL,
                    model: asrModel,
                    languageHints: languageHints,
                    diarizationEnabled: enableDiarization
                )

                // 存储格式化文本和原始结果
                meeting.transcript = AliyunASRService.formatForDisplay(result: result)
                meeting.asrRawResult = result.rawJSON
                meeting.transcriptProvider = asrModel.rawValue
            }

            meeting.isTranscribed = true
            meeting.status = .transcribed
            try? modelContext.save()
            print("[MeetingProcessing] Transcription complete for \(meeting.id)")

        } catch {
            meeting.status = .failed
            try? modelContext.save()
            print("[MeetingProcessing] Transcription error: \(error.localizedDescription)")
        }
    }

    /// 将 languageCode 转换为 ASR API 的 language_hints 数组
    private func resolveLanguageHints(_ code: String) -> [String] {
        switch code {
        case "zh":      return ["zh"]
        case "en":      return ["en"]
        case "zh-en":   return ["zh", "en"]
        case "ja":      return ["ja"]
        case "ko":      return ["ko"]
        case "yue":     return ["yue"]
        case "auto":    return ["zh", "en"]   // 默认中英
        default:        return ["zh", "en"]
        }
    }

    // =========================================================================
    // MARK: - 阶段三：AI 大模型处理（用户按需选择功能）
    // =========================================================================

    /// 使用 AI 大模型处理转录文本
    /// - Parameters:
    ///   - meeting: 已转录的会议
    ///   - modelContext: SwiftData 上下文
    ///   - tasks: 要执行的 AI 任务集合
    func processWithAI(meeting: Meeting, modelContext: ModelContext, tasks: Set<AIProcessingTask>) async {
        guard meeting.isTranscribed, !meeting.transcript.isEmpty else {
            print("[MeetingProcessing] Cannot process: meeting not transcribed")
            return
        }

        processingMeetingIds.insert(meeting.id)
        meeting.status = .processing
        try? modelContext.save()

        defer {
            Task { @MainActor in
                self.processingMeetingIds.remove(meeting.id)
            }
        }

        let transcript = meeting.transcript

        do {
            // 如果选了 title/summary/actionItems，使用现有 AIService.generateSummary
            if tasks.contains(.title) || tasks.contains(.summary) || tasks.contains(.actionItems) {
                let apiKey = AIConfig.shared.currentConfig.apiKey
                if !apiKey.isEmpty {
                    let summaryResult = try await aiService.generateSummary(transcript: transcript)

                    if tasks.contains(.title) {
                        meeting.title = summaryResult.title
                    }
                    if tasks.contains(.summary) {
                        meeting.summary = summaryResult.summary
                        meeting.keyPointsList = summaryResult.keyPoints
                    }
                    if tasks.contains(.actionItems) {
                        // 清除旧的行动项
                        for item in meeting.actionItems {
                            modelContext.delete(item)
                        }
                        for item in summaryResult.actionItems {
                            let actionItem = ActionItem(title: item.title, assignee: item.assignee, meeting: meeting)
                            modelContext.insert(actionItem)
                        }
                    }
                }
            }

            // 润色: 生成 rich notes (Markdown)
            if tasks.contains(.polish) || tasks.contains(.chapters) || tasks.contains(.decisions) {
                if let notes = try? await aiService.generateRichNotes(transcript: transcript) {
                    meeting.richNotes = notes
                }
            }

            meeting.isAIProcessed = true
            meeting.status = .completed
            try? modelContext.save()
            print("[MeetingProcessing] AI processing complete for \(meeting.id)")

        } catch {
            // 即使 AI 处理失败，保持 transcribed 状态而非 failed
            meeting.status = .transcribed
            try? modelContext.save()
            print("[MeetingProcessing] AI processing error: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - 一键处理（转录 + AI 全部）
    // =========================================================================

    /// 一键完成转录 + AI 处理
    func processAll(meeting: Meeting, modelContext: ModelContext) async {
        await transcribe(meeting: meeting, modelContext: modelContext)

        if meeting.isTranscribed {
            await processWithAI(
                meeting: meeting,
                modelContext: modelContext,
                tasks: Set(AIProcessingTask.allCases)
            )
        }
    }

    // =========================================================================
    // MARK: - 旧版兼容（Deprecated）
    // =========================================================================

    /// 旧版后台处理接口 — 保留兼容性
    @available(*, deprecated, message: "Use transcribe() + processWithAI() instead")
    func processInBackground(meeting: Meeting, modelContext: ModelContext) {
        processingMeetingIds.insert(meeting.id)

        Task {
            await processAll(meeting: meeting, modelContext: modelContext)
            processingMeetingIds.remove(meeting.id)
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    func generateBasicTitle(from transcript: String) -> String {
        let words = transcript.prefix(50).components(separatedBy: .whitespacesAndNewlines).prefix(6)
        let title = words.joined(separator: " ")
        return title.isEmpty ? "会议 \(Date().formatted(date: .abbreviated, time: .shortened))" : title + "..."
    }
}
