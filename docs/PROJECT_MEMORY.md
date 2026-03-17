# 🧠 AI会议记录 (MeetingMind) — 项目架构记忆文档

> 最后更新: 2025-06-17 | Xcode 26.2 | iOS 18.0+ | SwiftUI + SwiftData

---

## 一、项目概述

**AI会议记录** 是一款 iOS 本地录音 + AI 智能分析的会议助手 App。  
核心能力：一键录音 → 语音转文字 → AI 生成摘要/关键点/行动项 → 百炼工作流生成图文纪要 HTML。

| 属性 | 值 |
|---|---|
| Bundle ID (主 App) | `com.ceshi.ceshimainapp` |
| Bundle ID (广播扩展) | `com.ceshi.ceshimainapp.widget` |
| Bundle ID (Widget 扩展) | `com.ceshi.ceshimainapp.HuiyijiluWidget` |
| App Group | `group.com.ceshi.ceshimainapp` |
| Development Team | `WKG7GKH7M7` (iphoneos) / `87W4DKF7K6` (project) |
| GitHub 仓库 | `git@github.com:northcity/HuiYiJiLu.git` |
| 签名方式 | Manual (所有 target) |

---

## 二、项目结构

```
Huiyijilu/                          ← Xcode 项目根目录
├── Huiyijilu/                      ← 主 App target
│   ├── HuiyijiluApp.swift          ← @main 入口 (SwiftData ModelContainer)
│   ├── ContentView.swift           ← 根视图 → MeetingListView
│   ├── Info.plist                  ← ATS, BackgroundModes(audio), LiveActivities
│   ├── Huiyijilu.entitlements      ← Debug 签名 (App Group, APS)
│   ├── HuiyijiluRelease.entitlements ← Release 签名
│   ├── Assets.xcassets/            ← 图标 + 颜色
│   │
│   ├── Models/
│   │   ├── Meeting.swift           ← @Model 核心数据模型 (状态机: recording→completed)
│   │   ├── ActionItem.swift        ← @Model 行动项 (@Relationship → Meeting)
│   │   └── RecordingActivity.swift ← ActivityAttributes (灵动岛 LiveActivity)
│   │
│   ├── Services/
│   │   ├── AIService.swift         ← AI 摘要 (Qwen/DashScope, OpenAI兼容)
│   │   ├── AudioRecorderService.swift ← 麦克风录音 (AVAudioRecorder)
│   │   ├── SystemAudioRecorderService.swift ← 内录管理 (广播扩展生命周期 + ActivityKit)
│   │   ├── TranscriptionService.swift ← 本地语音转文字 (SFSpeechRecognizer)
│   │   ├── BailianWorkflowService.swift ← 百炼工作流 (会议图文纪要, SSE)
│   │   └── OSSUploadService.swift  ← 阿里云 OSS 上传 (UserDefaults 凭证)
│   │
│   └── Views/
│       ├── MeetingListView.swift   ← 首页 (问候+日期分组+卡片+FAB)
│       ├── MeetingDetailView.swift ← 详情页 (转写/摘要/行动项/播放器/SafariView)
│       ├── RecordingView.swift     ← 全屏录音 (麦克风/内录双模式)
│       ├── SettingsView.swift      ← 设置 (AI/百炼/OSS 配置)
│       └── Components/
│           ├── AudioPlayerView.swift     ← 音频播放器
│           ├── BroadcastPickerView.swift  ← RPSystemBroadcastPickerView 封装
│           ├── HTMLView.swift            ← WKWebView HTML 渲染
│           ├── MarkdownTextView.swift    ← AttributedString Markdown
│           └── SafariView.swift          ← SFSafariViewController 封装
│
├── HuiyijiluBroadcast/             ← 广播上传扩展 target (ReplayKit)
│   ├── SampleHandler.swift         ← RPBroadcastSampleHandler (AVAssetWriter → m4a)
│   ├── Info.plist                  ← broadcast-services-upload
│   └── HuiyijiluBroadcast.entitlements ← App Group
│
├── HuiyijiluWidget/                ← Widget 扩展 target (WidgetKit)
│   ├── HuiyijiluWidgetBundle.swift ← @main Widget 入口
│   ├── RecordingLiveActivity.swift ← 灵动岛 + 锁屏 Live Activity UI
│   ├── RecordingActivity.swift     ← ActivityAttributes (与主 App 同步)
│   ├── Info.plist                  ← widgetkit-extension
│   └── HuiyijiluWidget.entitlements ← App Group
│
└── Huiyijilu.xcodeproj/
    └── project.pbxproj             ← 3 个 target 配置
```

