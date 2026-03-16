//
//  BailianWorkflowService.swift
//  Huiyijilu
//
//  Calls the Bailian "会议图文纪要" workflow application.
//
//  Flow:
//    1. Upload audio → public OSS (ideasnap bucket) via OSSUploadService
//    2. Call workflow with HTTPS URL in input.file_list
//    3. Workflow: Paraformer ASR → LLM summary → HTML generation → EdgeOne deploy
//
//  Endpoint : POST https://dashscope.aliyuncs.com/api/v1/apps/{appId}/completion
//  Streaming: X-DashScope-SSE: enable   + flow_stream_mode: "agent_format"
//
//  Console log filter: [Bailian]
//

import Foundation
import Combine

class BailianWorkflowService: ObservableObject {
    @Published var isRunning = false
    @Published var streamingText = ""
    @Published var lastError: String = ""

    // MARK: - Config
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    }
    private var appId: String {
        UserDefaults.standard.string(forKey: "bailian_workflow_app_id") ?? ""
    }
    private let baseURL = "https://dashscope.aliyuncs.com"

    var isConfigured: Bool { !apiKey.isEmpty && !appId.isEmpty }

    private func log(_ msg: String) { print("[Bailian] \(msg)") }

    // =========================================================================
    // MARK: - Build workflow request
    // =========================================================================

    /// Build the HTTP request.
    /// For workflow apps with a File-type Start-node parameter, pass the file
    /// via `biz_params.file` (a structured File object), NOT via `file_list`.
    private func buildRequest(prompt: String, fileURL: String? = nil, fileName: String? = nil, fileMimeType: String? = nil, stream: Bool) throws -> URLRequest {
        let urlStr = "\(baseURL)/api/v1/apps/\(appId)/completion"
        guard let url = URL(string: urlStr) else { throw WorkflowError.invalidURL }

        var inputDict: [String: Any] = ["prompt": prompt]

        // Pass file as a structured File object through biz_params
        // This maps to the workflow Start node's `file` outputParam (type: File)
        if let fileURL = fileURL, !fileURL.isEmpty {
            let fileObj: [String: Any] = [
                "type": "audio",
                "name": fileName ?? "audio.m4a",
                "mimeType": fileMimeType ?? "audio/mp4",
                "source": "url",
                "url": fileURL
            ]
            inputDict["biz_params"] = ["file": fileObj]
        }

        var params: [String: Any] = [:]
        if stream {
            params["incremental_output"] = true
            params["flow_stream_mode"] = "agent_format"
        }

        let body: [String: Any] = ["input": inputDict, "parameters": params]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        if stream { req.setValue("enable", forHTTPHeaderField: "X-DashScope-SSE") }
        req.timeoutInterval = 300
        req.httpBody = bodyData

        log("→ \(urlStr) stream=\(stream)")
        log("→ body: \(String(data: bodyData, encoding: .utf8).map { String($0.prefix(500)) } ?? "")")
        return req
    }

    // =========================================================================
    // MARK: - Generate rich notes (upload audio → call workflow)
    // =========================================================================

    /// Upload audio to public OSS, then invoke the workflow with the HTTPS URL.
    func generateRichNotes(audioFileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw WorkflowError.noAPIKey }
        guard !appId.isEmpty  else { throw WorkflowError.noAppId  }

        await MainActor.run { isRunning = true; streamingText = ""; lastError = "" }
        defer { Task { @MainActor in self.isRunning = false } }

        // Step 1: Upload audio to public OSS (ideasnap bucket)
        await MainActor.run { self.streamingText = "正在上传音频文件..." }
        let publicURL = try await OSSUploadService.shared.uploadAudio(localURL: audioFileURL)
        log("📤 Public audio URL: \(publicURL)")

        // Step 2: Call workflow — pass public URL via biz_params.file (File type)
        await MainActor.run { self.streamingText = "工作流处理中（语音识别 → AI 分析 → 生成纪要）..." }
        let fileName = audioFileURL.lastPathComponent
        let mimeType = fileName.hasSuffix(".m4a") ? "audio/mp4" : "audio/mpeg"
        let req = try buildRequest(prompt: "请根据音频生成会议纪要", fileURL: publicURL, fileName: fileName, fileMimeType: mimeType, stream: true)
        let (asyncBytes, rawResp) = try await URLSession.shared.bytes(for: req)

        guard let httpResp = rawResp as? HTTPURLResponse else {
            throw WorkflowError.networkError("Non-HTTP response")
        }
        log("← HTTP \(httpResp.statusCode)")

        if httpResp.statusCode != 200 {
            var body = ""
            for try await byte in asyncBytes { body.append(Character(UnicodeScalar(byte))) }
            log("← Error body: \(body)")
            await MainActor.run { self.lastError = "HTTP \(httpResp.statusCode): \(body)" }
            throw WorkflowError.apiError(httpResp.statusCode, body)
        }

        // Step 3: Parse SSE stream
        var fullText = ""

        for try await line in asyncBytes.lines {
            log("← SSE: \(line)")
            guard line.hasPrefix("data:") else { continue }

            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard jsonStr != "[DONE]", !jsonStr.isEmpty else { log("SSE [DONE]"); break }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { log("⚠ Cannot parse: \(jsonStr.prefix(80))"); continue }

            if let code = json["code"] as? String, !code.isEmpty {
                let msg = json["message"] as? String ?? ""
                log("❌ code=\(code) msg=\(msg)")
                await MainActor.run { self.lastError = "[\(code)] \(msg)" }
                throw WorkflowError.serverError(code, msg)
            }

            guard let output = json["output"] as? [String: Any] else {
                log("⚠ No 'output'. Keys: \(json.keys.sorted())")
                continue
            }

            let chunk = output["text"] as? String ?? ""
            fullText += chunk
            let snap = fullText
            await MainActor.run { self.streamingText = snap }

            if let finish = output["finish_reason"] as? String, finish == "stop" {
                log("✔ finish=stop  total=\(fullText.count) chars")
                break
            }
        }

        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WorkflowError.emptyResponse
        }
        return fullText
    }

    // =========================================================================
    // MARK: - Non-streaming fallback
    // =========================================================================

    func generateRichNotesNonStreaming(audioFileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw WorkflowError.noAPIKey }
        guard !appId.isEmpty  else { throw WorkflowError.noAppId  }

        await MainActor.run { isRunning = true; lastError = "" }
        defer { Task { @MainActor in self.isRunning = false } }

        let publicURL = try await OSSUploadService.shared.uploadAudio(localURL: audioFileURL)
        let fileName = audioFileURL.lastPathComponent
        let mimeType = fileName.hasSuffix(".m4a") ? "audio/mp4" : "audio/mpeg"
        let req = try buildRequest(prompt: "请根据音频生成会议纪要", fileURL: publicURL, fileName: fileName, fileMimeType: mimeType, stream: false)
        let (data, response) = try await URLSession.shared.data(for: req)
        let rawStr = String(data: data, encoding: .utf8) ?? "<binary>"

        guard let httpResp = response as? HTTPURLResponse else {
            throw WorkflowError.networkError("Non-HTTP response")
        }
        log("← HTTP \(httpResp.statusCode)")
        log("← body: \(rawStr)")

        guard httpResp.statusCode == 200 else {
            await MainActor.run { self.lastError = "HTTP \(httpResp.statusCode): \(rawStr)" }
            throw WorkflowError.apiError(httpResp.statusCode, rawStr)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkflowError.parseError("Invalid JSON: \(rawStr)")
        }

        if let code = json["code"] as? String, !code.isEmpty {
            let msg = json["message"] as? String ?? ""
            log("❌ code=\(code) msg=\(msg)")
            await MainActor.run { self.lastError = "[\(code)] \(msg)" }
            throw WorkflowError.serverError(code, msg)
        }

        guard let output = json["output"] as? [String: Any],
              let text   = output["text"]   as? String else {
            throw WorkflowError.parseError("Missing output.text. Full: \(rawStr)")
        }
        return text
    }
}


// MARK: - Errors
enum WorkflowError: LocalizedError {
    case noAPIKey
    case noAppId
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case serverError(String, String)
    case parseError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:                  return "请在设置中填写 API Key"
        case .noAppId:                   return "请在设置中填写百炼工作流 App ID"
        case .invalidURL:                return "URL 配置有误"
        case .networkError(let m):       return "网络错误: \(m)"
        case .apiError(let c, let b):    return "HTTP \(c): \(b)"
        case .serverError(let c, let m): return "服务错误 [\(c)]: \(m)"
        case .parseError(let m):         return "解析失败: \(m)"
        case .emptyResponse:             return "工作流返回内容为空，请检查输入字段名是否与工作流 Start 节点匹配"
        }
    }
}
