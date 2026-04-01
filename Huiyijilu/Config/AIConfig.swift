//
//  AIConfig.swift
//  云雀记 (LarkNote)
//
//  统一的 AI 配置管理器 — 支持多 Provider 切换（策略模式）
//  密钥优先级：UserDefaults（设置页输入） > Secrets.swift（开发者本地）
//

import Foundation

// MARK: - AI Provider 枚举

/// 支持的 AI 服务提供商
enum AIProvider: String, CaseIterable, Identifiable {
    case dashScope = "dashscope"      // 阿里云 DashScope（通义千问）
    case openAI    = "openai"         // OpenAI (GPT)
    case claude    = "claude"         // Anthropic Claude
    case gemini    = "gemini"         // Google Gemini
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .dashScope: return "通义千问 (DashScope)"
        case .openAI:    return "OpenAI (GPT)"
        case .claude:    return "Claude (Anthropic)"
        case .gemini:    return "Gemini (Google)"
        }
    }
    
    var iconName: String {
        switch self {
        case .dashScope: return "sparkles"
        case .openAI:    return "brain.head.profile"
        case .claude:    return "message.badge.waveform"
        case .gemini:    return "diamond"
        }
    }
    
    /// 该 Provider 支持的模型列表
    var availableModels: [(name: String, label: String)] {
        switch self {
        case .dashScope:
            return [
                ("qwen-plus",  "Qwen Plus（推荐均衡）"),
                ("qwen-max",   "Qwen Max（最强性能）"),
                ("qwen-long",  "Qwen Long（超长上下文）"),
                ("qwen-turbo", "Qwen Turbo（最快最省）"),
            ]
        case .openAI:
            return [
                ("gpt-4o",      "GPT-4o（最强）"),
                ("gpt-4o-mini", "GPT-4o Mini（性价比）"),
                ("gpt-4-turbo", "GPT-4 Turbo"),
                ("gpt-3.5-turbo", "GPT-3.5 Turbo（经济）"),
            ]
        case .claude:
            return [
                ("claude-sonnet-4-20250514",   "Claude Sonnet 4（推荐）"),
                ("claude-opus-4-20250514", "Claude Opus 4（最强）"),
                ("claude-3-5-haiku-20241022", "Claude 3.5 Haiku（快速）"),
            ]
        case .gemini:
            return [
                ("gemini-2.5-pro",   "Gemini 2.5 Pro"),
                ("gemini-2.5-flash", "Gemini 2.5 Flash（快速）"),
                ("gemini-2.0-flash", "Gemini 2.0 Flash"),
            ]
        }
    }
    
    var defaultModel: String {
        availableModels.first?.name ?? ""
    }
}

// MARK: - Provider 配置

/// 单个 Provider 的完整配置
struct ProviderConfig {
    let apiKey: String
    let baseURL: String
    let model: String
    
    var isConfigured: Bool { !apiKey.isEmpty }
}

// MARK: - AI 配置管理器（单例）

/// 统一配置入口 — 读取优先级：UserDefaults > Secrets.swift
final class AIConfig {
    static let shared = AIConfig()
    private init() {}
    
    // MARK: - 当前 Provider
    
