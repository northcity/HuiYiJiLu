//
//  SettingsView.swift
//  Huiyijilu
//

import SwiftUI

/// Settings view for configuring API key and preferences
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("openai_api_key") private var apiKey = ""
    @AppStorage("api_base_url") private var apiBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    @AppStorage("ai_model") private var aiModel = "qwen-plus"
    @State private var showAPIKey = false
    @AppStorage("bailian_workflow_app_id") private var workflowAppId = ""

    // TingWu (通义听悟)
    @AppStorage("tingwu_app_id") private var tingwuAppId = ""
    @AppStorage("tingwu_workspace_id") private var tingwuWorkspaceId = ""

    // OSS
    @AppStorage("oss_access_key_id")     private var ossKeyId = ""
    @AppStorage("oss_access_key_secret") private var ossKeySecret = ""
    @AppStorage("oss_endpoint")          private var ossEndpoint = "oss-cn-shanghai.aliyuncs.com"
    @AppStorage("oss_bucket_name")       private var ossBucket = ""
    @State private var showOSSSecret = false

    var body: some View {
        NavigationStack {
            Form {
                // AI Configuration
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("sk-...", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("粘贴你的 API Key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("AI 会议总结必填。前往阿里云百炼控制台获取：bailian.console.aliyun.com")
                }

                Section {
                    TextField("API Base URL", text: $apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("API Base URL")
                } footer: {
                    Text("通义千问默认：dashscope.aliyuncs.com/compatible-mode/v1\n兼容任何 OpenAI 格式接口")
                }

                Section {
                    Picker("Model", selection: $aiModel) {
                        Text("Qwen Plus（推荐）").tag("qwen-plus")
                        Text("Qwen Max（最强）").tag("qwen-max")
                        Text("Qwen Long（超长上下文）").tag("qwen-long")
                        Text("Qwen Turbo（最快最省）").tag("qwen-turbo")
                        Text("GPT-4o Mini").tag("gpt-4o-mini")
                        Text("GPT-4o").tag("gpt-4o")
                    }
                } header: {
                    Text("AI 模型")
                }

                // Bailian Workflow
                Section {
                    HStack {
                        TextField("工作流 App ID", text: $workflowAppId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        if !workflowAppId.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("会议图文纪要工作流")
                } footer: {
                    Text("输入百炼应用工作流 App ID。\n工作流会自动接收录音音频文件并生成 HTML 格式的会议纪要。\n如工作流不可用，将自动回退到 AI 模型生成 Markdown 纪要。")
                }

                // TingWu 通义听悟 智能纪要
                Section {
                    HStack {
                        TextField("听悟 App ID（如 tw_xxx）", text: $tingwuAppId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        if !tingwuAppId.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    HStack {
                        TextField("Workspace ID（如 llm-xxx）", text: $tingwuWorkspaceId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        if !tingwuWorkspaceId.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("通义听悟·智能纪要")
                } footer: {
                    Text("输入通义听悟应用 App ID 和 Workspace ID。\n听悟会自动完成语音识别并生成结构化的会议智能纪要。\n前往 tingwu.aliyun.com 获取配置。")
                }

                // OSS 馅云对象存储
                Section {
                    TextField("Access Key ID", text: $ossKeyId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        if showOSSSecret {
                            TextField("Access Key Secret", text: $ossKeySecret)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Access Key Secret", text: $ossKeySecret)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showOSSSecret.toggle()
                        } label: {
                            Image(systemName: showOSSSecret ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Endpoint", text: $ossEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    TextField("Bucket Name", text: $ossBucket)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("阿里云 OSS 配置")
                } footer: {
                    Text("用于上传录音文件到 OSS，供工作流读取。需硬 config 公开读 Bucket。\nEndpoint 示例：oss-cn-shanghai.aliyuncs.com")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Speech Engine")
                        Spacer()
                        Text("iOS Speech (On-device)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }

                // Data
                Section {
                    Button(role: .destructive) {
                        // Clear all data
                    } label: {
                        Text("Clear All Data")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("This will delete all meetings and recordings")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
