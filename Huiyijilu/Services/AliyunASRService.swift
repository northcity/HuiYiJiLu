//
//  AliyunASRService.swift
//  Huiyijilu
//
//  阿里云 DashScope 语音转文字服务 — 基于 Paraformer/Fun-ASR 录音文件识别 RESTful API
//
//  流程：
//    1. 上传音频到 OSS → 获取公网 URL
//    2. POST 提交转写任务 (X-DashScope-Async: enable)
//    3. 轮询 GET 查询任务状态直到 SUCCEEDED/FAILED
//    4. 从 transcription_url 下载 JSON 结果
//    5. 解析为 ASRResult
//
//  支持模型: paraformer-v2 (默认/最便宜), fun-asr (预留)
//  API Doc: docs/Paraformer录音文件识别RESTful API.md
//

import Foundation
import Combine

// MARK: - ASR Result Models

struct ASRResult {
    let text: String                        // 全文拼接
    let segments: [ASRSegment]              // 句子级结果
    let properties: ASRProperties           // 音频属性
    let rawJSON: String                     // 原始 JSON 字符串
}

struct ASRSegment: Codable {
    let beginTime: Int                      // 毫秒
    let endTime: Int                        // 毫秒
    let text: String
    let sentenceId: Int
    let speakerId: Int?                     // 说话人分离时才有
    let words: [ASRWord]?

    enum CodingKeys: String, CodingKey {
        case beginTime = "begin_time"
        case endTime = "end_time"
        case text
        case sentenceId = "sentence_id"
        case speakerId = "speaker_id"
        case words
    }
}

struct ASRWord: Codable {
    let beginTime: Int
    let endTime: Int
    let text: String
    let punctuation: String

    enum CodingKeys: String, CodingKey {
        case beginTime = "begin_time"
        case endTime = "end_time"
        case text, punctuation
    }
}

struct ASRProperties: Codable {
    let audioFormat: String
    let channels: [Int]
    let originalSamplingRate: Int
    let originalDurationInMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case audioFormat = "audio_format"
        case channels
        case originalSamplingRate = "original_sampling_rate"
        case originalDurationInMilliseconds = "original_duration_in_milliseconds"
    }
}

// MARK: - ASR Task Status

enum ASRTaskStatus: String {
    case pending = "PENDING"
    case running = "RUNNING"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case unknown
}

// MARK: - ASR Error

enum ASRError: LocalizedError {
    case noAPIKey
    case ossUploadFailed(String)
    case submitFailed(Int, String)
    case taskFailed(String)
    case downloadFailed(String)
    case parseFailed(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey:                 return "未配置 DashScope API Key"
        case .ossUploadFailed(let m):   return "OSS 上传失败: \(m)"
        case .submitFailed(let c, let m): return "提交任务失败 (HTTP \(c)): \(m)"
        case .taskFailed(let m):        return "转写任务失败: \(m)"
        case .downloadFailed(let m):    return "下载结果失败: \(m)"
        case .parseFailed(let m):       return "解析结果失败: \(m)"
        case .timeout:                  return "转写任务超时"
        case .cancelled:                return "任务已取消"
        }
    }
}

// MARK: - AliyunASRService

@MainActor
class AliyunASRService: ObservableObject {
    @Published var isTranscribing = false
    @Published var statusText = ""
    @Published var progress: Double = 0     // 0.0 ~ 1.0

    /// 支持的 ASR 模型
    enum ASRModel: String, CaseIterable {
        case paraformerV2 = "paraformer-v2"     // 0.00008元/秒, 最便宜
        case funASR = "fun-asr"                 // 0.00022元/秒, 中文更强
    }

    private let submitURL = "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
    private let taskBaseURL = "https://dashscope.aliyuncs.com/api/v1/tasks"

    /// 轮询间隔（秒）
    private let pollInterval: UInt64 = 2_000_000_000   // 2 seconds
    /// 最大轮询次数（2秒 × 900 = 30分钟超时）
    private let maxPollAttempts = 900

    private func log(_ msg: String) { print("[ASR] \(msg)") }

    // MARK: - Config

    private var apiKey: String {
        AIConfig.shared.dashScopeAPIKey
    }

    // MARK: - Public: Transcribe Audio

