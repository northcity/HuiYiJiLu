//
//  SettingsView.swift
//  云雀记 (LarkNote)
//
//  全新设计的设置页 — 专业级 AI 会议纪要工具
//  信息架构：AI 设置 > 录音与转写 > 会议纪要 > 云服务 > 数据与同步 > 关于
//

import SwiftUI
import Combine

// MARK: - Settings ViewModel

@MainActor
final class SettingsViewModel: ObservableObject {
    
    // MARK: AI 设置
    @AppStorage("ai_provider")       var aiProvider: String = AIProvider.dashScope.rawValue
    @AppStorage("ai_model")          var aiModel: String = "qwen-plus"
    @AppStorage("ai_output_style")   var outputStyle: String = "balanced"
    @AppStorage("auto_summary")      var autoSummary: Bool = true
    
    // MARK: 录音与转写
    @AppStorage("recording_mode")    var recordingMode: String = "microphone"
    @AppStorage("auto_start_record") var autoStartRecord: Bool = false
    @AppStorage("speech_language")   var speechLanguage: String = "zh-Hans"
    @AppStorage("segment_duration")  var segmentDuration: Double = 30.0
    
    // MARK: 会议纪要
    @AppStorage("default_template")  var defaultTemplate: String = "standard"
    @AppStorage("auto_title")        var autoTitle: Bool = true
    @AppStorage("auto_action_items") var autoActionItems: Bool = true
    @AppStorage("export_format")     var exportFormat: String = "markdown"
    
    // MARK: 云服务密钥 (设置页输入，优先级高于 Secrets.swift)
    @AppStorage("openai_api_key")            var apiKey: String = ""
    @AppStorage("api_base_url")              var apiBaseURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    @AppStorage("bailian_workflow_app_id")    var workflowAppId: String = ""
    @AppStorage("tingwu_app_id")             var tingwuAppId: String = ""
    @AppStorage("tingwu_workspace_id")       var tingwuWorkspaceId: String = ""
    @AppStorage("oss_access_key_id")         var ossKeyId: String = ""
    @AppStorage("oss_access_key_secret")     var ossKeySecret: String = ""
    @AppStorage("oss_endpoint")              var ossEndpoint: String = "oss-cn-shanghai.aliyuncs.com"
    @AppStorage("oss_bucket_name")           var ossBucket: String = "ideasnap"
    @AppStorage("oss_upload_path")           var ossUploadPath: String = "meetings/audio/"
    
    // MARK: 数据
    @AppStorage("icloud_sync")       var iCloudSync: Bool = false
    
    // MARK: UI State
    @Published var showAPIKey = false
    @Published var showOSSSecret = false
    @Published var apiTestStatus: String = ""
    @Published var showClearDataAlert = false
    
    var selectedProvider: AIProvider {
        get { AIProvider(rawValue: aiProvider) ?? .dashScope }
        set {
            aiProvider = newValue.rawValue
            aiModel = newValue.defaultModel
            AIConfig.shared.currentProvider = newValue
        }
    }
    
    /// 当前 Provider 是否已配置密钥
    var isAPIKeyConfigured: Bool {
        !AIConfig.shared.currentConfig.apiKey.isEmpty
    }
    
    var isTingwuConfigured: Bool {
        !AIConfig.shared.tingwuAppId.isEmpty && !AIConfig.shared.tingwuWorkspaceId.isEmpty
    }
    
