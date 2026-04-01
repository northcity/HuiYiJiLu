//
//  RecordingBookmark.swift
//  Huiyijilu
//
//  录音打点/笔记/照片标记数据结构
//  存储为 JSON 字符串在 Meeting.bookmarks 字段中

import Foundation

/// 录音过程中的标记（打点、笔记、照片）
struct RecordingBookmark: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var timestamp: TimeInterval       // 录音时间点（秒）
    var label: String                 // 标签内容
    var type: BookmarkType            // 标记类型
    var photoFileName: String?        // 仅 type == .photo 时有值

    enum BookmarkType: String, Codable {
        case flag       // 打点标记
        case note       // 文字笔记
        case photo      // 拍照
    }

    init(timestamp: TimeInterval, label: String = "", type: BookmarkType = .flag, photoFileName: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.label = label
        self.type = type
        self.photoFileName = photoFileName
    }

    /// 格式化时间戳为 mm:ss 或 hh:mm:ss
    var formattedTimestamp: String {
        let hours = Int(timestamp) / 3600
        let minutes = (Int(timestamp) % 3600) / 60
        let seconds = Int(timestamp) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var displayIcon: String {
        switch type {
        case .flag:  return "flag.fill"
        case .note:  return "note.text"
        case .photo: return "camera.fill"
        }
    }

    var displayLabel: String {
        if !label.isEmpty { return label }
        switch type {
        case .flag:  return "打点"
        case .note:  return "笔记"
        case .photo: return "照片"
        }
    }
}
