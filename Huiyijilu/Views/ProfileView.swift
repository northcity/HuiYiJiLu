//
//  ProfileView.swift
//  Huiyijilu
//
//  "我的"页面 — 使用统计 + 设置入口

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @Query private var actionItems: [ActionItem]

    @State private var showSettings = false

    // MARK: - Stats

    private var totalMeetings: Int { meetings.count }

    private var totalDuration: TimeInterval {
        meetings.reduce(0) { $0 + $1.duration }
    }

    private var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var thisMonthMeetings: Int {
        let now = Date()
        return meetings.filter {
            Calendar.current.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count
    }

    private var completionRate: Int {
        guard !actionItems.isEmpty else { return 100 }
        let done = actionItems.filter(\.isCompleted).count
        return Int(Double(done) / Double(actionItems.count) * 100)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // User header
                    userHeader

                    // Stats grid
                    statsGrid

                    // Quick actions
                    quickActions

                    // App info
                    appInfoSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - User Header

    private var userHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.13, green: 0.47, blue: 1.0), Color(red: 0.13, green: 0.47, blue: 1.0).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("云雀记用户")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("累计 \(totalMeetings) 场会议")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用统计")
                .font(.headline)
                .padding(.leading, 4)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ProfileStatCard(
                    icon: "calendar",
                    value: "\(thisMonthMeetings)",
                    label: "本月会议",
                    color: .blue
                )
                ProfileStatCard(
                    icon: "clock",
                    value: formattedTotalDuration,
                    label: "累计时长",
                    color: .purple
                )
                ProfileStatCard(
                    icon: "checklist",
                    value: "\(actionItems.count)",
                    label: "待办总数",
                    color: .orange
                )
                ProfileStatCard(
                    icon: "chart.line.uptrend.xyaxis",
                    value: "\(completionRate)%",
                    label: "完成率",
                    color: completionRate >= 80 ? .green : (completionRate >= 50 ? .orange : .red)
                )
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 0) {
            ProfileActionRow(icon: "gearshape", title: "设置", subtitle: "AI模型、录音、云服务配置") {
                showSettings = true
            }

            Divider().padding(.leading, 52)

            ProfileActionRow(icon: "questionmark.circle", title: "帮助与反馈", subtitle: "使用说明和问题反馈") {
                // TODO: help & feedback
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        VStack(spacing: 8) {
            Text("云雀记")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("版本 \(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Profile Stat Card

private struct ProfileStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
}

// MARK: - Profile Action Row

private struct ProfileActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
