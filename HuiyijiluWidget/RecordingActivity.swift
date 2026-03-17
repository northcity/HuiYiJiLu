//
//  RecordingActivity.swift
//  HuiyijiluWidget
//
//  Shared ActivityAttributes definition — must match the copy in Huiyijilu/Models/.
//

import Foundation
import ActivityKit

/// Attributes for the recording Live Activity displayed on the Dynamic Island and Lock Screen.
struct RecordingAttributes: ActivityAttributes {

    /// Dynamic state that updates while the activity is active.
    public struct ContentState: Codable, Hashable {
        /// Elapsed recording time in seconds.
        var elapsedSeconds: Int
        /// Recording mode label ("内录" or "麦克风").
        var mode: String
        /// Whether the recording is still in progress.
        var isActive: Bool
    }

    /// Static context that doesn't change during the activity.
    /// The start date of the recording.
    var startDate: Date
}
