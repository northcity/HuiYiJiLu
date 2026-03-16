//
//  ContentView.swift
//  Huiyijilu
//

import SwiftUI
import SwiftData

/// Root view - delegates to MeetingListView
struct ContentView: View {
    var body: some View {
        MeetingListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Meeting.self, ActionItem.self], inMemory: true)
}
