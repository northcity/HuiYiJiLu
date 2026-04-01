//
//  TaskListView.swift
//  Huiyijilu
//
//  跨会议待办聚合页 — 所有会议中提取的待办事项集中管理

import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActionItem.createdAt, order: .reverse) private var allItems: [ActionItem]

    @State private var filterMode: TaskFilter = .pending

    enum TaskFilter: String, CaseIterable {
        case all = "全部"
        case pending = "未完成"
        case completed = "已完成"
    }

    private var filteredItems: [ActionItem] {
        switch filterMode {
        case .all: return allItems
        case .pending: return allItems.filter { !$0.isCompleted }
        case .completed: return allItems.filter { $0.isCompleted }
        }
    }

    private var pendingCount: Int {
        allItems.filter { !$0.isCompleted }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stats header
                statsHeader

                // Filter picker
                Picker("筛选", selection: $filterMode) {
                    ForEach(TaskFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    taskList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("待办事项")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 20) {
            StatCard(
                value: "\(allItems.count)",
                label: "总计",
                color: .blue
            )
            StatCard(
                value: "\(pendingCount)",
                label: "待完成",
                color: pendingCount > 0 ? .orange : .green
            )
            StatCard(
                value: "\(allItems.count - pendingCount)",
                label: "已完成",
                color: .green
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Task List

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredItems) { item in
                    TaskItemCard(item: item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: filterMode == .completed ? "checkmark.circle" : "checklist")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(filterMode == .completed ? "还没有已完成的待办" : (filterMode == .pending ? "所有待办都完成了" : "还没有待办事项"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("会议中 AI 自动提取的待办事项会出现在这里")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Task Item Card

private struct TaskItemCard: View {
    @Bindable var item: ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    item.isCompleted.toggle()
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 12) {
                    if !item.assignee.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(item.assignee)
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }

                    if let meeting = item.meeting {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text(meeting.title.isEmpty ? "未命名会议" : meeting.title)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }
}

#Preview {
    TaskListView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
