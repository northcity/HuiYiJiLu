//
//  AIService.swift
//  Huiyijilu
//

import Foundation
import Combine

/// AI service for generating meeting summaries using OpenAI API
class AIService: ObservableObject {
    @Published var isProcessing = false

    // MARK: - Configuration
    // Users should set their API key in Settings
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    }

    private var apiBaseURL: String {
        UserDefaults.standard.string(forKey: "api_base_url") ?? "https://dashscope.aliyuncs.com/compatible-mode/v1"
    }

    private var modelName: String {
        UserDefaults.standard.string(forKey: "ai_model") ?? "qwen-plus"
    }

    struct MeetingSummaryResult {
        let title: String
        let summary: String
        let keyPoints: [String]
        let actionItems: [ActionItemResult]
    }

    struct ActionItemResult {
        let title: String
        let assignee: String
    }

    /// Generate meeting summary from transcript
    func generateSummary(transcript: String) async throws -> MeetingSummaryResult {
        guard !apiKey.isEmpty else {
            throw AIServiceError.noAPIKey
        }

        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in self.isProcessing = false } }

        let systemPrompt = """
        You are a professional meeting assistant. Analyze the meeting transcript and generate a structured summary.
        You MUST respond in the SAME LANGUAGE as the transcript.
        
        Respond in this exact JSON format:
        {
            "title": "A concise meeting title (max 20 chars)",
            "summary": "2-3 sentence meeting summary",
            "keyPoints": ["key point 1", "key point 2", ...],
            "actionItems": [
                {"title": "task description", "assignee": "person name or empty string"},
                ...
            ]
        }
        
        Rules:
        - Title should capture the meeting theme
        - Summary should be concise but informative
        - Extract 3-6 key discussion points
        - Extract all action items with assignees when mentioned
        - If no clear assignee, leave assignee as empty string
        - Respond ONLY with valid JSON, no other text
        """

        let userPrompt = "Please analyze this meeting transcript and generate a structured summary:\n\n\(transcript)"

        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]

        guard let url = URL(string: "\(apiBaseURL)/chat/completions") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(httpResponse.statusCode, errorBody)
        }

        // Parse OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.parseError("Cannot parse API response")
        }

        return try parseSummaryJSON(content)
    }

    private func parseSummaryJSON(_ jsonString: String) throws -> MeetingSummaryResult {
        // Clean up potential markdown code blocks
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parseError("Invalid JSON in AI response")
        }

        let title = json["title"] as? String ?? "Meeting"
        let summary = json["summary"] as? String ?? ""
        let keyPoints = json["keyPoints"] as? [String] ?? []

        var actionItems: [ActionItemResult] = []
        if let items = json["actionItems"] as? [[String: Any]] {
            for item in items {
                let itemTitle = item["title"] as? String ?? ""
                let assignee = item["assignee"] as? String ?? ""
                if !itemTitle.isEmpty {
                    actionItems.append(ActionItemResult(title: itemTitle, assignee: assignee))
                }
            }
        }

        return MeetingSummaryResult(
            title: title,
            summary: summary,
            keyPoints: keyPoints,
            actionItems: actionItems
        )
    }

    // MARK: - Rich Notes (Markdown)

    /// Generate richly formatted Markdown meeting notes from transcript.
    /// Used as fallback when Bailian workflow is unavailable or fails.
    func generateRichNotes(transcript: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.noAPIKey }

        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in self.isProcessing = false } }

        let systemPrompt = """
        你是专业的会议记录助手。请将以下会议转写文本整理成结构化的 Markdown 格式会议纪要。

        输出格式要求（严格遵守）：

        # 会议标题（AI 自动生成）

        ## 📌 会议概要
        2-3 句概括会议核心内容。

        ## 💬 关键讨论
        - 讨论点 1
        - 讨论点 2

        ## ✅ 行动项
        - **[责任人]** 任务描述——优先级：高/中/低
        - **[待确认]** 任务描述——优先级：高/中/低

        ## 💡 关键决策
        - 决策 1
        - 决策 2

        ## 🗒️ 下次会议建议
        （如有则填写，没有则省略此节）

        规则：
        - 必须使用与转写文本相同的语言回复
        - 不要使用 Markdown 表格，只用标题和列表
        - 行动项如无明确责任人，责任人写「待确认」
        - 使用 **加粗** 突出关键词
        - 只输出 Markdown 内容，不要加前后说明
        """

        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": "请将以下会议转写整理成会议纪要：\n\n\(transcript)"]
            ],
            "temperature": 0.4,
            "max_tokens": 3000
        ]

        guard let url = URL(string: "\(apiBaseURL)/chat/completions") else {
            throw AIServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",       forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)",       forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.apiError(code, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw AIServiceError.parseError("Cannot parse response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AIServiceError: LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Please set your OpenAI API Key in Settings"
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        }
    }
}
