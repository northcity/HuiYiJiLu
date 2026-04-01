//
//  Meeting.swift
//  Huiyijilu
//

import Foundation
import SwiftData

/// Meeting status enum
enum MeetingStatus: String, Codable {
    case recording = "recording"
    case saved = "saved"                  // 录音已保存（终态之一）
    case transcribing = "transcribing"
    case transcribed = "transcribed"      // 转录完成（终态之一）
    case summarizing = "summarizing"
    case processing = "processing"        // AI 大模型处理中
    case completed = "completed"
    case failed = "failed"
}

/// Meeting data model
@Model
final class Meeting {
    var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var audioFileName: String
    var transcript: String
    var summary: String
    var keyPoints: String
    var statusRaw: String
    var richNotes: String                   // output from Bailian workflow app
    var tingwuNotes: String = ""            // output from TingWu meeting smart notes
    var tingwuDataId: String = ""           // TingWu task dataId (for polling)
    var tingwuRawResults: String = ""       // Raw JSON results from TingWu (for detail view)

    // === 新增字段（v2 重构） ===
    var languageCode: String = "zh"             // 录音时选择的语言 (zh/en/ja/ko/yue/auto)
    var bookmarksJSON: String = "[]"            // 录音打点 JSON [RecordingBookmark]
    var sourceType: String = "microphone"       // 来源: microphone / system / import
    var transcriptProvider: String = ""         // 转录来源: "" / local / paraformer-v2 / fun-asr / tingwu
    var isTranscribed: Bool = false
    var isAIProcessed: Bool = false
    var asrRawResult: String = ""               // ASR 原始 JSON 结果（含时间戳、说话人等）

    @Relationship(deleteRule: .cascade)
    var actionItems: [ActionItem] = []

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .recording }
        set { statusRaw = newValue.rawValue }
    }

    var keyPointsList: [String] {
        get {
            guard !keyPoints.isEmpty,
                  let data = keyPoints.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                keyPoints = str
            }
        }
    }

    /// 录音打点列表（存储为 JSON）
    var bookmarksList: [RecordingBookmark] {
        get {
            guard !bookmarksJSON.isEmpty,
                  let data = bookmarksJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([RecordingBookmark].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                bookmarksJSON = str
            }
        }
    }

    var audioFileURL: URL? {
        guard !audioFileName.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Recordings").appendingPathComponent(audioFileName)
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    init(title: String = "", date: Date = Date(), duration: TimeInterval = 0) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.duration = duration
        self.audioFileName = ""
        self.transcript = ""
        self.summary = ""
        self.keyPoints = "[]"
        self.richNotes = ""
        self.tingwuNotes = ""
        self.tingwuDataId = ""
        self.statusRaw = MeetingStatus.recording.rawValue
    }
}
