//
//  TingWuService.swift
//  Huiyijilu
//
//  通义听悟·会议智能纪要服务
//
//  基于阿里云 DashScope tingwu-meeting 模型，实现离线转写 + 会议纪要生成。
//
//  Flow:
//    1. 上传录音文件到公共 OSS（复用 OSSUploadService）
//    2. 调用 TingWu createTask 接口创建离线转写任务
//    3. 轮询 getTask 直到 output 包含 meetingAssistancePath / transcriptionPath 等结果 URL
//    4. HTTP GET 下载结果 URL 内容
//    5. 解析并展示会议纪要
//
//  API Endpoint : POST https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
//  Header       : X-DashScope-WorkSpace: {workspaceId}
//  Model        : tingwu-meeting
//
//  getTask completed output keys:
//    autoChaptersPath, customPromptPath, meetingAssistancePath,
//    playbackUrl, pptExtractionPath, status, summarizationPath,
//    textPolishPath, transcriptionPath
//
//  Console log filter: [TingWu]
//

import Foundation
import Combine

// MARK: - TingWu Result

struct TingWuResult {
    let dataId: String
    let meetingNotes: String          // Formatted display text
    let transcription: String         // Formatted transcription text
    let rawJSON: String               // Original poll response
    /// All downloaded results keyed by type:
    /// "transcription", "meetingAssistance", "summarization",
    /// "autoChapters", "textPolish", "customPrompt", "pptExtraction"
    let rawResults: [String: String]
}

// MARK: - TingWu Service

class TingWuService: ObservableObject {
    @Published var isProcessing = false
    @Published var statusText   = ""
    @Published var lastError    = ""

