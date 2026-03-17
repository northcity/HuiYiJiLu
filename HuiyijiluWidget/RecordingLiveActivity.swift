//
//  RecordingLiveActivity.swift
//  HuiyijiluWidget
//
//  Live Activity UI for Dynamic Island and Lock Screen.
//  Shows recording status, elapsed time, and mode indicator.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            // ── Lock Screen / StandBy Live Activity Banner ──
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded Regions ──
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.mode == "内录" ? "record.circle" : "mic.fill")
                            .foregroundStyle(context.state.mode == "内录" ? .purple : .red)
                            .font(.title3)
                        Text(context.state.mode)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(context.state.isActive ? .primary : .secondary)
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("会议录制中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // Animated recording indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(context.state.isActive ? Color.red : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(context.state.isActive ? "录制中" : "已暂停")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Start time
                        Text("开始于 \(context.attributes.startDate, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // ── Compact Leading ──
                HStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(context.state.mode == "内录" ? .purple : .red)
                }
            } compactTrailing: {
                // ── Compact Trailing ──
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(context.state.isActive ? .primary : .secondary)
                    .contentTransition(.numericText())
            } minimal: {
                // ── Minimal (when another activity is also active) ──
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(context.state.mode == "内录" ? .purple : .red)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingAttributes>) -> some View {
        HStack(spacing: 16) {
            // Left: mode icon
            VStack {
                Image(systemName: context.state.mode == "内录" ? "record.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(context.state.mode == "内录" ? .purple : .red)
            }

            // Center: info
            VStack(alignment: .leading, spacing: 4) {
                Text("会议录制")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    // Recording indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(context.state.isActive ? Color.red : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(context.state.isActive ? "录制中" : "已暂停")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text(context.state.mode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right: timer
            Text(formatTime(context.state.elapsedSeconds))
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(context.state.isActive ? .primary : .secondary)
                .contentTransition(.numericText())
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
