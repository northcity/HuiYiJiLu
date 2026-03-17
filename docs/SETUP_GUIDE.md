# 🦅 云雀记 — 快速配置指南

> 最后更新: 2026-03-17 | 所有配置均已集成至应用内设置

---

## 📱 应用内设置指南

云雀记的所有云服务配置都在 **设置 → 云雀记 · 设置** 中进行，分为 5 个主要标签。

---

## 1️⃣ AI 配置 (通义千问/DashScope)

### 用途
- 自动生成会议摘要
- 提取关键要点
- 自动生成行动项
- 生成会议标题

### 配置步骤

#### 1. 获取 API Key

**官方渠道**: https://bailian.console.aliyun.com

1. 登录阿里云百炼控制台
2. 左侧菜单 → API Keys → 创建新密钥
3. 复制生成的 API Key (格式: `sk-xxx...`)

**测试密钥**: `<YOUR_API_KEY>`
- 在应用设置中点击 **复制测试密钥** 一键填入

#### 2. 设置 API Base URL

**默认值** (推荐):
```
https://dashscope.aliyuncs.com/compatible-mode/v1
```

该 URL 支持 OpenAI 兼容格式接口，如需使用其他 API，可在此修改。

#### 3. 选择 AI 模型

| 模型 | 性能 | 价格 | 推荐场景 |
|---|---|---|---|
| **Qwen Plus** (推荐) | ⭐⭐⭐⭐ | 💰💰 | 生产环境，日常使用 |
| Qwen Max | ⭐⭐⭐⭐⭐ | 💰💰💰 | 超复杂分析场景 |
| Qwen Long | ⭐⭐⭐⭐ | 💰💰 | 超长会议录音 (8小时+) |
| Qwen Turbo | ⭐⭐⭐ | 💰 | 快速响应，成本优先 |
| GPT-4o | ⭐⭐⭐⭐⭐ | 💰💰💰💰 | 最高质量，国际用户 |
| GPT-4o Mini | ⭐⭐⭐⭐ | 💰💰 | 成本与质量平衡 |

#### 4. 验证配置

应用会自动检测配置状态：
- ✅ 绿色对勾 → 配置完成
- ⚠️ 橙色感叹号 → 配置不完整或无效

---

## 2️⃣ 工作流配置 (百炼 - 会议图文纪要)

### 用途
- 生成专业的 HTML 格式会议纪要
- 支持浏览器在线查看
- 自动上传至 EdgeOne 云端

### 配置步骤

#### 1. 获取工作流 App ID

**官方渠道**: https://bailian.console.aliyun.com

1. 控制台左侧 → 应用 → 我的应用
2. 创建新应用或选择现有应用
3. 配置工作流：上传录音 → 生成图文纪要
4. 复制应用 ID (格式: `ce57...`)

**测试工作流 ID**: `<YOUR_WORKFLOW_APP_ID>`
- 在应用设置中点击 **复制测试ID** 一键填入

#### 2. 工作流流程

```
录音完成
  ↓
上传至 OSS
  ↓
调用百炼工作流
  ↓
工作流接收音频
  ↓
AI 分析处理
  ↓
生成 HTML 纪要
  ↓
应用展示
```

#### 3. 如果工作流不可用

应用会自动回退到 **AI 模型直接生成 Markdown 纪要**，无需手动干预。

---

## 3️⃣ 通义听悟配置

### 用途
- 高质量语音识别 (可选，主要用 iOS Speech)
- 生成专业的转写和纪要
- 支持 30+ 语言识别

### 配置步骤

#### 1. 获取 App ID 和 Workspace ID

**官方渠道**: https://tingwu.aliyun.com

1. 登录通义听悟控制台
2. 创建新应用或使用现有应用
3. 获取 **App ID** (格式: `tw_xxx`)
4. 获取 **Workspace ID** (格式: `llm-xxx`)

**测试凭证**:
- App ID: `<YOUR_TINGWU_APP_ID>`
- Workspace ID: `<YOUR_TINGWU_WORKSPACE_ID>`
- 在应用设置中点击 **复制测试ID** 一键填入

#### 2. 注意事项

- 听悟配置为**可选项**
- 云雀记 v1.0 默认使用 iOS 本地语音识别
- 听悟配置主要为**未来扩展**预留

---

## 4️⃣ 阿里云 OSS 配置 (对象存储)

### 用途
- 存储录音文件
- 供百炼工作流读取
- 云端备份

### 配置步骤

#### 1. 获取身份认证凭证

**官方渠道**: https://ram.console.aliyun.com/users

1. 登录阿里云 RAM 访问控制
2. 用户 → 用户列表 → 选择用户
3. 创建 Access Key
4. 复制 **Access Key ID** 和 **Access Key Secret**

#### 2. 配置 OSS Bucket

**官方渠道**: https://oss.console.aliyun.com

1. 创建新 Bucket 或选择现有 Bucket
2. 获取 **Bucket Name** (例: `ideasnap`)
3. 记录 **Endpoint** (例: `oss-cn-shanghai.aliyuncs.com`)

| 地域 | Endpoint | 备注 |
|---|---|---|
| 华东1（杭州）| `oss-cn-hangzhou.aliyuncs.com` | - |
| 华东2（上海）| `oss-cn-shanghai.aliyuncs.com` | **推荐** |
| 华北1（青岛）| `oss-cn-qingdao.aliyuncs.com` | - |
| 华南1（深圳）| `oss-cn-shenzhen.aliyuncs.com` | - |

#### 3. OSS 安全配置

**CORS 跨域配置** (如需浏览器访问):

