# � 云雀记 (LarkNote) — 项目架构记忆文档

> 最后更新: 2026-04-01 | Xcode 26.2 | iOS 18.0+ | SwiftUI + SwiftData

---

**最后更新**: 2026-04-01

## 📋 项目基本信息

**项目名称**: 云雀记  
**开发者**: 北城  
**角色**: 产品经理 + iOS 开发  
**开发工具**: Claude Code (AI辅助开发)  
**语言偏好**: 中文  
**创建时间**: 2025年12月28日  

**最后更新**: 2026年1月27日（第八十二次）

---

## 🎯 产品理念

### 核心方法论：简单
> 专注于一个功能并做到极致，而不是做加法

### 产品三段论
1. **预测** - 预测市场趋势
2. **单点击穿** - 找到一个点站稳脚跟
3. **All in** - 投入所有资源

### 设计原则
- 追求极致的简单
- UI基础薄弱但有审美
- 功能专注，体验极致


## 一、项目概述

**云雀记** 是一款 iOS 本地录音 + AI 智能分析的会议助手 App。  
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
│   │   ├── Meeting.swift           ← @Model 核心数据模型 (状态机: recording→saved→transcribed→completed)
│   │   ├── ActionItem.swift        ← @Model 行动项 (@Relationship → Meeting)
│   │   ├── RecordingBookmark.swift ← Codable 录音书签 (flag/note/photo) [新增]
│   │   └── RecordingActivity.swift ← ActivityAttributes (灵动岛 LiveActivity)
│   │
│   ├── Services/
│   │   ├── AIService.swift         ← AI 摘要 (Qwen/DashScope, OpenAI兼容)
│   │   ├── AliyunASRService.swift  ← 阿里云 DashScope ASR (paraformer-v2/fun-asr) [新增]
│   │   ├── AudioRecorderService.swift ← 麦克风录音 (AVAudioRecorder)
│   │   ├── SystemAudioRecorderService.swift ← 内录管理 (广播扩展生命周期 + ActivityKit)
│   │   ├── MeetingProcessingService.swift ← 转录 + AI 处理编排 (重构为两阶段)
│   │   ├── TranscriptionService.swift ← 本地语音转文字 (SFSpeechRecognizer, 备用)
│   │   ├── BailianWorkflowService.swift ← 百炼工作流 (代码保留, UI 已隐藏)
│   │   └── OSSUploadService.swift  ← 阿里云 OSS 上传 (UserDefaults 凭证)
│   │
│   └── Views/
│       ├── MeetingListView.swift   ← 首页 (问候+日期分组+卡片+FAB)
│       ├── MeetingDetailView.swift ← 详情页 (转录入口 + AI 任务选择 + 播放器)
│       ├── RecordingView.swift     ← 全屏录音 (竞品风格重写, 录音纯保存)
│       ├── SettingsView.swift      ← 设置 (AI/ASR/OSS 配置, 百炼/通义听悟隐藏)
│       └── Components/
│           ├── AudioPlayerView.swift     ← 音频播放器
│           ├── BroadcastPickerView.swift  ← RPSystemBroadcastPickerView 封装
│           ├── CircularWaveView.swift    ← 录音圆形呼吸波形动画 [新增]
│           ├── HTMLView.swift            ← WKWebView HTML 渲染
│           ├── MarkdownTextView.swift    ← AttributedString Markdown
│           ├── RecordingToolbar.swift    ← 录音工具栏 (书签/备注/拍照) [新增]
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
| **DashScope (通义千问)** | AI 摘要/标题/行动项 + ASR 语音转文字 | UserDefaults: `ai_api_key`, `ai_base_url`, `ai_model` |
| **DashScope ASR** | 录音文件转文字 (paraformer-v2 / fun-asr) | 复用 `ai_api_key`，独立配置 `asr_model` |
| **阿里云 OSS** | 音频文件上传（ASR 需要公网 URL） | UserDefaults: `oss_access_key_id`, `oss_access_key_secret`, `oss_endpoint`, `oss_bucket_name` |
| **百炼工作流** | 会议图文纪要 HTML（代码保留，UI 已隐藏） | UserDefaults: `bailian_workflow_app_id` |
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
    // ——— 2026-04-01 新增字段 ———
    var languageCode: String    // 录音语言 (zh/en/zh-en/ja/ko/yue/auto)
    var bookmarksJSON: String   // JSON 序列化的 [RecordingBookmark]
    var sourceType: String      // microphone / system / import
    var transcriptProvider: String  // "" / "local" / "paraformer-v2" / "fun-asr"
    var isTranscribed: Bool     // 是否已完成 ASR 转录
    var isAIProcessed: Bool     // 是否已完成 AI 处理
    var asrRawResult: String    // ASR 原始 JSON (含说话人/时间戳)
    var ossAudioURL: String?    // OSS 公网 URL (ASR 需要)
    @Relationship var actionItems: [ActionItem]
}