---

## 三、技术栈 & 依赖

### 框架

| 框架 | 用途 |
|---|---|
| **SwiftUI** | 全部 UI |
| **SwiftData** | 本地数据持久化 (Meeting, ActionItem) |
| **AVFoundation** | 音频录制/播放 (AVAudioRecorder, AVAudioPlayer, AVAssetWriter) |
| **Speech** | 本地语音识别 (SFSpeechRecognizer, zh-Hans) |
| **ReplayKit** | 系统内录 (RPBroadcastSampleHandler, RPSystemBroadcastPickerView) |
| **ActivityKit** | 灵动岛 Live Activity (录制状态) |
| **WidgetKit** | Widget 扩展 (ActivityConfiguration) |
| **WebKit** | WKWebView HTML 渲染 |
| **SafariServices** | SFSafariViewController 内嵌浏览 |
| **CommonCrypto** | OSS 签名 (HMAC-SHA1) |

### 云服务

| 服务 | 用途 | 配置方式 |
|---|---|---|
| **DashScope (通义千问)** | AI 摘要/标题/行动项 | UserDefaults: `ai_api_key`, `ai_base_url`, `ai_model` |
| **百炼工作流** | 会议图文纪要 HTML | UserDefaults: `bailian_workflow_app_id` |
| **阿里云 OSS** | 音频文件上传 | UserDefaults: `oss_access_key_id`, `oss_access_key_secret`, `oss_endpoint`, `oss_bucket_name` |
| **EdgeOne** | 图文纪要 HTML 托管 | 百炼工作流自动部署 |

### 无第三方依赖

项目不使用任何 SPM/CocoaPods 第三方库，全部原生实现。

---

## 四、核心数据模型

### Meeting (@Model)

```swift
@Model class Meeting {
    var id: UUID
    var title: String           // AI 或手动命名
    var date: Date
    var duration: TimeInterval
    var audioFileName: String?  // Recordings/meeting_xxx.m4a
    var transcript: String?     // 语音转文字
    var summary: String?        // AI 摘要
    var keyPoints: [String]     // AI 关键点
    var statusRaw: String       // MeetingStatus enum raw
    var richNotes: String?      // 百炼图文纪要 HTML
    @Relationship var actionItems: [ActionItem]
}

enum MeetingStatus: String {
    case recording, transcribing, summarizing, completed, failed
}
```

### ActionItem (@Model)

```swift
@Model class ActionItem {
    var id: UUID
    var title: String
    var assignee: String?
    var isCompleted: Bool
    var createdAt: Date
    var meeting: Meeting?       // @Relationship inverse
}
```

---

## 五、核心流程

### 录音 → 处理 → 保存

```
用户选择模式
├── 麦克风模式: AVAudioRecorder → 本地 m4a
└── 内录模式: RPBroadcastSampleHandler → App Group → 拷贝到本地

↓ 录音完成

1. 语音转文字 (TranscriptionService, SFSpeechRecognizer, 本地)
2. AI 生成摘要 (AIService, DashScope API, 远程)
   → title, summary, keyPoints, actionItems
3. 更新 SwiftData Meeting 对象
4. (可选) 百炼工作流 (BailianWorkflowService)
   → 上传 OSS → 调用工作流 → SSE 获取 HTML → 保存 richNotes
```

### 内录 (Broadcast Extension) 通信架构

```
主 App                          广播扩展 (独立进程)
  │                                │
  │  RPSystemBroadcastPickerView   │
  │  ──────────────────────────>   │
  │                                │
  │                    broadcastStarted()
  │                    → 创建 AVAssetWriter
  │                    → 写入 flag file
  │                    → Darwin Notify "started"
  │  <──────────────────────────   │
  │                                │
  │  handleBroadcastStarted()      │
  │  → isRecording = true          │
  │  → startTimer()                │  processSampleBuffer()
  │  → startLiveActivity()         │  → 写入音频数据
  │                                │
  │                    broadcastFinished()
  │                    → 完成 AVAssetWriter
  │                    → 删除 flag file
  │                    → Darwin Notify "stopped"
  │  <──────────────────────────   │
  │                                │
  │  collectRecordedAudio()        │
  │  → 拷贝 m4a 到 app 沙箱       │
```