    // MARK: - Config (from UserDefaults, configured in Settings)
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    }
    private var tingwuAppId: String {
        UserDefaults.standard.string(forKey: "tingwu_app_id") ?? ""
    }
    private var tingwuWorkspaceId: String {
        UserDefaults.standard.string(forKey: "tingwu_workspace_id") ?? ""
    }

    private let baseURL = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    private let model   = "tingwu-meeting"

    var isConfigured: Bool {
        !apiKey.isEmpty && !tingwuAppId.isEmpty && !tingwuWorkspaceId.isEmpty
    }

    private func log(_ msg: String) { print("[TingWu] \(msg)") }

    // =========================================================================
    // MARK: - Public: Generate Smart Meeting Notes
    // =========================================================================

    /// 完整流程：上传音频 → 创建任务 → 轮询等待 → 下载结果 → 返回
    func generateSmartNotes(audioFileURL: URL) async throws -> TingWuResult {
        guard isConfigured else { throw TingWuError.notConfigured }

        await MainActor.run {
            isProcessing = true
            statusText = "准备上传音频文件..."
            lastError = ""
        }
        defer { Task { @MainActor in self.isProcessing = false } }

        // Step 1: Upload audio to public OSS
        let publicURL: String
        do {
            publicURL = try await OSSUploadService.shared.uploadAudio(localURL: audioFileURL)
            log("📤 Uploaded audio → \(publicURL)")
        } catch {
            log("❌ Upload failed: \(error)")
            await MainActor.run { self.lastError = "音频上传失败: \(error.localizedDescription)" }
            throw error
        }

        await MainActor.run { self.statusText = "正在创建听悟任务..." }

        // Step 2: Create offline transcription task
        let dataId = try await createOfflineTask(fileUrl: publicURL)
        log("✅ Task created, dataId: \(dataId)")

        await MainActor.run { self.statusText = "听悟处理中（语音识别 → 智能纪要）..." }

        // Step 3: Poll until result URLs appear
        let (output, rawJSON) = try await pollUntilDone(dataId: dataId)
        log("✅ Polling done, output has \(output.keys.count) keys")

        await MainActor.run { self.statusText = "正在下载纪要内容..." }

        // Step 4: Download content from result URLs
        let result = try await downloadResults(output: output, dataId: dataId, rawJSON: rawJSON)
        log("✅ Done! notes=\(result.meetingNotes.count) chars, transcript=\(result.transcription.count) chars")

        await MainActor.run { self.statusText = "完成" }
        return result
    }

    // =========================================================================
    // MARK: - Create Offline Task
    // =========================================================================

    /// Create offline transcription task.
    /// Note: Features (meetingAssistance, summarization, autoChapters, etc.) are
    /// configured in the TingWu app on Alibaba Cloud console (via appId),
    /// NOT via the API call. The input only accepts:
    /// [task, dataId, phraseId, appId, format, fileUrl, text, type, sampleRate]
    private func createOfflineTask(fileUrl: String) async throws -> String {
        let input: [String: Any] = [
            "task": "createTask",
            "type": "offline",
            "appId": tingwuAppId,
            "fileUrl": fileUrl,
            "phraseId": ""
        ]

        let body: [String: Any] = [
            "model": model,
            "input": input,
            "parameters": [String: Any]()
        ]

        let request = try buildRequest(body: body)
        
        // Debug: log the request body
        if let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let bodyStr = String(data: bodyData, encoding: .utf8) {
            log("→ createTask body:\n\(bodyStr)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw TingWuError.networkError("非 HTTP 响应")
        }

        let rawStr = String(data: data, encoding: .utf8) ?? "<binary>"
        log("← createTask HTTP \(httpResp.statusCode)")
        log("← body: \(rawStr.prefix(500))")

        guard httpResp.statusCode == 200 else {
            await MainActor.run { self.lastError = "HTTP \(httpResp.statusCode): \(rawStr)" }
            throw TingWuError.apiError(httpResp.statusCode, rawStr)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TingWuError.parseError("无法解析 createTask 响应: \(rawStr)")
        }

        // Check for error code in response
        if let code = json["code"] as? String, !code.isEmpty {
            let msg = json["message"] as? String ?? ""
            log("❌ code=\(code) msg=\(msg)")
            await MainActor.run { self.lastError = "[\(code)] \(msg)" }
            throw TingWuError.serverError(code, msg)
        }

        // Extract dataId from output
        guard let output = json["output"] as? [String: Any],
              let dataId = output["dataId"] as? String else {
            throw TingWuError.parseError("响应中缺少 output.dataId")
        }

        return dataId
    }

    // =========================================================================
    // MARK: - Poll Until Done
    // =========================================================================

    /// Polls getTask until result URLs appear in the output.
    /// TingWu returns keys like `meetingAssistancePath`, `transcriptionPath`, `summarizationPath`
    /// when the task is complete. We detect these instead of relying on `status` field.
    private func pollUntilDone(dataId: String) async throws -> ([String: Any], String) {
        let maxAttempts = 120
        let intervalNs: UInt64 = 5_000_000_000  // 5 seconds

        for attempt in 1...maxAttempts {
            log("🔄 Poll \(attempt)/\(maxAttempts) dataId=\(dataId)")

            let input: [String: Any] = [
                "dataId": dataId,
                "task": "getTask"
            ]
            let body: [String: Any] = [
                "model": model,
                "input": input
            ]

            let request = try buildRequest(body: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResp = response as? HTTPURLResponse else {
                throw TingWuError.networkError("非 HTTP 响应")
            }

            let rawStr = String(data: data, encoding: .utf8) ?? "<binary>"
            log("← HTTP \(httpResp.statusCode)")

            guard httpResp.statusCode == 200 else {
                if attempt == maxAttempts { throw TingWuError.apiError(httpResp.statusCode, rawStr) }
                try await Task.sleep(nanoseconds: intervalNs)
                continue
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TingWuError.parseError("无法解析 getTask 响应")
            }

            if let code = json["code"] as? String, !code.isEmpty {
                let msg = json["message"] as? String ?? ""
                throw TingWuError.serverError(code, msg)
            }

            guard let output = json["output"] as? [String: Any] else {
                log("⚠ No output. keys=\(json.keys.sorted())")
                throw TingWuError.parseError("响应缺少 output")
            }

            let keys = output.keys.sorted()
            log("📋 output keys: \(keys)")

            // Log raw status for debugging
            if let st = output["status"] { log("📋 status=\(st) type=\(type(of: st))") }

            // ── Completion detection ──
            // TingWu status codes (observed):
            //   status=1 → running (partial results, e.g. only transcriptionPath)
            //   status=0 → completed (all results ready)
            //   negative → failed
            let statusNum = output["status"] as? Int ?? -99
            let availablePaths = output.keys.filter { $0.hasSuffix("Path") }
                .filter { output[$0] as? String != nil && !(output[$0] as! String).isEmpty }
            
            // Completed: status=0, or status=2, or all key analysis paths are present
            let analysisKeys = ["meetingAssistancePath", "summarizationPath", "autoChaptersPath"]
            let hasAnalysis = analysisKeys.allSatisfy { availablePaths.contains($0) }
            
            if statusNum == 0 || statusNum == 2 || (hasAnalysis && availablePaths.count >= 5) {
                log("✅ Task completed (status=\(statusNum))! Available paths: \(availablePaths.sorted())")
                return (output, rawStr)
            }
            
            // ── Failure detection ──
            if statusNum < 0 {
                let msg = output["message"] as? String ?? "任务失败 (status=\(statusNum))"
                await MainActor.run { self.lastError = msg }
                throw TingWuError.taskFailed(msg)
            }
            
            let statusStr = "\(output["status"] ?? "nil")"
            if statusStr.uppercased().contains("FAIL") || statusStr.uppercased().contains("ERROR") {
                let msg = output["message"] as? String ?? "任务失败 (\(statusStr))"
                await MainActor.run { self.lastError = msg }
                throw TingWuError.taskFailed(msg)
            }

            // ── Still processing (status=1 etc.) ──
            if !availablePaths.isEmpty {
                log("⏳ status=\(statusNum), partial paths: \(availablePaths.sorted()), waiting for completion...")
            }

            // ── Still processing ──
            await MainActor.run {
                self.statusText = "听悟处理中（第 \(attempt) 次查询）..."
            }
            try await Task.sleep(nanoseconds: intervalNs)
        }

        throw TingWuError.timeout
    }

    // =========================================================================
    // MARK: - Download Results from URLs
    // =========================================================================

    /// Download content from the result URLs returned by getTask.
    private func downloadResults(output: [String: Any], dataId: String, rawJSON: String) async throws -> TingWuResult {
        // Map of output key → raw result storage key
        let pathMapping: [(outputKey: String, resultKey: String)] = [
            ("transcriptionPath",       "transcription"),
            ("meetingAssistancePath",   "meetingAssistance"),
            ("summarizationPath",       "summarization"),
            ("autoChaptersPath",        "autoChapters"),
            ("textPolishPath",          "textPolish"),
            ("customPromptPath",        "customPrompt"),
            ("pptExtractionPath",       "pptExtraction"),
        ]
        
        var rawResults: [String: String] = [:]
        
        // Download all available result URLs
        for mapping in pathMapping {
            if let url = output[mapping.outputKey] as? String, !url.isEmpty {
                log("📥 Downloading \(mapping.outputKey)...")
                if let content = await httpGet(url) {
                    log("📥 \(mapping.resultKey) \(content.count) chars")
                    rawResults[mapping.resultKey] = content
                    
                    // Debug: log structure for key results
                    if mapping.resultKey == "transcription" || mapping.resultKey == "meetingAssistance" || mapping.resultKey == "summarization" {
                        if let data = content.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            log("🔍 \(mapping.resultKey) top-level keys: \(json.keys.sorted())")
                            for (key, value) in json {
                                if let dict = value as? [String: Any] {
                                    log("🔍   \(key): [Dict] keys=\(dict.keys.sorted())")
                                } else if let arr = value as? [Any] {
                                    log("🔍   \(key): [Array] count=\(arr.count)")
                                    if let first = arr.first as? [String: Any] {
                                        log("🔍     first item keys: \(first.keys.sorted())")
                                    }
                                } else {
                                    log("🔍   \(key): \(type(of: value)) = \(String(describing: value).prefix(100))")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        log("📥 Downloaded \(rawResults.count) result files: \(rawResults.keys.sorted())")
        
        // Build formatted transcription text
        var transcription = ""
        if let raw = rawResults["transcription"] {
            transcription = tryParseTranscriptionJSON(raw)
        }
        
        // Build formatted meeting notes from all analysis results
        var meetingNotes = ""
        
        // Priority 1: meetingAssistance
        if let raw = rawResults["meetingAssistance"] {
            meetingNotes = tryParseMeetingJSON(raw)
        }
        
        // Priority 2: summarization (append or use as primary)
        if let raw = rawResults["summarization"] {
            let parsed = tryParseMeetingJSON(raw)
            if meetingNotes.isEmpty {
                meetingNotes = parsed
            } else if !parsed.isEmpty {
                meetingNotes += "\n\n---\n\n" + parsed
            }
        }
        
        // Append textPolish if available
        if let raw = rawResults["textPolish"] {
            let parsed = tryParseMeetingJSON(raw)
            if !parsed.isEmpty {
                let polishSection = "## 口语书面化\n\(parsed)"
                meetingNotes = meetingNotes.isEmpty ? polishSection : meetingNotes + "\n\n" + polishSection
            }
        }
        
        // Append customPrompt if available
        if let raw = rawResults["customPrompt"] {
            let parsed = tryParseMeetingJSON(raw)
            if !parsed.isEmpty {
                let promptSection = "## 自定义分析\n\(parsed)"
                meetingNotes = meetingNotes.isEmpty ? promptSection : meetingNotes + "\n\n" + promptSection
            }
        }
        
        // Fallback: use transcription as notes
        if meetingNotes.isEmpty && !transcription.isEmpty {
            meetingNotes = transcription
        }

        // Fallback: list all available URL keys
        if meetingNotes.isEmpty {
            var summary = "## 听悟任务完成\n\n以下结果可用：\n\n"
            for key in output.keys.sorted() where key.hasSuffix("Path") || key.hasSuffix("Url") {
                if let v = output[key] as? String, !v.isEmpty {
                    summary += "- **\(key)**\n"
                }
            }
            meetingNotes = summary
        }

        return TingWuResult(
            dataId: dataId,
            meetingNotes: meetingNotes,
            transcription: transcription,
            rawJSON: rawJSON,
            rawResults: rawResults
        )
    }

    /// Simple HTTP GET that returns text content.
    private func httpGet(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else {
            log("⚠ bad URL: \(urlString.prefix(80))")
            return nil
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            log("📥 GET \(code) \(data.count) bytes")
            guard code == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            log("⚠ GET error: \(error.localizedDescription)")
            return nil
        }
    }

    // =========================================================================
    // MARK: - JSON Parsing Helpers
    // =========================================================================
    
    /// Convert milliseconds to timestamp string like "00:05"
    private func msToTimestamp(_ ms: Any?) -> String {
        guard let msValue = ms as? Int ?? (ms as? Double).map({ Int($0) }) else { return "" }
        let totalSeconds = msValue / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Extract speaker label from a paragraph dict
    private func speakerLabel(from p: [String: Any]) -> String {
        if let sid = p["speaker_id"] as? String { return "发言人 \(sid)" }
        if let sid = p["speaker_id"] as? Int { return "发言人 \(sid)" }
        if let sid = p["speakerId"] as? String { return "发言人 \(sid)" }
        if let sid = p["speakerId"] as? Int { return "发言人 \(sid)" }
        if let spk = p["speaker"] as? String { return spk }
        return "发言人"
    }
    
    /// Reconstruct text from a words array: [{ "text": "...", "punctuation": "," }]
    private func joinWords(_ words: [[String: Any]]) -> String {
        return words.map { w in
            let text = w["text"] as? String ?? ""
            let punct = w["punctuation"] as? String ?? ""
            return text + punct
        }.joined()
    }

    /// If the raw string is JSON, try to extract readable transcription text.
    private func tryParseTranscriptionJSON(_ raw: String) -> String {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }
        
        log("🔍 tryParseTranscriptionJSON: top-level keys = \(json.keys.sorted())")
        
        // 1. Try: { "transcription": { "paragraphs": [...] } }
        if let trans = json["transcription"] as? [String: Any] {
            log("🔍 Found transcription dict with keys: \(trans.keys.sorted())")
            if let paragraphs = trans["paragraphs"] as? [[String: Any]] {
                log("🔍 Found transcription.paragraphs with \(paragraphs.count) items")
                if let first = paragraphs.first {
                    log("🔍   First paragraph keys: \(first.keys.sorted())")
                    if let words = first["words"] as? [Any] {
                        log("🔍   First paragraph has \(words.count) words")
                    }
                    log("🔍   Has text field: \(first["text"] != nil)")
                }
                let result = parseParagraphs(paragraphs)
                log("🔍 parseParagraphs result: \(result.count) chars")
                if !result.isEmpty { return result }
            }
        }
        
        // 2. Try: { "body": { "transcription": { "paragraphs": [...] } } }
        if let body = json["body"] as? [String: Any] {
            log("🔍 Found body dict with keys: \(body.keys.sorted())")
            if let trans = body["transcription"] as? [String: Any],
               let paragraphs = trans["paragraphs"] as? [[String: Any]] {
                log("🔍 Found body.transcription.paragraphs with \(paragraphs.count) items")
                let result = parseParagraphs(paragraphs)
                if !result.isEmpty { return result }
            }
        }
        
        // 3. Try: { "paragraphs": [...] } at top level
        if let paragraphs = json["paragraphs"] as? [[String: Any]] {
            log("🔍 Found top-level paragraphs with \(paragraphs.count) items")
            let result = parseParagraphs(paragraphs)
            if !result.isEmpty { return result }
        }
        
        // 4. Try: { "body": [{ "text": "...", "speaker_id": 0 }] } (array-style body)
        if let body = json["body"] as? [[String: Any]] {
            log("🔍 Found body array with \(body.count) items")
            let result = body.compactMap { item -> String? in
                let txt = item["text"] as? String ?? item["content"] as? String ?? ""
                guard !txt.isEmpty else { return nil }
                let spk = speakerLabel(from: item)
                let ts = msToTimestamp(item["begin_time"] ?? item["beginTime"])
                let header = ts.isEmpty ? spk : "\(spk)  \(ts)"
                return "\(header)\n\(txt)"
            }.joined(separator: "\n\n")
            if !result.isEmpty { return result }
        }
        
        // 5. Try: { "sentences": [...] } or { "items": [...] }
        for arrayKey in ["sentences", "items", "results", "segments"] {
            if let items = json[arrayKey] as? [[String: Any]] {
                log("🔍 Found \(arrayKey) array with \(items.count) items")
                let result = items.compactMap { item -> String? in
                    item["text"] as? String ?? item["content"] as? String
                }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                if !result.isEmpty { return result }
            }
        }
        
        // 6. Try: direct text field
        if let text = json["text"] as? String, !text.isEmpty { return text }
        if let text = json["content"] as? String, !text.isEmpty { return text }
        
        // 7. Fallback: pretty-print the JSON for display
        log("⚠ No known transcription format matched. Using fallback display.")
        let fallback = formatJSONForDisplay(json)
        return fallback.isEmpty ? String(raw.prefix(5000)) : fallback
    }
    
    /// Parse paragraphs array - handles both text-field and words-array formats
    private func parseParagraphs(_ paragraphs: [[String: Any]]) -> String {
        return paragraphs.compactMap { p -> String? in
            // Try to get full text from paragraph-level field
            var txt = p["text"] as? String ?? p["content"] as? String ?? ""
            
            // If no text field, reconstruct from words array
            if txt.isEmpty, let words = p["words"] as? [[String: Any]] {
                txt = joinWords(words)
            }
            
            guard !txt.isEmpty else { return nil }
            
            let spk = speakerLabel(from: p)
            let ts = msToTimestamp(p["begin_time"] ?? p["beginTime"])
            let header = ts.isEmpty ? spk : "\(spk)  \(ts)"
            return "\(header)\n\(txt)"
        }.joined(separator: "\n\n")
    }

    /// If the raw string is JSON, try to convert to Markdown meeting notes.
    private func tryParseMeetingJSON(_ raw: String) -> String {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }
        
        log("🔍 tryParseMeetingJSON: top-level keys = \(json.keys.sorted())")
        
        var parts: [String] = []
        
        // Try to find meetingAssistance structure
        if let ma = json["meetingAssistance"] as? [String: Any] {
            log("🔍 Found meetingAssistance dict with keys: \(ma.keys.sorted())")
            if let summary = ma["summary"] as? String { parts.append("## 全文概要\n\(summary)") }
            if let kp = ma["keyPoints"] as? [String] {
                parts.append("## 要点回顾\n" + kp.map { "- \($0)" }.joined(separator: "\n"))
            }
            if let actions = ma["actions"] as? [[String: Any]] {
                let lines = actions.compactMap { a -> String? in
                    guard let t = a["content"] as? String ?? a["title"] as? String else { return nil }
                    return "- [ ] \(t)"
                }.joined(separator: "\n")
                if !lines.isEmpty { parts.append("## 待办事项\n\(lines)") }
            }
            if let keywords = ma["keywords"] as? [String] {
                parts.append("## 关键词\n\(keywords.joined(separator: "、"))")
            }
        }
        
        // Also check top-level fields
        if let t = json["title"] as? String ?? json["meeting_title"] as? String {
            parts.insert("# \(t)", at: 0)
        }
        if let s = json["summary"] as? String, !parts.contains(where: { $0.contains("全文概要") }) {
            parts.append("## 全文概要\n\(s)")
        }
        if let s = json["abstract"] as? String, !parts.contains(where: { $0.contains("全文概要") }) {
            parts.append("## 全文概要\n\(s)")
        }
        if let kp = json["keyPoints"] as? [String] ?? json["key_points"] as? [String],
           !parts.contains(where: { $0.contains("要点") }) {
            parts.append("## 要点回顾\n" + kp.map { "- \($0)" }.joined(separator: "\n"))
        }
        
        // Topics / Chapters
        if let topics = json["topics"] as? [[String: Any]] ?? json["chapters"] as? [[String: Any]] {
            let topicText = topics.compactMap { t -> String? in
                guard let title = t["title"] as? String ?? t["name"] as? String else { return nil }
                if let desc = t["summary"] as? String ?? t["description"] as? String {
                    return "### \(title)\n\(desc)"
                }
                return "### \(title)"
            }.joined(separator: "\n\n")
            if !topicText.isEmpty { parts.append("## 章节速览\n\(topicText)") }
        }
        
        // Action Items
        if let items = json["actionItems"] as? [[String: Any]] ?? json["action_items"] as? [[String: Any]],
           !parts.contains(where: { $0.contains("待办") }) {
            let lines = items.compactMap { i -> String? in
                guard let t = i["title"] as? String ?? i["content"] as? String else { return nil }
                let a = i["assignee"] as? String ?? i["owner"] as? String ?? ""
                return a.isEmpty ? "- [ ] \(t)" : "- [ ] \(t) (@\(a))"
            }.joined(separator: "\n")
            if !lines.isEmpty { parts.append("## 待办事项\n\(lines)") }
        }
        
        if !parts.isEmpty { return parts.joined(separator: "\n\n") }
        if let text = json["text"] as? String { return text }
        if let text = json["content"] as? String { return text }
        
        // Fallback: pretty-print
        let fallback = formatJSONForDisplay(json)
        return fallback.isEmpty ? String(raw.prefix(5000)) : fallback
    }
    
    /// Pretty-print a JSON object for display when structure is unknown
    private func formatJSONForDisplay(_ json: [String: Any]) -> String {
        var result: [String] = []
        
        for (key, value) in json.sorted(by: { $0.key < $1.key }) {
            if let str = value as? String, !str.isEmpty {
                let preview = str.count > 500 ? String(str.prefix(500)) + "..." : str
                result.append("**\(key)**: \(preview)")
            } else if let num = value as? NSNumber {
                result.append("**\(key)**: \(num)")
            } else if let arr = value as? [Any] {
                if let stringArr = arr as? [String] {
                    result.append("**\(key)**: \(stringArr.joined(separator: ", "))")
                } else {
                    result.append("**\(key)**: [\(arr.count) items]")
                }
            } else if let dict = value as? [String: Any] {
                result.append("**\(key)**: {keys: \(dict.keys.sorted().joined(separator: ", "))}")
            }
        }
        
        return result.isEmpty ? "" : result.joined(separator: "\n\n")
    }

    // =========================================================================
    // MARK: - Build HTTP Request
    // =========================================================================

    private func buildRequest(body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: baseURL) else { throw TingWuError.invalidURL }
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)",   forHTTPHeaderField: "Authorization")
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.setValue(tingwuWorkspaceId,      forHTTPHeaderField: "X-DashScope-WorkSpace")
        req.timeoutInterval = 60
        req.httpBody = bodyData

        log("→ POST \(baseURL)")
        log("→ workspace: \(tingwuWorkspaceId)")
        return req
    }
}

// MARK: - Errors

enum TingWuError: LocalizedError {
    case notConfigured
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case serverError(String, String)
    case parseError(String)
    case taskFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured:             return "请在设置中配置听悟 App ID 和 Workspace ID"
        case .invalidURL:                return "URL 配置有误"
        case .networkError(let m):       return "网络错误: \(m)"
        case .apiError(let c, let b):    return "HTTP \(c): \(b)"
        case .serverError(let c, let m): return "服务错误 [\(c)]: \(m)"
        case .parseError(let m):         return "解析失败: \(m)"
        case .taskFailed(let m):         return "任务失败: \(m)"
        case .timeout:                   return "任务超时（已等待 10 分钟），请稍后重试"
        }
    }
}