    /// 完整转写流程：上传OSS → 提交任务 → 轮询 → 下载结果 → 解析
    /// - Parameters:
    ///   - audioFileURL: 本地音频文件 URL
    ///   - model: ASR 模型，默认 paraformer-v2
    ///   - languageHints: 语言提示，如 ["zh", "en"]
    ///   - diarizationEnabled: 是否启用说话人分离
    ///   - speakerCount: 说话人数量参考值（可选）
    func transcribe(
        audioFileURL: URL,
        model: ASRModel = .paraformerV2,
        languageHints: [String] = ["zh", "en"],
        diarizationEnabled: Bool = true,
        speakerCount: Int? = nil
    ) async throws -> ASRResult {
        guard !apiKey.isEmpty else { throw ASRError.noAPIKey }

        isTranscribing = true
        progress = 0
        statusText = "准备上传音频..."
        defer {
            Task { @MainActor in
                self.isTranscribing = false
            }
        }

        // Step 1: Upload to OSS
        statusText = "上传音频到云端..."
        progress = 0.1
        log("📤 Uploading audio: \(audioFileURL.lastPathComponent)")

        let publicURL: String
        do {
            publicURL = try await OSSUploadService.shared.uploadAudio(localURL: audioFileURL)
        } catch {
            throw ASRError.ossUploadFailed(error.localizedDescription)
        }
        log("✅ Upload complete: \(publicURL)")
        progress = 0.2

        // Step 2: Submit transcription task
        statusText = "提交转写任务..."
        let taskId = try await submitTask(
            fileURL: publicURL,
            model: model,
            languageHints: languageHints,
            diarizationEnabled: diarizationEnabled,
            speakerCount: speakerCount
        )
        log("📋 Task submitted: \(taskId)")
        progress = 0.3

        // Step 3: Poll for completion
        statusText = "AI 转写中..."
        let pollResult = try await pollTask(taskId: taskId)
        progress = 0.85

        // Step 4: Download result JSON
        statusText = "下载转写结果..."
        guard let transcriptionURL = pollResult.transcriptionURL else {
            throw ASRError.taskFailed("No transcription URL in result")
        }
        let resultJSON = try await downloadResult(url: transcriptionURL)
        progress = 0.95

        // Step 5: Parse
        statusText = "解析结果..."
        let result = try parseResult(jsonString: resultJSON)
        progress = 1.0
        statusText = "转写完成"
        log("✅ Transcription complete: \(result.text.prefix(100))...")

        return result
    }

    // MARK: - Step 2: Submit Task

