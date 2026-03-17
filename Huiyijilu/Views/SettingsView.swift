//
//  SettingsView.swift
//  云雀记 (LarkNote)
//

import SwiftUI

/// Settings view for configuring cloud services and preferences
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - AI Configuration (DashScope/Qwen)
    @AppStorage("openai_api_key") private var apiKey = ""
    @AppStorage("api_base_url") private var apiBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    @AppStorage("ai_model") private var aiModel = "qwen-plus"
    @State private var showAPIKey = false
    @State private var apiConnectionStatus = ""
    
    // MARK: - Bailian Workflow (会议图文纪要)
    @AppStorage("bailian_workflow_app_id") private var workflowAppId = ""
    @State private var bailianConnectionStatus = ""

    // MARK: - TingWu (通义听悟 智能纪要)
    @AppStorage("tingwu_app_id") private var tingwuAppId = ""
    @AppStorage("tingwu_workspace_id") private var tingwuWorkspaceId = ""
    @State private var tingwuConnectionStatus = ""

    // MARK: - OSS (阿里云对象存储)
    @AppStorage("oss_access_key_id")     private var ossKeyId = ""
    @AppStorage("oss_access_key_secret") private var ossKeySecret = ""
    @AppStorage("oss_endpoint")          private var ossEndpoint = "oss-cn-shanghai.aliyuncs.com"
    @AppStorage("oss_bucket_name")       private var ossBucket = "ideasnap"
    @AppStorage("oss_upload_path")       private var ossUploadPath = "anpai/screenshots/"
    @State private var showOSSSecret = false
    @State private var ossConnectionStatus = ""
    
    // MARK: - UI State
    @State private var selectedTab: SettingsTab = .ai
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    
    enum SettingsTab {
        case ai, bailian, tingwu, oss, about
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Tab Navigation
                HStack(spacing: 0) {
                    ForEach([SettingsTab.ai, .bailian, .tingwu, .oss, .about], id: \.self) { tab in
                        VStack(spacing: 4) {
                            Image(systemName: tabIcon(tab))
                                .font(.system(size: 16, weight: .semibold))
                            Text(tabLabel(tab))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                        .padding(.vertical, 12)
                        .background(selectedTab == tab ? Color(.systemBackground) : Color(.systemGroupedBackground))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTab = tab }
                    }
                }
                .background(Color(.systemGroupedBackground))
                .overlay(alignment: .bottom) {
                    Divider()
                }

                // MARK: - Content
                Form {
                    switch selectedTab {
                    case .ai:
                        aiConfigurationSection
                    case .bailian:
                        bailianWorkflowSection
                    case .tingwu:
                        tingwuSection
                    case .oss:
                        ossConfigurationSection
                    case .about:
                        aboutSection
                    }
                }
            }
            .navigationTitle("云雀记 · 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("配置成功", isPresented: $showSuccessAlert) {
                Button("好的") { }
            } message: {
                Text(successMessage)
            }
        }
    }
    
    // MARK: - Configuration Sections
    
    @ViewBuilder
    private var aiConfigurationSection: some View {
        Section {
            HStack {
                if showAPIKey {
                    TextField("sk-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: apiKey) { _, _ in apiConnectionStatus = "" }
                } else {
                    SecureField("粘贴你的 DashScope API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, _ in apiConnectionStatus = "" }
                }
                Button {
                    showAPIKey.toggle()
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
            }
            
            if !apiConnectionStatus.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: apiConnectionStatus.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(apiConnectionStatus.contains("✓") ? .green : .orange)
                    Text(apiConnectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Label("API 密钥", systemImage: "key.fill")
                    .font(.headline.bold())
                Spacer()
                if !apiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("用于 AI 会议摘要、关键点、行动项提取")
                    .font(.caption)
                HStack(spacing: 8) {
                    Link("获取密钥", destination: URL(string: "https://bailian.console.aliyun.com")!)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Link("获取密钥 →", destination: URL(string: "https://bailian.console.aliyun.com")!)
                        .font(.caption)
                }
            }
        }
        
        Section {
            TextField("API Base URL", text: $apiBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(.body, design: .monospaced))
        } header: {
            Text("API 基址")
        } footer: {
            Text("默认值：https://dashscope.aliyuncs.com/compatible-mode/v1\n支持任何 OpenAI 兼容格式的 API")
        }

        Section {
            Picker("模型选择", selection: $aiModel) {
                Text("Qwen Plus（推荐均衡）").tag("qwen-plus")
                Text("Qwen Max（最强性能）").tag("qwen-max")
                Text("Qwen Long（超长上下文）").tag("qwen-long")
                Text("Qwen Turbo（最快最省）").tag("qwen-turbo")
                Text("GPT-4o Mini").tag("gpt-4o-mini")
                Text("GPT-4o（最强）").tag("gpt-4o")
            }
        } header: {
            Text("AI 模型")
        } footer: {
            Text("选择用于会议分析的模型。Qwen Plus 性价比最高。")
        }
    }
    
    @ViewBuilder
    private var bailianWorkflowSection: some View {
        Section {
            HStack {
                TextField("工作流 App ID（ce57...）", text: $workflowAppId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: workflowAppId) { _, _ in bailianConnectionStatus = "" }
                if !workflowAppId.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            
            if !bailianConnectionStatus.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: bailianConnectionStatus.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(bailianConnectionStatus.contains("✓") ? .green : .orange)
                    Text(bailianConnectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Label("图文纪要工作流", systemImage: "document.richtext.fill")
                    .font(.headline.bold())
                Spacer()
                if !workflowAppId.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("百炼工作流自动接收录音并生成专业的 HTML 格式会议纪要，返回结果支持浏览器在线查看。")
                    .font(.caption)
                HStack(spacing: 8) {
                    Link("获取工作流 ID", destination: URL(string: "https://bailian.console.aliyun.com")!)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                    Spacer()
                    Link("创建工作流 →", destination: URL(string: "https://bailian.console.aliyun.com")!)
                        .font(.caption)
                }
            }
        }
    }
    
    @ViewBuilder
    private var tingwuSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    TextField("App ID（tw_xxx）", text: $tingwuAppId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: tingwuAppId) { _, _ in tingwuConnectionStatus = "" }
                    if !tingwuAppId.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                
                HStack {
                    TextField("Workspace ID（llm-xxx）", text: $tingwuWorkspaceId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: tingwuWorkspaceId) { _, _ in tingwuConnectionStatus = "" }
                    if !tingwuWorkspaceId.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            
            if !tingwuConnectionStatus.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: tingwuConnectionStatus.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(tingwuConnectionStatus.contains("✓") ? .green : .orange)
                    Text(tingwuConnectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Label("通义听悟", systemImage: "waveform.circle.fill")
                    .font(.headline.bold())
                Spacer()
                if !tingwuAppId.isEmpty && !tingwuWorkspaceId.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("阿里云通义听悟为实时音视频、直播等生成高质量的字幕和纪要，支持 30 多语言。")
                    .font(.caption)
                HStack(spacing: 8) {
                    Link("获取听悟 App ID", destination: URL(string: "https://tingwu.aliyun.com")!)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Link("管理应用 →", destination: URL(string: "https://tingwu.aliyun.com")!)
                        .font(.caption)
                }
            }
        }
    }
    
    @ViewBuilder
    private var ossConfigurationSection: some View {
        Section {
            HStack {
                TextField("Access Key ID", text: $ossKeyId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: ossKeyId) { _, _ in ossConnectionStatus = "" }
            }
            
            HStack {
                if showOSSSecret {
                    TextField("Access Key Secret", text: $ossKeySecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: ossKeySecret) { _, _ in ossConnectionStatus = "" }
                } else {
                    SecureField("Access Key Secret", text: $ossKeySecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: ossKeySecret) { _, _ in ossConnectionStatus = "" }
                }
                Button {
                    showOSSSecret.toggle()
                } label: {
                    Image(systemName: showOSSSecret ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
            }
            
            if !ossConnectionStatus.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: ossConnectionStatus.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(ossConnectionStatus.contains("✓") ? .green : .orange)
                    Text(ossConnectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Label("阿里云身份认证", systemImage: "key")
                    .font(.headline.bold())
                Spacer()
                if !ossKeyId.isEmpty && !ossKeySecret.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("用于从 RAM 访问控制获得的 Access Key ID 和 Access Key Secret")
                    .font(.caption)
                Link("获取访问凭证 →", destination: URL(string: "https://ram.console.aliyun.com/users")!)
                    .font(.caption)
            }
        }
        
        Section {
            TextField("Endpoint", text: $ossEndpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(.body, design: .monospaced))
            
            TextField("Bucket Name", text: $ossBucket)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
            
            TextField("上传路径前缀", text: $ossUploadPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
        } header: {
            Text("OSS 存储配置")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("• Endpoint 示例：oss-cn-shanghai.aliyuncs.com")
                Text("• Bucket Name 示例：ideasnap")
                Text("• 上传路径示例：yunque/recordings/")
                    .font(.caption)
            }
        }
    }
    
    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack {
                Text("应用名称")
                Spacer()
                Text("云雀记")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text("2026.03.17")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("语音引擎")
                Spacer()
                Text("iOS Speech (本地)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } header: {
            Text("关于云雀记")
        }
        
        Section {
            HStack {
                Text("开发者")
                Spacer()
                Text("Cloud Lark Studio")
                    .foregroundStyle(.secondary)
            }
            Link("官网", destination: URL(string: "https://example.com")!)
            Link("隐私政策", destination: URL(string: "https://example.com/privacy")!)
            Link("服务条款", destination: URL(string: "https://example.com/terms")!)
        } header: {
            Text("链接")
        }
        
        Section {
            Button(role: .destructive) {
                // Implement clear data logic
            } label: {
                Label("清空所有数据", systemImage: "trash")
            }
        } footer: {
            Text("此操作将删除所有会议记录和录音文件，无法恢复")
        }
    }
    
    // MARK: - Utilities
    
    private func tabIcon(_ tab: SettingsTab) -> String {
        switch tab {
        case .ai: return "sparkles"
        case .bailian: return "document.richtext"
        case .tingwu: return "waveform.circle"
        case .oss: return "internaldrive"
        case .about: return "info.circle"
        }
    }
    
    private func tabLabel(_ tab: SettingsTab) -> String {
        switch tab {
        case .ai: return "AI"
        case .bailian: return "工作流"
        case .tingwu: return "听悟"
        case .oss: return "存储"
        case .about: return "关于"
        }
    }
}

#Preview {
    SettingsView()
}
