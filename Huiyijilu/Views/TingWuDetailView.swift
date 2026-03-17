//
//  TingWuDetailView.swift
//  Huiyijilu
//
//  通义听悟·智能纪要详情页
//  展示结构化的会议分析结果，包括对话内容(口语书面化)、智能速览、思维导图
//

import SwiftUI
import SwiftData

// MARK: - Data Models

/// Parsed paragraph from transcription
struct TingWuParagraph: Identifiable {
    let id = UUID()
    let speakerLabel: String
    let timestamp: String       // "00:05"
    let text: String
    let beginTimeMs: Int
    var polishedText: String = ""   // 口语书面化 text from textPolish
}

/// Mind map tree node (from summarization.mindMapSummary)
struct TingWuMindMapNode: Identifiable {
    let id = UUID()
    let title: String
    var children: [TingWuMindMapNode] = []
}

/// Smart overview sub-tabs
enum SmartOverviewTab: String, CaseIterable {
    case summary = "全文概要"
    case chapters = "章节速览"
    case speakers = "发言总结"
    case qa = "要点回顾"
    case actions = "待办事项"
}

/// Parsed analysis data from all result types
struct TingWuAnalysis {
    var summary: String = ""                                    // paragraphSummary
    var keywords: [String] = []                                 // meetingAssistance.keywords
    var chapters: [(title: String, summary: String)] = []       // autoChapters
    var actionItems: [String] = []                              // meetingAssistance.actions
    var speakerSummaries: [(name: String, summary: String)] = [] // conversationalSummary
    var questionsAnswers: [(q: String, a: String)] = []         // questionsAnsweringSummary
    var mindMapNodes: [TingWuMindMapNode] = []                  // mindMapSummary
    var customPrompt: String = ""                               // customPrompt result
    var availableResults: [String] = []                         // downloaded result type names
}

// MARK: - Detail View

struct TingWuDetailView: View {
    @Bindable var meeting: Meeting
    @State private var selectedMainTab = 0
    @State private var selectedSubTab: SmartOverviewTab = .summary
    @State private var showPolishedText = false
    @State private var paragraphs: [TingWuParagraph] = []
    @State private var analysis = TingWuAnalysis()
    @State private var parseError = ""
    
