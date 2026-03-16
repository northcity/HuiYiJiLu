//
//  ActionItem.swift
//  Huiyijilu
//

import Foundation
import SwiftData

/// Action item model - extracted from meetings by AI
@Model
final class ActionItem {
    var id: UUID
    var title: String
    var assignee: String
    var isCompleted: Bool
    var createdAt: Date

    var meeting: Meeting?

    init(title: String, assignee: String = "", meeting: Meeting? = nil) {
        self.id = UUID()
        self.title = title
        self.assignee = assignee
        self.isCompleted = false
        self.createdAt = Date()
        self.meeting = meeting
    }
}