### IPC 机制

| 机制 | 用途 |
|---|---|
| **App Group 共享容器** | 音频文件 (broadcast_recording.m4a) + flag file (is_recording) |
| **Darwin Notifications** | `com.huiyijilu.broadcast.started` / `.stopped` |
| **ActivityKit** | Live Activity 灵动岛状态更新 |

---

## 六、签名 & 证书配置

| Target | CODE_SIGN_STYLE | TEAM (iphoneos) | PROVISIONING_PROFILE |
|---|---|---|---|
| Huiyijilu (Debug) | Manual | WKG7GKH7M7 | testwatchmianapp_Dev |
| Huiyijilu (Release) | Manual | WKG7GKH7M7 | testwatchmianapp_Dev |
| HuiyijiluBroadcast | Manual | WKG7GKH7M7 | testmainwidget_dev |
| HuiyijiluWidget | Manual | WKG7GKH7M7 | (需配置) |

**Release 签名使用 `HuiyijiluRelease.entitlements`，Debug 使用 `Huiyijilu.entitlements`。**

---

## 七、已知问题 & 注意事项

### ⚠️ App Group ID 不一致 (已修复 → 统一为 group.com.ceshi.ceshimainapp)

- 需确保 Apple Developer Portal 中 3 个 App ID 都配置了同一个 App Group
- Debug/Release entitlements 文件中的 App Group ID 需与代码中 `SystemAudioRecorderService.appGroupID` 一致

### ⚠️ RecordingAttributes 重复定义

- `Huiyijilu/Models/RecordingActivity.swift` 和 `HuiyijiluWidget/RecordingActivity.swift` 需同步修改

### ⚠️ Release Entitlements

- `aps-environment` 当前为 `development`，上 App Store 时需改为 `production`

### ⚠️ 凭证管理

- 所有 API Key 和 OSS 凭证存储在 `UserDefaults`，需在 Settings 页面手动配置
- Top-level `Services/` 目录中的 AnPai 代码含硬编码凭证，已在 `.gitignore` 中排除

---

## 八、UserDefaults 配置项

| Key | 类型 | 用途 | 默认值 |
|---|---|---|---|
| `ai_api_key` | String | DashScope API Key | "" |
| `ai_base_url` | String | API 基础 URL | "https://dashscope.aliyuncs.com/compatible-mode/v1" |
| `ai_model` | String | 模型名称 | "qwen-plus" |
| `bailian_workflow_app_id` | String | 百炼工作流 App ID | "" |
| `oss_access_key_id` | String | OSS AccessKey ID | "" |
| `oss_access_key_secret` | String | OSS AccessKey Secret | "" |
| `oss_endpoint` | String | OSS Endpoint | "oss-cn-shanghai.aliyuncs.com" |
| `oss_bucket_name` | String | OSS Bucket 名称 | "" |
| `recording_mode` | String | 录音模式 (麦克风/内录) | "麦克风" |

---

## 九、文件存储路径

| 内容 | 路径 |
|---|---|
| 录音文件 | `Documents/Recordings/meeting_xxx.m4a` 或 `meeting_sys_xxx.m4a` |
| 广播录音 (共享容器) | `App Group Container/broadcast_recording.m4a` |
| 广播状态标记 | `App Group Container/is_recording` |
| SwiftData | `默认容器 (自动管理)` |

---

## 十、Git 提交历史

| Commit | 描述 |
|---|---|
| `1137e63` | 初始提交 — MVP 全部功能 |
| `f03bd10` | 安全修复 — OSS 凭证移至 UserDefaults |
| `70ac174` | UI 优化 — 会议列表重设计 + Markdown 渲染 |
| `5566c2a` | 功能 — ReplayKit 系统内录 (RPScreenRecorder) |
| `3172149` | 功能 — Broadcast Upload Extension 内录 |
| `0780d6e` | 功能 — Dynamic Island 灵动岛 + 修复内录检测 |