    var isOSSConfigured: Bool {
        !AIConfig.shared.ossKeyId.isEmpty && !AIConfig.shared.ossKeySecret.isEmpty
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SettingsViewModel()
    
    var body: some View {
        NavigationStack {
            Form {
                aiSection
                recordingSection
                meetingNotesSection
                cloudServicesSection
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("清空所有数据", isPresented: $vm.showClearDataAlert) {
                Button("取消", role: .cancel) {}
                Button("确认删除", role: .destructive) { clearAllData() }
            } message: {
                Text("此操作将删除所有会议记录和录音文件，无法恢复。")
            }
        }
    }
    
    // =========================================================================
    // MARK: - 🧠 AI 设置
    // =========================================================================
    
    private var aiSection: some View {
        Section {
            // AI 模型提供商
            Picker(selection: $vm.aiProvider) {
                ForEach(AIProvider.allCases) { provider in
                    Label(provider.displayName, systemImage: provider.iconName)
                        .tag(provider.rawValue)
                }
            } label: {
                Label("AI 提供商", systemImage: "cpu")
            }
            .onChange(of: vm.aiProvider) { _, newValue in
                if let p = AIProvider(rawValue: newValue) {
                    vm.aiModel = p.defaultModel
                    AIConfig.shared.currentProvider = p
                }
            }
            
            // 模型选择（动态跟随 Provider）
            Picker(selection: $vm.aiModel) {
                ForEach(vm.selectedProvider.availableModels, id: \.name) { model in
                    Text(model.label).tag(model.name)
                }
            } label: {
                Label("模型", systemImage: "sparkles")
            }
            
            // 输出风格
            Picker(selection: $vm.outputStyle) {
                Text("简洁摘要").tag("concise")
                Text("均衡（推荐）").tag("balanced")
                Text("详细分析").tag("detailed")
                Text("行动项优先").tag("action_items")
            } label: {
                Label("输出风格", systemImage: "text.alignleft")
            }
            
            // 自动总结
            Toggle(isOn: $vm.autoSummary) {
                Label("自动生成摘要", systemImage: "wand.and.stars")
            }
        } header: {
            Label("AI 智能", systemImage: "brain.head.profile")
        } footer: {
            Text("录音结束后自动调用 AI 分析会议内容，生成摘要和行动项。切换提供商需在「云服务配置」中填写对应密钥。")
        }
    }
    
    // =========================================================================
    // MARK: - 🎙 录音与转写
    // =========================================================================
    
    private var recordingSection: some View {
        Section {
            Picker(selection: $vm.recordingMode) {
                Text("麦克风").tag("microphone")
                Text("系统内录").tag("system")
            } label: {
                Label("录音模式", systemImage: "mic.fill")
            }
            
            Toggle(isOn: $vm.autoStartRecord) {
                Label("自动开始录音", systemImage: "record.circle")
            }
            
            Picker(selection: $vm.speechLanguage) {
                Text("中文（简体）").tag("zh-Hans")
                Text("中文（繁体）").tag("zh-Hant")
                Text("English").tag("en-US")
                Text("日本語").tag("ja-JP")
                Text("自动检测").tag("auto")
            } label: {
                Label("语音语言", systemImage: "globe")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("分段时长", systemImage: "timer")
                    Spacer()
                    Text("\(Int(vm.segmentDuration))秒")
                        .foregroundStyle(Color(.systemGray))
                        .font(.subheadline.monospacedDigit())
                }
                Slider(value: $vm.segmentDuration, in: 10...120, step: 5)
                    .tint(.blue)
            }
        } header: {
            Label("录音与转写", systemImage: "waveform")
        } footer: {
            Text("麦克风模式录制现场声音，系统内录模式可捕获设备内的音频（需 ReplayKit 权限）。分段时长影响本地语音识别的刷新频率。")
        }
    }
    
    // =========================================================================
    // MARK: - 📄 会议纪要
    // =========================================================================
    
    private var meetingNotesSection: some View {
        Section {
            Picker(selection: $vm.defaultTemplate) {
                Text("标准纪要").tag("standard")
                Text("简洁速记").tag("brief")
                Text("详细报告").tag("detailed")
                Text("头脑风暴").tag("brainstorm")
            } label: {
                Label("默认模板", systemImage: "doc.text")
            }
            
            Toggle(isOn: $vm.autoTitle) {
                Label("自动生成标题", systemImage: "textformat")
            }
            
            Toggle(isOn: $vm.autoActionItems) {
                Label("自动提取待办事项", systemImage: "checklist")
            }
            
            Picker(selection: $vm.exportFormat) {
                Text("Markdown").tag("markdown")
                Text("纯文本").tag("text")
                Text("HTML").tag("html")
            } label: {
                Label("导出格式", systemImage: "square.and.arrow.up")
            }
        } header: {
            Label("会议纪要", systemImage: "doc.richtext")
        } footer: {
            Text("配置纪要的默认生成风格和导出选项。AI 会根据所选模板调整输出格式。")
        }
    }
    
    // =========================================================================
    // MARK: - ☁️ 云服务配置
    // =========================================================================
    
    private var cloudServicesSection: some View {
        Section {
            // DashScope API Key
            NavigationLink {
                DashScopeConfigView(vm: vm)
            } label: {
                HStack {
                    Label("DashScope API", systemImage: "key.fill")
                    Spacer()
                    configStatusBadge(configured: vm.isAPIKeyConfigured)
                }
            }
            
            // 通义听悟
            NavigationLink {
                TingWuConfigView(vm: vm)
            } label: {
                HStack {
                    Label("通义听悟", systemImage: "waveform.circle.fill")
                    Spacer()
                    configStatusBadge(configured: vm.isTingwuConfigured)
                }
            }
            
            // 百炼工作流
            NavigationLink {
                BailianConfigView(vm: vm)
            } label: {
                HStack {
                    Label("百炼工作流", systemImage: "gearshape.2.fill")
                    Spacer()
                    configStatusBadge(configured: !vm.workflowAppId.isEmpty || !Secrets.bailianWorkflowAppId.isEmpty)
                }
            }
            
            // OSS 存储
            NavigationLink {
                OSSConfigView(vm: vm)
            } label: {
                HStack {
                    Label("OSS 对象存储", systemImage: "externaldrive.fill")
                    Spacer()
                    configStatusBadge(configured: vm.isOSSConfigured)
                }
            }
        } header: {
            Label("云服务配置", systemImage: "cloud.fill")
        } footer: {
            Text("配置阿里云相关服务的密钥。如果在 Secrets.swift 中已预设密钥，此处可留空。")
        }
    }
    
    // =========================================================================
    // MARK: - 💾 数据与同步
    // =========================================================================
    
    private var dataSection: some View {
        Section {
            Toggle(isOn: $vm.iCloudSync) {
                Label("iCloud 同步", systemImage: "icloud")
            }
            
            Button(role: .destructive) {
                vm.showClearDataAlert = true
            } label: {
                Label("清空所有数据", systemImage: "trash")
            }
        } header: {
            Label("数据管理", systemImage: "externaldrive")
        } footer: {
            Text("开启 iCloud 同步后，会议记录将在多设备间自动同步。")
        }
    }
    
    // =========================================================================
    // MARK: - ℹ️ 关于
    // =========================================================================
    
    private var aboutSection: some View {
        Section {
            HStack {
                Text("应用名称")
                Spacer()
                Text("云雀记")
                    .foregroundStyle(Color(.systemGray))
            }
            HStack {
                Text("版本")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(Color(.systemGray))
            }
            
            Link(destination: URL(string: "https://example.com/privacy")!) {
                Label("隐私政策", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://example.com/terms")!) {
                Label("服务条款", systemImage: "doc.plaintext")
            }
        } header: {
            Label("关于", systemImage: "info.circle")
        }
    }
    
    // MARK: - Helpers
    
    private func configStatusBadge(configured: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(configured ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(configured ? "已配置" : "未配置")
                .font(.caption)
                .foregroundStyle(configured ? .green : .orange)
        }
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    private func clearAllData() {
        // TODO: Implement via ModelContext
    }
}

// MARK: - DashScope 配置子页面

struct DashScopeConfigView: View {
    @ObservedObject var vm: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                HStack {
                    if vm.showAPIKey {
                        TextField("sk-...", text: $vm.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("粘贴你的 DashScope API Key", text: $vm.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        vm.showAPIKey.toggle()
                    } label: {
                        Image(systemName: vm.showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(Color(.systemGray))
                    }
                }
            } header: {
                Text("API 密钥")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("用于 AI 会议摘要、听悟、百炼等所有阿里云 DashScope 服务。")
                    Link("获取 API Key →", destination: URL(string: "https://bailian.console.aliyun.com")!)
                        .font(.caption)
                }
            }
            
            Section {
                TextField("https://dashscope.aliyuncs.com/compatible-mode/v1", text: $vm.apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("API 基址")
            } footer: {
                Text("默认使用 DashScope 兼容模式。支持任何 OpenAI 兼容的 API。")
            }
            
            if vm.isAPIKeyConfigured {
                Section {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("密钥已配置")
                            .foregroundStyle(Color(.systemGray))
                    }
                }
            }
        }
        .navigationTitle("DashScope API")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 通义听悟配置子页面

struct TingWuConfigView: View {
    @ObservedObject var vm: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                TextField("tw_xxx", text: $vm.tingwuAppId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                
                TextField("llm-xxx", text: $vm.tingwuWorkspaceId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("听悟应用配置")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("通义听悟提供专业的语音转写和智能会议纪要功能，支持 30+ 语言。")
                    HStack(spacing: 12) {
                        Link("获取 App ID →", destination: URL(string: "https://tingwu.aliyun.com")!)
                            .font(.caption)
                        Link("管理应用 →", destination: URL(string: "https://tingwu.aliyun.com")!)
                            .font(.caption)
                    }
                }
            }
            
            if vm.isTingwuConfigured {
                Section {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("听悟已配置")
                            .foregroundStyle(Color(.systemGray))
                    }
                }
            }
        }
        .navigationTitle("通义听悟")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 百炼工作流配置子页面

struct BailianConfigView: View {
    @ObservedObject var vm: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                TextField("工作流 App ID（ce57...）", text: $vm.workflowAppId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("工作流应用 ID")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("百炼工作流自动接收录音并生成专业的 HTML 格式会议纪要。")
                    HStack(spacing: 12) {
                        Link("获取工作流 ID →", destination: URL(string: "https://bailian.console.aliyun.com")!)
                            .font(.caption)
                        Link("创建工作流 →", destination: URL(string: "https://bailian.console.aliyun.com")!)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("百炼工作流")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - OSS 存储配置子页面

struct OSSConfigView: View {
    @ObservedObject var vm: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                TextField("Access Key ID", text: $vm.ossKeyId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    if vm.showOSSSecret {
                        TextField("Access Key Secret", text: $vm.ossKeySecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Access Key Secret", text: $vm.ossKeySecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        vm.showOSSSecret.toggle()
                    } label: {
                        Image(systemName: vm.showOSSSecret ? "eye.slash" : "eye")
                            .foregroundStyle(Color(.systemGray))
                    }
                }
            } header: {
                Text("阿里云身份认证")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("用于上传音频文件到 OSS，供听悟和百炼处理。")
                    Link("获取访问凭证 →", destination: URL(string: "https://ram.console.aliyun.com/users")!)
                        .font(.caption)
                }
            }
            
            Section {
                TextField("oss-cn-shanghai.aliyuncs.com", text: $vm.ossEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))
                
                TextField("Bucket Name", text: $vm.ossBucket)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                
                TextField("上传路径前缀", text: $vm.ossUploadPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("OSS 存储桶配置")
            } footer: {
                Text("Endpoint 示例：oss-cn-shanghai.aliyuncs.com")
            }
        }
        .navigationTitle("OSS 存储")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