enum MeetingStatus: String {
    case recording              // 录音中
    case saved                  // 已保存，待转录 [新增]
    case transcribing           // 转录中
    case transcribed            // 已转录，待 AI 处理 [新增]
    case summarizing            // AI 处理中
    case processing             // AI 处理中（统一别名）[新增]
    case completed              // 全部完成
    case failed                 // 失败
}
```

### RecordingBookmark (Codable, 新增)

```swift
struct RecordingBookmark: Codable, Identifiable, Equatable {
    var id: UUID
    var timestamp: TimeInterval  // 录音内时间戳（秒）
    var label: String            // 自定义标签
    var type: BookmarkType       // .flag / .note / .photo
    var photoFileName: String?   // Documents/MeetingPhotos/xxx.jpg
}
enum BookmarkType: String, Codable { case flag, note, photo }
```

Meeting.bookmarksList 是对 `bookmarksJSON` 的 computed 读写属性，和 `keyPointsList` 模式一致。

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

### 新三段式流程（2026-04-01 重构后）

```
阶段一：录音（纯录音，不做任何 AI）
├── 麦克风模式: AVAudioRecorder → 本地 m4a
└── 内录模式: RPBroadcastSampleHandler → App Group → 拷贝到本地
录音中可操作：旗帜书签 / 文字备注 / 拍照存档
↓ 用户点击停止

阶段二：AI 转录（用户主动触发，在详情页）
1. 上传音频到阿里云 OSS (OSSUploadService)
2. 提交 DashScope ASR 任务 (AliyunASRService)
   POST https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription
   模型: paraformer-v2 (默认) / fun-asr (可选)
3. 轮询任务状态 (GET /tasks/{task_id}，间隔 2s)
4. 下载 transcription_url JSON → 解析 → 存入 transcript
5. Meeting.status → .transcribed
备用: 本地 SFSpeechRecognizer (TranscriptionService)

阶段三：AI 处理（用户勾选任务，按需触发）
可选任务: 生成标题 / 摘要 / 章节 / 行动项 / 决策 / 润色
调用: AIService (DashScope Qwen-Plus 或其他模型)
Meeting.status → .completed
```

### 旧流程（已废弃，代码标记 @available(*, deprecated)）

```
RecordingView.stopAndProcess() → 立即转写 → AI分析 → dismiss()
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
| `asr_model` | String | ASR 模型 (paraformer-v2/fun-asr/local) | "paraformer-v2" |
| `recording_language` | String | 默认录音语言代码 | "zh" |
| `enable_speaker_diarization` | Bool | 启用说话人分离 | false |
| `auto_transcribe` | Bool | 录音结束后自动触发转录 | false |

---

## 九、文件存储路径

| 内容 | 路径 |
|---|---|
| 录音文件 | `Documents/Recordings/meeting_xxx.m4a` 或 `meeting_sys_xxx.m4a` |
| 广播录音 (共享容器) | `App Group Container/broadcast_recording.m4a` |
| 广播状态标记 | `App Group Container/is_recording` |
| 录音书签照片 | `Documents/MeetingPhotos/photo_xxx.jpg` |
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
| 2026-04-01 | 重构 — 录音流程全面重构（三段式 + DashScope ASR） |

---

## 十一、录音流程重构记录（2026-04-01）

### 核心变更

**前：** 录音结束 → 自动转录 + AI 分析 → 用户必须等待
**后：** 录音结束 → **立即保存** → AI 转录（按需）→ AI 处理（按需）

### 新建文件

| 文件 | 作用 |
|---|---|
| `Models/RecordingBookmark.swift` | 录音书签（旗帜/备注/拍照）数据模型 |
| `Views/Components/CircularWaveView.swift` | 录音页圆形呼吸动画，4层同心圆 |
| `Views/Components/RecordingToolbar.swift` | 录音工具栏，支持旗帜书签/文字备注/拍照 |
| `Services/AliyunASRService.swift` | DashScope ASR 异步转录（提交→轮询→下载） |

### 修改文件

| 文件 | 主要变更 |
|---|---|
| `Models/Meeting.swift` | +8 新字段，+3 新状态 (.saved/.transcribed/.processing) |
| `Views/RecordingView.swift` | 全面重写：竞品风格 UI，语言选择器，16根音量条，REC 闪烁，圆形波形 |
| `Services/MeetingProcessingService.swift` | 重构为 `transcribe()` + `processWithAI()` 两阶段方法 |
| `Views/MeetingDetailView.swift` | +转录入口区 / AI 任务勾选区 / 处理状态覆盖层 |
| `Views/SettingsView.swift` | +ASR 配置分区，百炼/通义听悟隐藏到开发者模式 |
| `Views/MeetingListView.swift` | 新状态颜色/标签/状态能 |
| `Config/AIConfig.swift` | +ASR 相关属性 (asrModel/asrAPIKey/recordingLanguage 等) |

### ASR 模型对比

| 模型 | 计费 | 适用场景 | UI 状态 |
|---|---|---|---|
| paraformer-v2 | ¥0.00008/秒 | 多语言，企业会议 | 默认选项 |
| fun-asr | ¥0.00022/秒 | 中文优化，噪音鲁棒 | 隐藏（预留） |
| 本地 | 免费 | 离线 | 备用入口 |

### 录音 UI 语言选项

| 代码 | 显示 | API language_hints |
|---|---|---|
| zh | 中文 | ["zh"] |
| en | English | ["en"] |
| zh-en | 中英混合 | ["zh", "en"] |
| ja | 日语 | ["ja"] |
| ko | 韩语 | ["ko"] |
| yue | 粤语 | ["yue"] |
| auto | 自动识别 | nil (省略参数) |