    private var hasPolishedText: Bool {
        paragraphs.contains { !$0.polishedText.isEmpty }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main tab picker
            Picker("Section", selection: $selectedMainTab) {
                Text("对话内容").tag(0)
                Text("智能速览").tag(1)
                Text("思维导图").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Tab content
            switch selectedMainTab {
            case 0: conversationTab
            case 1: smartOverviewTab
            case 2: mindMapTab
            default: EmptyView()
            }
        }
        .navigationTitle("智能纪要")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !meeting.tingwuDataId.isEmpty {
                    Menu {
                        Button(action: { UIPasteboard.general.string = meeting.tingwuDataId }) {
                            Label("复制 DataId", systemImage: "doc.on.doc")
                        }
                        if !meeting.tingwuRawResults.isEmpty {
                            Button(action: { UIPasteboard.general.string = meeting.tingwuRawResults }) {
                                Label("复制原始数据", systemImage: "doc.on.clipboard")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear { parseData() }
    }
    
    // MARK: - Tab 1: 对话内容
    
    private var conversationTab: some View {
        Group {
            if paragraphs.isEmpty {
                emptyStateView(icon: "text.bubble", title: "暂无对话内容", subtitle: "转写数据尚未解析或格式不支持")
            } else {
                VStack(spacing: 0) {
                    // 口语书面化 toggle bar
                    if hasPolishedText {
                        HStack {
                            Image(systemName: "pencil.line")
                                .foregroundStyle(.indigo)
                                .font(.subheadline)
                            Text("口语书面化")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: $showPolishedText)
                                .labelsHidden()
                                .tint(.indigo)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                    }
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(paragraphs) { para in
                                ConversationBubble(
                                    paragraph: para,
                                    showPolished: showPolishedText
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 2: 智能速览
    
    private var smartOverviewTab: some View {
        let hasAnyAnalysis = !analysis.summary.isEmpty || !analysis.keywords.isEmpty ||
            !analysis.chapters.isEmpty || !analysis.actionItems.isEmpty ||
            !analysis.speakerSummaries.isEmpty || !analysis.questionsAnswers.isEmpty ||
            !analysis.customPrompt.isEmpty
        
        return Group {
            if !hasAnyAnalysis {
                emptyStateView(
                    icon: "waveform.badge.magnifyingglass",
                    title: "暂无分析数据",
                    subtitle: "请在阿里云听悟控制台的应用配置中\n启用\"会议纪要\"、\"智能摘要\"等分析功能"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 关键词 tags at top
                        if !analysis.keywords.isEmpty {
                            keywordsSection
                        }
                        
                        // Sub-tab picker (horizontal scroll)
                        subTabPicker
                        
                        // Sub-tab content
                        subTabContent
                        
                        // 自定义Prompt (if available, show as extra section)
                        if !analysis.customPrompt.isEmpty {
                            AnalysisSection(title: "自定义分析", icon: "sparkles") {
                                Text(analysis.customPrompt)
                                    .font(.body)
                                    .lineSpacing(5)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var keywordsSection: some View {
        AnalysisSection(title: "关键词", icon: "tag") {
            FlowLayout(spacing: 8) {
                ForEach(analysis.keywords, id: \.self) { keyword in
                    Text(keyword)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.indigo.opacity(0.1)))
                        .foregroundStyle(.indigo)
                }
            }
        }
    }
    
    private var subTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(SmartOverviewTab.allCases, id: \.self) { tab in
                    let isSelected = selectedSubTab == tab
                    let hasContent = subTabHasContent(tab)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSubTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? .indigo : (hasContent ? .primary : .secondary))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Group {
                                    if isSelected {
                                        Capsule().fill(Color.indigo.opacity(0.1))
                                    }
                                }
                            )
                    }
                    .disabled(!hasContent)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func subTabHasContent(_ tab: SmartOverviewTab) -> Bool {
        switch tab {
        case .summary: return !analysis.summary.isEmpty
        case .chapters: return !analysis.chapters.isEmpty
        case .speakers: return !analysis.speakerSummaries.isEmpty
        case .qa: return !analysis.questionsAnswers.isEmpty
        case .actions: return !analysis.actionItems.isEmpty
        }
    }
    
    @ViewBuilder
    private var subTabContent: some View {
        switch selectedSubTab {
        case .summary:
            if !analysis.summary.isEmpty {
                AnalysisSection(title: "全文概要", icon: "doc.text") {
                    Text(analysis.summary)
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
            } else {
                subTabEmptyView("暂无全文概要")
            }
            
        case .chapters:
            if !analysis.chapters.isEmpty {
                AnalysisSection(title: "章节速览", icon: "list.bullet.rectangle") {
                    ForEach(Array(analysis.chapters.enumerated()), id: \.offset) { idx, chapter in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapter.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if !chapter.summary.isEmpty {
                                Text(chapter.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        if idx < analysis.chapters.count - 1 { Divider() }
                    }
                }
            } else {
                subTabEmptyView("暂无章节速览")
            }
            
        case .speakers:
            if !analysis.speakerSummaries.isEmpty {
                AnalysisSection(title: "发言总结", icon: "person.wave.2") {
                    ForEach(Array(analysis.speakerSummaries.enumerated()), id: \.offset) { idx, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.indigo)
                            Text(item.summary)
                                .font(.subheadline)
                                .lineSpacing(3)
                        }
                        .padding(.vertical, 4)
                        if idx < analysis.speakerSummaries.count - 1 { Divider() }
                    }
                }
            } else {
                subTabEmptyView("暂无发言总结")
            }
            
        case .qa:
            if !analysis.questionsAnswers.isEmpty {
                AnalysisSection(title: "要点回顾", icon: "questionmark.bubble") {
                    ForEach(Array(analysis.questionsAnswers.enumerated()), id: \.offset) { idx, qa in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 6) {
                                Text("Q")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.indigo))
                                Text(qa.q)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            if !qa.a.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("A")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(Color.teal))
                                    Text(qa.a)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        if idx < analysis.questionsAnswers.count - 1 { Divider() }
                    }
                }
            } else {
                subTabEmptyView("暂无要点回顾")
            }
            
        case .actions:
            if !analysis.actionItems.isEmpty {
                AnalysisSection(title: "待办事项", icon: "checklist") {
                    ForEach(Array(analysis.actionItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "square")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            Text(item)
                                .font(.subheadline)
                                .lineSpacing(3)
                        }
                    }
                }
            } else {
                subTabEmptyView("暂无待办事项")
            }
        }
    }
    
    private func subTabEmptyView(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }
    
    // MARK: - Tab 3: 思维导图
    
    private var mindMapTab: some View {
        Group {
            if analysis.mindMapNodes.isEmpty {
                emptyStateView(icon: "brain", title: "暂无思维导图", subtitle: "请在听悟控制台启用\"智能摘要\"功能")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "brain")
                                .foregroundStyle(.indigo)
                            Text("思维导图")
                                .font(.headline)
                        }
                        .padding(.bottom, 12)
                        
                        ForEach(analysis.mindMapNodes) { node in
                            MindMapNodeView(node: node, depth: 0)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Data Parsing
    
    private func parseData() {
        let rawJSON = meeting.tingwuRawResults
        print("[TingWuDetail] parseData: tingwuRawResults=\(rawJSON.count) chars")
        
        guard !rawJSON.isEmpty else {
            parseNotesAsConversation()
            return
        }
        
        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            parseError += "无法解析原始结果 JSON。\n"
            parseNotesAsConversation()
            return
        }
        
        let availableKeys = dict.keys.filter { !(dict[$0] ?? "").isEmpty }.sorted()
        analysis.availableResults = availableKeys
        print("[TingWuDetail] Available results: \(availableKeys)")
        for key in availableKeys {
            print("[TingWuDetail]   \(key): \(dict[key]?.count ?? 0) chars")
        }
        
        // Parse transcription → conversation paragraphs
        if let raw = dict["transcription"], !raw.isEmpty,
           let tData = raw.data(using: .utf8),
           let tJson = try? JSONSerialization.jsonObject(with: tData) as? [String: Any] {
            extractParagraphs(from: tJson)
        } else {
            parseNotesAsConversation()
        }
        
        // Parse textPolish → pair polished text with original paragraphs
        if let raw = dict["textPolish"], !raw.isEmpty,
           let d = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            print("[TingWuDetail] textPolish keys: \(json.keys.sorted())")
            applyPolishedText(from: json)
        }
        
        // Parse meetingAssistance → keywords, actionItems
        if let raw = dict["meetingAssistance"], !raw.isEmpty,
           let d = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            print("[TingWuDetail] meetingAssistance keys: \(json.keys.sorted())")
            extractMeetingAssistance(from: json)
        }
        
        // Parse summarization → summary, speakers, QA, mindMap
        if let raw = dict["summarization"], !raw.isEmpty,
           let d = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            print("[TingWuDetail] summarization keys: \(json.keys.sorted())")
            extractSummarization(from: json)
        }
        
        // Parse autoChapters → chapters
        if let raw = dict["autoChapters"], !raw.isEmpty,
           let d = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            print("[TingWuDetail] autoChapters keys: \(json.keys.sorted())")
            extractChapters(from: json)
        }
        
        // Parse customPrompt → custom analysis result
        if let raw = dict["customPrompt"], !raw.isEmpty {
            if let d = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                print("[TingWuDetail] customPrompt keys: \(json.keys.sorted())")
                analysis.customPrompt = extractTextContent(from: json)
            } else {
                analysis.customPrompt = raw
            }
        }
        
        // Auto-select first sub-tab that has content
        if !analysis.summary.isEmpty { selectedSubTab = .summary }
        else if !analysis.chapters.isEmpty { selectedSubTab = .chapters }
        else if !analysis.speakerSummaries.isEmpty { selectedSubTab = .speakers }
        else if !analysis.questionsAnswers.isEmpty { selectedSubTab = .qa }
        else if !analysis.actionItems.isEmpty { selectedSubTab = .actions }
    }
    
    // MARK: - Paragraph Extractor
    
    private func extractParagraphs(from json: [String: Any]) {
        var paras: [[String: Any]]? = nil
        
        if let trans = json["transcription"] as? [String: Any],
           let p = trans["paragraphs"] as? [[String: Any]] {
            paras = p
        } else if let body = json["body"] as? [String: Any],
                  let trans = body["transcription"] as? [String: Any],
                  let p = trans["paragraphs"] as? [[String: Any]] {
            paras = p
        } else if let p = json["paragraphs"] as? [[String: Any]] {
            paras = p
        }
        
        guard let paragraphDicts = paras else {
            parseError += "未找到 paragraphs 数组。keys=\(json.keys.sorted())\n"
            return
        }
        
        print("[TingWuDetail] extractParagraphs: \(paragraphDicts.count) paragraphs")
        
        paragraphs = paragraphDicts.compactMap { p -> TingWuParagraph? in
            // Get text: try direct, then reconstruct from words array
            var text = p["text"] as? String ?? p["content"] as? String ?? ""
            if text.isEmpty, let words = p["words"] as? [[String: Any]] {
                text = words.map { w in
                    (w["text"] as? String ?? "") + (w["punctuation"] as? String ?? "")
                }.joined()
            }
            guard !text.isEmpty else { return nil }
            
            // Speaker - check all possible key formats (API returns "speakerId" camelCase)
            let speaker: String
            if let sid = p["speakerId"] as? String { speaker = "发言人 \(sid)" }
            else if let sid = p["speakerId"] as? Int { speaker = "发言人 \(sid)" }
            else if let sid = p["speaker_id"] as? String { speaker = "发言人 \(sid)" }
            else if let sid = p["speaker_id"] as? Int { speaker = "发言人 \(sid)" }
            else if let spk = p["speaker"] as? String { speaker = spk }
            else { speaker = "发言人" }
            
            // Timestamp
            var beginMs = p["beginTime"] as? Int ?? p["begin_time"] as? Int ?? 0
            if beginMs == 0, let d = p["beginTime"] as? Double ?? p["begin_time"] as? Double {
                beginMs = Int(d)
            }
            if beginMs == 0, let words = p["words"] as? [[String: Any]], let first = words.first {
                beginMs = first["beginTime"] as? Int ?? first["begin_time"] as? Int ?? 0
                if beginMs == 0, let d = first["beginTime"] as? Double ?? first["begin_time"] as? Double {
                    beginMs = Int(d)
                }
            }
            let totalSec = beginMs / 1000
            let ts = String(format: "%02d:%02d", totalSec / 60, totalSec % 60)
            
            return TingWuParagraph(speakerLabel: speaker, timestamp: ts, text: text, beginTimeMs: beginMs)
        }
        
        print("[TingWuDetail] Parsed \(paragraphs.count) conversation paragraphs")
    }
    
    // MARK: - TextPolish → pair with original paragraphs
    
    private func applyPolishedText(from json: [String: Any]) {
        var paras: [[String: Any]]? = nil
        
        // Try different paths to find polished paragraphs
        if let tp = json["textPolish"] as? [String: Any],
           let p = tp["paragraphs"] as? [[String: Any]] {
            paras = p
        } else if let trans = json["transcription"] as? [String: Any],
                  let p = trans["paragraphs"] as? [[String: Any]] {
            paras = p
        } else if let p = json["paragraphs"] as? [[String: Any]] {
            paras = p
        }
        
        guard let polishedDicts = paras else {
            print("[TingWuDetail] textPolish: no paragraphs found, keys=\(json.keys.sorted())")
            return
        }
        
        // Extract text from polished paragraphs
        let polishedTexts: [String] = polishedDicts.compactMap { p -> String? in
            var text = p["text"] as? String ?? p["content"] as? String ?? ""
            if text.isEmpty, let words = p["words"] as? [[String: Any]] {
                text = words.map { w in
                    (w["text"] as? String ?? "") + (w["punctuation"] as? String ?? "")
                }.joined()
            }
            return text.isEmpty ? nil : text
        }
        
        // Pair by index: only set polishedText when it differs from original
        for i in 0..<min(paragraphs.count, polishedTexts.count) {
            if polishedTexts[i] != paragraphs[i].text {
                paragraphs[i].polishedText = polishedTexts[i]
            }
        }
        
        let matched = paragraphs.filter { !$0.polishedText.isEmpty }.count
        print("[TingWuDetail] textPolish: \(polishedTexts.count) polished paragraphs, \(matched) matched to originals")
    }
    
    // MARK: - MeetingAssistance Parser (关键词, 待办事项)
    
    private func extractMeetingAssistance(from json: [String: Any]) {
        let ma = json["meetingAssistance"] as? [String: Any] ?? json
        
        // Keywords — can be [String] or [{word/text/keyword: String}]
        if let kw = ma["keywords"] as? [String] { analysis.keywords = kw }
        else if let kw = json["keywords"] as? [String] { analysis.keywords = kw }
        else if let kwArr = (ma["keywords"] ?? json["keywords"]) as? [[String: Any]] {
            analysis.keywords = kwArr.compactMap {
                $0["word"] as? String ?? $0["text"] as? String ?? $0["keyword"] as? String
            }
        }
        
        // Action Items — API returns actions with "text" field
        if let actions = ma["actions"] as? [[String: Any]] {
            analysis.actionItems = actions.compactMap {
                $0["text"] as? String ?? $0["content"] as? String ?? $0["title"] as? String
            }
        } else if let actions = (ma["actionItems"] ?? json["actionItems"]) as? [[String: Any]] {
            analysis.actionItems = actions.compactMap {
                $0["text"] as? String ?? $0["content"] as? String
            }
        } else if let actions = (ma["actions"] ?? json["actions"]) as? [String] {
            analysis.actionItems = actions
        }
        
        print("[TingWuDetail] meetingAssistance: keywords=\(analysis.keywords.count), actions=\(analysis.actionItems.count)")
    }
    
    // MARK: - Summarization Parser (FIXED: correct API field names)
    //
    // Actual API returns:
    //   paragraphSummary: String (NOT "paragraphSummarization", NOT Array)
    //   conversationalSummary: Array of {speakerId, speakerName, summary}
    //   questionsAnsweringSummary: Array of {question, answer, ...}
    //   mindMapSummary: Array of {title, topic}
    
    private func extractSummarization(from json: [String: Any]) {
        // paragraphSummary → 全文概要 (String or Array)
        if let ps = json["paragraphSummary"] as? String, !ps.isEmpty {
            analysis.summary = ps
        } else if let ps = json["paragraphSummary"] as? [[String: Any]] {
            let text = ps.compactMap {
                $0["text"] as? String ?? $0["content"] as? String ?? $0["paragraph"] as? String
            }.joined(separator: "\n\n")
            if !text.isEmpty { analysis.summary = text }
        }
        // Fallback keys
        if analysis.summary.isEmpty, let s = json["summary"] as? String { analysis.summary = s }
        if analysis.summary.isEmpty, let s = json["abstract"] as? String { analysis.summary = s }
        if analysis.summary.isEmpty, let s = json["paragraph"] as? String { analysis.summary = s }
        
        // conversationalSummary → 发言总结
        if let cs = json["conversationalSummary"] as? [[String: Any]] {
            analysis.speakerSummaries = cs.compactMap { item -> (String, String)? in
                let name = item["speakerName"] as? String
                    ?? item["speakerId"].flatMap { "发言人 \($0)" }
                    ?? item["speaker"] as? String
                    ?? "发言人"
                let text = item["summary"] as? String
                    ?? item["text"] as? String
                    ?? item["content"] as? String
                    ?? ""
                guard !text.isEmpty else { return nil }
                return (name, text)
            }
        }
        
        // questionsAnsweringSummary → 要点回顾 (Q&A pairs)
        if let qa = json["questionsAnsweringSummary"] as? [[String: Any]] {
            analysis.questionsAnswers = qa.compactMap { item -> (String, String)? in
                let q = item["question"] as? String ?? ""
                let a = item["answer"] as? String ?? ""
                guard !q.isEmpty else { return nil }
                return (q, a)
            }
        }
        
        // mindMapSummary → 思维导图
        if let mm = json["mindMapSummary"] as? [[String: Any]] {
            analysis.mindMapNodes = mm.compactMap { parseMindMapNode($0) }
        }
        
        print("[TingWuDetail] summarization: summary=\(analysis.summary.count) chars, speakers=\(analysis.speakerSummaries.count), qa=\(analysis.questionsAnswers.count), mindMap=\(analysis.mindMapNodes.count)")
    }
    
    /// Recursively parse mind map node from JSON
    private func parseMindMapNode(_ dict: [String: Any]) -> TingWuMindMapNode? {
        let title = dict["title"] as? String ?? dict["name"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        
        var children: [TingWuMindMapNode] = []
        
        // "topic" can be an array of child nodes or a string (leaf content)
        if let topicArr = dict["topic"] as? [[String: Any]] {
            children = topicArr.compactMap { parseMindMapNode($0) }
        } else if let topicStr = dict["topic"] as? String, !topicStr.isEmpty {
            children = [TingWuMindMapNode(title: topicStr)]
        }
        
        // Also check "children" key
        if children.isEmpty, let childArr = dict["children"] as? [[String: Any]] {
            children = childArr.compactMap { parseMindMapNode($0) }
        }
        
        return TingWuMindMapNode(title: title, children: children)
    }
    
    // MARK: - AutoChapters Parser (章节速览)
    
    private func extractChapters(from json: [String: Any]) {
        let chaptersArr = json["autoChapters"] as? [[String: Any]]
            ?? json["chapters"] as? [[String: Any]]
            ?? json["topics"] as? [[String: Any]]
        
        if let chapters = chaptersArr {
            analysis.chapters = chapters.compactMap { c -> (String, String)? in
                let title = c["title"] as? String ?? c["name"] as? String ?? c["headline"] as? String
                guard let t = title else { return nil }
                let desc = c["summary"] as? String ?? c["description"] as? String ?? c["content"] as? String ?? ""
                return (t, desc)
            }
        }
        
        print("[TingWuDetail] autoChapters: \(analysis.chapters.count) chapters")
    }
    
    // MARK: - Generic Text Extractor (for customPrompt etc.)
    
    private func extractTextContent(from json: [String: Any]) -> String {
        if let text = json["text"] as? String, !text.isEmpty { return text }
        if let text = json["content"] as? String, !text.isEmpty { return text }
        if let text = json["result"] as? String, !text.isEmpty { return text }
        
        if let paras = json["paragraphs"] as? [[String: Any]] {
            let text = paras.compactMap { p -> String? in
                var t = p["text"] as? String ?? p["content"] as? String ?? ""
                if t.isEmpty, let words = p["words"] as? [[String: Any]] {
                    t = words.map { ($0["text"] as? String ?? "") + ($0["punctuation"] as? String ?? "") }.joined()
                }
                return t.isEmpty ? nil : t
            }.joined(separator: "\n\n")
            if !text.isEmpty { return text }
        }
        
        if let arr = json["results"] as? [String] { return arr.joined(separator: "\n\n") }
        
        return json.values.compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    
    // MARK: - Fallback: parse tingwuNotes as conversation
    
    private func parseNotesAsConversation() {
        let notes = meeting.tingwuNotes
        guard !notes.isEmpty else { return }
        
        let lines = notes.components(separatedBy: "\n\n")
        var results: [TingWuParagraph] = []
        
        for block in lines {
            let parts = block.components(separatedBy: "\n")
            if parts.count >= 2 {
                let header = parts[0]
                let text = parts.dropFirst().joined(separator: "\n")
                let headerParts = header.components(separatedBy: "  ")
                let speaker = headerParts.first ?? "发言人"
                let ts = headerParts.count > 1 ? headerParts[1] : ""
                results.append(TingWuParagraph(
                    speakerLabel: speaker, timestamp: ts, text: text, beginTimeMs: 0
                ))
            }
        }
        
        if !results.isEmpty { paragraphs = results }
    }
}

// MARK: - Conversation Bubble

private struct ConversationBubble: View {
    let paragraph: TingWuParagraph
    let showPolished: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: speaker + timestamp
            HStack(spacing: 8) {
                Circle()
                    .fill(speakerColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    )
                
                Text(paragraph.speakerLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if !paragraph.timestamp.isEmpty {
                    Text(paragraph.timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Original text
            Text(paragraph.text)
                .font(.body)
                .lineSpacing(4)
                .padding(.leading, 36)
                .textSelection(.enabled)
            
            // Polished text (shown when toggle is on and different from original)
            if showPolished && !paragraph.polishedText.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "pencil.line")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                        .padding(.top, 3)
                    Text(paragraph.polishedText)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(.indigo.opacity(0.8))
                        .textSelection(.enabled)
                }
                .padding(.leading, 36)
                .padding(.top, 4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.05)))
            }
        }
        .padding(.vertical, 4)
    }
    
    private var speakerColor: Color {
        let hash = paragraph.speakerLabel.hashValue
        let colors: [Color] = [.indigo, .orange, .teal, .pink, .cyan, .purple]
        return colors[abs(hash) % colors.count]
    }
}

// MARK: - Mind Map Node View (recursive tree)

private struct MindMapNodeView: View {
    let node: TingWuMindMapNode
    let depth: Int
    @State private var isExpanded = true
    
    private var nodeColor: Color {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .cyan, .purple]
        return colors[depth % colors.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Node title row
            HStack(spacing: 6) {
                if !node.children.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(nodeColor)
                        .frame(width: 14)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }
                } else {
                    Circle()
                        .fill(nodeColor)
                        .frame(width: 6, height: 6)
                        .padding(.horizontal, 4)
                }
                
                Text(node.title)
                    .font(depth == 0 ? .subheadline.bold() : .subheadline)
                    .foregroundStyle(depth == 0 ? .primary : .secondary)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(depth) * 20)
            .padding(.vertical, 3)
            
            // Children
            if isExpanded {
                ForEach(node.children) { child in
                    MindMapNodeView(node: child, depth: depth + 1)
                }
            }
        }
    }
}

// MARK: - Analysis Section Card

private struct AnalysisSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.indigo)
                    .font(.subheadline)
                Text(title)
                    .font(.headline)
            }
            
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}

// MARK: - Flow Layout (for keyword chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        computeLayout(proposal: proposal, subviews: subviews).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
    
    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
        
        return (CGSize(width: maxWidth, height: currentY + rowHeight), positions)
    }
}