    private func submitTask(
        fileURL: String,
        model: ASRModel,
        languageHints: [String],
        diarizationEnabled: Bool,
        speakerCount: Int?
    ) async throws -> String {
        guard let url = URL(string: submitURL) else {
            throw ASRError.submitFailed(0, "Invalid URL")
        }

        var parameters: [String: Any] = [
            "channel_id": [0],
            "diarization_enabled": diarizationEnabled,
            "timestamp_alignment_enabled": true
        ]

        // language_hints 仅 paraformer-v2 支持
        if model == .paraformerV2 {
            parameters["language_hints"] = languageHints
        }

        if let count = speakerCount, diarizationEnabled {
            parameters["speaker_count"] = count
        }

        let body: [String: Any] = [
            "model": model.rawValue,
            "input": [
                "file_urls": [fileURL]
            ],
            "parameters": parameters
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log("→ POST \(submitURL)")
        log("→ model=\(model.rawValue) lang=\(languageHints) diarization=\(diarizationEnabled)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw ASRError.submitFailed(0, "Non-HTTP response")
        }

        let respStr = String(data: data, encoding: .utf8) ?? ""
        log("← HTTP \(httpResp.statusCode): \(respStr.prefix(300))")

        guard httpResp.statusCode == 200 else {
            throw ASRError.submitFailed(httpResp.statusCode, respStr)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let taskId = output["task_id"] as? String else {
            throw ASRError.submitFailed(200, "Cannot parse task_id from response")
        }

        return taskId
    }

    // MARK: - Step 3: Poll Task

    private struct PollResult {
        let status: ASRTaskStatus
        let transcriptionURL: String?
        let rawOutput: [String: Any]
    }

    private func pollTask(taskId: String) async throws -> PollResult {
        let pollURL = "\(taskBaseURL)/\(taskId)"
        guard let url = URL(string: pollURL) else {
            throw ASRError.taskFailed("Invalid poll URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        for attempt in 0..<maxPollAttempts {
            try await Task.sleep(nanoseconds: pollInterval)

            // Check cancellation
            try Task.checkCancellation()

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                log("⚠ Poll HTTP error, retrying...")
                continue
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [String: Any],
                  let statusStr = output["task_status"] as? String else {
                log("⚠ Poll parse error, retrying...")
                continue
            }

            let status = ASRTaskStatus(rawValue: statusStr) ?? .unknown
            log("📊 Poll #\(attempt + 1): \(statusStr)")

            // 更新进度（从 0.3 到 0.85）
            let pollProgress = 0.3 + (0.55 * Double(min(attempt + 1, 50)) / 50.0)
            await MainActor.run {
                self.progress = pollProgress
                switch status {
                case .pending:  self.statusText = "排队等待中..."
                case .running:  self.statusText = "AI 转写中..."
                default:        break
                }
            }

            switch status {
            case .succeeded:
                // 提取 transcription_url
                var transcriptionURL: String?
                if let results = output["results"] as? [[String: Any]],
                   let first = results.first {
                    if first["subtask_status"] as? String == "SUCCEEDED" {
                        transcriptionURL = first["transcription_url"] as? String
                    } else {
                        let code = first["code"] as? String ?? ""
                        let msg = first["message"] as? String ?? ""
                        throw ASRError.taskFailed("子任务失败: [\(code)] \(msg)")
                    }
                }
                return PollResult(status: .succeeded, transcriptionURL: transcriptionURL, rawOutput: output)

            case .failed:
                let msg = output["message"] as? String ?? "Unknown error"
                let code = output["code"] as? String ?? ""
                throw ASRError.taskFailed("[\(code)] \(msg)")

            case .pending, .running, .unknown:
                continue
            }
        }

        throw ASRError.timeout
    }

    // MARK: - Step 4: Download Result

    private func downloadResult(url: String) async throws -> String {
        guard let resultURL = URL(string: url) else {
            throw ASRError.downloadFailed("Invalid URL: \(url)")
        }

        let request = URLRequest(url: resultURL, timeoutInterval: 30)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw ASRError.downloadFailed("HTTP error downloading result")
        }

        guard let jsonStr = String(data: data, encoding: .utf8) else {
            throw ASRError.downloadFailed("Cannot decode result as UTF-8")
        }

        log("📥 Downloaded result: \(jsonStr.count) chars")
        return jsonStr
    }

    // MARK: - Step 5: Parse Result

    private func parseResult(jsonString: String) throws -> ASRResult {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ASRError.parseFailed("Invalid JSON")
        }

        // Parse properties
        var properties = ASRProperties(
            audioFormat: "unknown",
            channels: [0],
            originalSamplingRate: 0,
            originalDurationInMilliseconds: 0
        )
        if let props = json["properties"] as? [String: Any] {
            properties = ASRProperties(
                audioFormat: props["audio_format"] as? String ?? "unknown",
                channels: props["channels"] as? [Int] ?? [0],
                originalSamplingRate: props["original_sampling_rate"] as? Int ?? 0,
                originalDurationInMilliseconds: props["original_duration_in_milliseconds"] as? Int ?? 0
            )
        }

        // Parse transcripts
        var fullText = ""
        var allSegments: [ASRSegment] = []

        if let transcripts = json["transcripts"] as? [[String: Any]] {
            for transcript in transcripts {
                if let text = transcript["text"] as? String {
                    fullText = text
                }

                if let sentences = transcript["sentences"] as? [[String: Any]] {
                    for sentence in sentences {
                        let beginTime = sentence["begin_time"] as? Int ?? 0
                        let endTime = sentence["end_time"] as? Int ?? 0
                        let text = sentence["text"] as? String ?? ""
                        let sentenceId = sentence["sentence_id"] as? Int ?? 0
                        let speakerId = sentence["speaker_id"] as? Int

                        // Parse words
                        var words: [ASRWord]?
                        if let wordDicts = sentence["words"] as? [[String: Any]] {
                            words = wordDicts.map { w in
                                ASRWord(
                                    beginTime: w["begin_time"] as? Int ?? 0,
                                    endTime: w["end_time"] as? Int ?? 0,
                                    text: w["text"] as? String ?? "",
                                    punctuation: w["punctuation"] as? String ?? ""
                                )
                            }
                        }

                        allSegments.append(ASRSegment(
                            beginTime: beginTime,
                            endTime: endTime,
                            text: text,
                            sentenceId: sentenceId,
                            speakerId: speakerId,
                            words: words
                        ))
                    }
                }
            }
        }

        return ASRResult(
            text: fullText,
            segments: allSegments,
            properties: properties,
            rawJSON: jsonString
        )
    }

    // MARK: - Utility: Format ASR Result for Display

    /// 将 ASR 结果格式化为带说话人标签和时间戳的显示文本
    static func formatForDisplay(result: ASRResult) -> String {
        var lines: [String] = []
        var lastSpeaker: Int? = nil

        for segment in result.segments {
            let timeStr = formatMillis(segment.beginTime)

            if let speakerId = segment.speakerId {
                if speakerId != lastSpeaker {
                    lines.append("")
                    lines.append("[\(speakerLabel(speakerId))] \(timeStr)")
                    lastSpeaker = speakerId
                }
                lines.append(segment.text)
            } else {
                lines.append("\(timeStr)  \(segment.text)")
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatMillis(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func speakerLabel(_ id: Int) -> String {
        let labels = ["说话人A", "说话人B", "说话人C", "说话人D", "说话人E", "说话人F"]
        return id < labels.count ? labels[id] : "说话人\(id + 1)"
    }
}
