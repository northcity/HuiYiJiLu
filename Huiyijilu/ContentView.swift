//
//  ContentView.swift
//  Huiyijilu
//
//  重构：底部 TabBar 架构（会议 / 待办 / 我的）

import SwiftUI
import SwiftData

/// Root view - TabView with 3 tabs
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MeetingListView()
                .tabItem {
                    Label("会议", systemImage: "list.bullet.rectangle.portrait")
                }
                .tag(0)

            TaskListView()
                .tabItem {
                    Label("待办", systemImage: "checklist")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        .tint(Color(red: 0.13, green: 0.47, blue: 1.0))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
