//
//  Meeting.swift
//  Huiyijilu
//

import Foundation
import SwiftData

/// Meeting status enum
enum MeetingStatus: String, Codable {
    case recording = "recording"
    case transcribing = "transcribing"
    case summarizing = "summarizing"
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