    var currentProvider: AIProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: "ai_provider") ?? AIProvider.dashScope.rawValue
            return AIProvider(rawValue: raw) ?? .dashScope
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ai_provider")
        }
    }
    
    // MARK: - 获取当前 Provider 配置
    
    var currentConfig: ProviderConfig {
        config(for: currentProvider)
    }
    
    /// 获取指定 Provider 的配置
    func config(for provider: AIProvider) -> ProviderConfig {
        switch provider {
        case .dashScope:
            return ProviderConfig(
                apiKey:  resolve(udKey: "openai_api_key",  secret: Secrets.dashScopeAPIKey),
                baseURL: resolve(udKey: "api_base_url",    secret: "https://dashscope.aliyuncs.com/compatible-mode/v1"),
                model:   resolve(udKey: "ai_model",        secret: "qwen-plus")
            )
        case .openAI:
            return ProviderConfig(
                apiKey:  resolve(udKey: "openai_api_key_openai", secret: Secrets.openAIAPIKey),
                baseURL: resolve(udKey: "api_base_url_openai",   secret: Secrets.openAIBaseURL),
                model:   resolve(udKey: "ai_model_openai",       secret: "gpt-4o-mini")
            )
        case .claude:
            return ProviderConfig(
                apiKey:  resolve(udKey: "openai_api_key_claude", secret: Secrets.claudeAPIKey),
                baseURL: resolve(udKey: "api_base_url_claude",   secret: Secrets.claudeBaseURL),
                model:   resolve(udKey: "ai_model_claude",       secret: "claude-sonnet-4-20250514")
            )
        case .gemini:
            return ProviderConfig(
                apiKey:  resolve(udKey: "openai_api_key_gemini", secret: Secrets.geminiAPIKey),
                baseURL: resolve(udKey: "api_base_url_gemini",   secret: Secrets.geminiBaseURL),
                model:   resolve(udKey: "ai_model_gemini",       secret: "gemini-2.5-flash")
            )
        }
    }
    
    // MARK: - 阿里云服务配置（非 AI 对话，但依赖相同 Key 体系）
    
    /// DashScope API Key (用于听悟、百炼等阿里云服务)
    var dashScopeAPIKey: String {
        resolve(udKey: "openai_api_key", secret: Secrets.dashScopeAPIKey)
    }
    
    /// 通义听悟配置
    var tingwuAppId: String {
        resolve(udKey: "tingwu_app_id", secret: Secrets.tingwuAppId)
    }
    var tingwuWorkspaceId: String {
        resolve(udKey: "tingwu_workspace_id", secret: Secrets.tingwuWorkspaceId)
    }
    
    /// 百炼工作流配置
    var bailianAppId: String {
        resolve(udKey: "bailian_workflow_app_id", secret: Secrets.bailianWorkflowAppId)
    }
    
    /// OSS 配置
    var ossKeyId: String {
        resolve(udKey: "oss_access_key_id", secret: Secrets.ossAccessKeyId)
    }
    var ossKeySecret: String {
        resolve(udKey: "oss_access_key_secret", secret: Secrets.ossAccessKeySecret)
    }
    var ossEndpoint: String {
        resolve(udKey: "oss_endpoint", secret: Secrets.ossEndpoint)
    }
    var ossBucket: String {
        resolve(udKey: "oss_bucket_name", secret: Secrets.ossBucketName)
    }
    
    // MARK: - ASR 转录配置
    
    /// ASR 模型名称（paraformer-v2 / fun-asr / local）
    var asrModel: String {
        UserDefaults.standard.string(forKey: "asr_model") ?? "paraformer-v2"
    }
    
    /// 默认录音语言
    var recordingLanguage: String {
        UserDefaults.standard.string(forKey: "recording_language") ?? "zh"
    }
    
    /// 是否启用说话人分离
    var enableSpeakerDiarization: Bool {
        UserDefaults.standard.bool(forKey: "enable_speaker_diarization")
    }
    
    /// 是否录音结束后自动转录
    var autoTranscribe: Bool {
        UserDefaults.standard.bool(forKey: "auto_transcribe")
    }
    
    /// ASR API Key（复用 DashScope API Key）
    var asrAPIKey: String {
        dashScopeAPIKey
    }
    
    // MARK: - Private Helpers
    
    /// 优先使用 UserDefaults 的值（用户在设置页输入的），其次使用 Secrets.swift 的值
    private func resolve(udKey: String, secret: String) -> String {
        let ud = UserDefaults.standard.string(forKey: udKey) ?? ""
        return ud.isEmpty ? secret : ud
    }
}