```xml
<CORSConfiguration>
  <CORSRule>
    <AllowedOrigin>*</AllowedOrigin>
    <AllowedMethod>GET</AllowedMethod>
    <AllowedMethod>PUT</AllowedMethod>
    <AllowedMethod>POST</AllowedMethod>
    <AllowedHeader>*</AllowedHeader>
  </CORSRule>
</CORSConfiguration>
```

**Bucket Policy** (公开读权限):

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "oss:GetObject",
      "Resource": "oss://bucket-name/*"
    }
  ]
}
```

#### 4. 测试配置

**测试凭证**:
```
Access Key ID:     <YOUR_OSS_KEY_ID>
Access Key Secret: <YOUR_OSS_KEY_SECRET>
Endpoint:          oss-cn-shanghai.aliyuncs.com
Bucket Name:       ideasnap
Upload Path:       yunque/
```

**⚠️ 警告**: 这些是演示凭证，仅供测试使用。生产环境必须使用自己的凭证。

---

## 🔐 配置安全最佳实践

### ✅ 应该做

- [ ] 定期更新 API Key
- [ ] 为 API 密钥设置访问限制
- [ ] 使用 RAM 子账户的密钥，而非主账户
- [ ] 启用 Bucket 文件版本控制
- [ ] 定期检查 API 使用统计

### ❌ 不应该做

- [ ] **不要**在代码中硬编码密钥
- [ ] **不要**将密钥上传至公开 Git 仓库
- [ ] **不要**在截图/视频中暴露私密密钥
- [ ] **不要**给予过于宽泛的 IAM 权限
- [ ] **不要**在生产环境中使用测试密钥

---

## 📋 完整配置检查清单

### 最小化配置 (MVP 可用)

- [ ] AI API Key (DashScope)
- [ ] AI Base URL
- [ ] AI 模型选择

### 完整配置 (推荐)

- [ ] ✅ AI API Key
- [ ] ✅ AI Base URL
- [ ] ✅ AI 模型
- [ ] ✅ 百炼工作流 App ID
- [ ] ✅ OSS Access Key ID
- [ ] ✅ OSS Access Key Secret
- [ ] ✅ OSS Endpoint
- [ ] ✅ OSS Bucket Name
- [ ] ✅ OSS Upload Path

### 高级配置 (可选)

- [ ] 🔲 通义听悟 App ID
- [ ] 🔲 通义听悟 Workspace ID

---

## 🆘 常见问题与排查

### 问题 1: API Key 无效

**症状**: 总是显示 "⚠️ 配置错误"

**排查步骤**:
1. 确认 API Key 前缀是否为 `sk-`
2. 验证密钥是否过期 (可在阿里云控制台查看密钥状态)
3. 尝试用测试密钥验证 App 是否能正常工作
4. 检查网络连接

**解决方案**:
- 重新生成 API Key
- 等待 5 分钟让新密钥生效
- 重启应用

### 问题 2: 工作流返回 HTML 失败

**症状**: 生成 Markdown 纪要但不生成 HTML

**排查步骤**:
1. 确认工作流 App ID 是否正确
2. 确认 OSS 配置是否完整
3. 检查 OSS Bucket 权限设置

**解决方案**:
- 验证 OSS Bucket 已设置公开读权限
- 检查百炼工作流的消息队列设置
- 参考: https://bailian.console.aliyun.com

### 问题 3: 录音上传 OSS 失败

**症状**: 显示 "上传失败"

**排查步骤**:
1. 确认 Access Key ID/Secret 正确
2. 确认 Endpoint 格式正确
3. 确认 Bucket Name 存在

**解决方案**:
- 在 OSS 控制台测试上传文件
- 检查 RAM 用户权限: `oss:PutObject`
- 验证网络连接

### 问题 4: 通义听悟识别不工作

**症状**: 显示 "听悟不可用"

**排查步骤**:
1. 确认 App ID 和 Workspace ID 均已填写
2. 检查听悟服务是否启用

**解决方案**:
- v1.0 版本中听悟配置为可选项，可暂时忽略
- 系统会自动回退到 iOS 本地语音识别

---

## 🚀 配置完成后

### 验证流程

1. **开始录音**
   - 打开云雀记 → 点击大按钮开始录音
   - 录制 30 秒测试内容

2. **等待处理**
   - 系统自动进行: 转写 → AI 分析 → 生成纪要

3. **查看结果**
   - 转写文本 (iOS Speech)
   - AI 生成的摘要、关键点、行动项
   - (可选) HTML 格式图文纪要

### 性能优化建议

| 优化项 | 建议 |
|---|---|
| 转写速度 | 使用 Qwen Turbo 或 Qwen Plus |
| 分析准确率 | 使用 Qwen Max (需付费) |
| 成本控制 | 使用 Qwen Plus (最佳性价比) |
| 超长会议 | 使用 Qwen Long (8小时+) |

---

## 📞 获取帮助

### 官方资源

- 🌐 **百炼控制台**: https://bailian.console.aliyun.com
- 📚 **API 文档**: https://help.aliyun.com/document_detail/2712612.html
- 🎤 **通义听悟**: https://tingwu.aliyun.com
- 📦 **OSS 管理**: https://oss.console.aliyun.com
- 🔑 **RAM 访问控制**: https://ram.console.aliyun.com

### 常见链接速记

| 功能 | 链接 | 复制快捷键 |
|---|---|---|
| 获取 API Key | bailian.console.aliyun.com | App 设置中点击 "复制测试密钥" |
| 创建工作流 | bailian.console.aliyun.com | App 设置中点击 "创建工作流" |
| 听悟管理 | tingwu.aliyun.com | App 设置中点击 "管理应用" |
| OSS 存储 | oss.console.aliyun.com | - |
| RAM 密钥管理 | ram.console.aliyun.com/users | - |

---

## 📝 更新记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-03-17 | 1.0 | 初始快速配置指南发布 |
