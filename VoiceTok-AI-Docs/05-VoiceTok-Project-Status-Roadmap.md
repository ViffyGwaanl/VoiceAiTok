# VoiceTok — 项目状态与开发路线图

> **文档类型**：工程状态追踪 + 产品路线图
> **最后更新**：2026-04-02
> **当前版本**：v1.0.0（Build 8，多供应商转录 + Bug 修复）
> **仓库**：https://github.com/ViffyGwaanl/VoiceAiTok

---

## 一、交付清单 — v1.0

### 核心功能

| 功能 | 状态 | Commit |
|------|------|--------|
| 项目框架（SwiftUI、MVVM、AppState DI） | ✅ 完成 | d6a1814 |
| MobileVLCKit 3.7 CocoaPods 集成 | ✅ 完成 | 8f5e0c7 |
| WhisperKit 0.18 SPM 集成 | ✅ 完成 | 8f5e0c7 |
| AVMediaPlayerService 备用播放器 | ✅ 完成 | d6a1814 |
| VLCPlayerService + VLCVideoRepresentable | ✅ 完成 | 8f5e0c7 |
| TranscriptionService — WhisperKit 本地转录 | ✅ 完成 | d6a1814 |
| TranscriptionService — Apple SFSpeechRecognizer | ✅ 完成 | 当前 |
| TranscriptionService — OpenAI Whisper API | ✅ 完成 | 当前 |
| 多供应商路由（TranscriptionProvider 枚举） | ✅ 完成 | 当前 |
| WhisperKit 时间戳 Token 过滤（`<|6.00|>`） | ✅ 完成 | 当前 |
| 播放器内转录设置面板（供应商/模型/语言） | ✅ 完成 | 当前 |
| 转录后 Chat 标签页内容消失 Bug 修复 | ✅ 完成 | 当前 |
| 实时转录进度回调（WindowId 估算） | ✅ 完成 | 25cdca9 |
| 音频提取（AVAssetReader → 16kHz WAV） | ✅ 完成 | d6a1814 |
| AVLinearPCMIsNonInterleaved 真机崩溃修复 | ✅ 完成 | 5559bcf |
| MediaLibraryService（导入、缩略图、持久化） | ✅ 完成 | d6a1814 |
| ChatService — Claude / OpenAI / Ollama 流式 | ✅ 完成 | d6a1814 |
| AI 供应商多供应商管理（无限添加） | ✅ 完成 | 93a3d8c |
| 模型自动获取 + API Key 测试 | ✅ 完成 | 93a3d8c |
| ChatView — 复制/重生成/停止/供应商标签 | ✅ 完成 | 9e27f15 |
| API 密钥 → iOS Keychain | ✅ 完成 | 25cdca9 |
| 长文本 Token 截断（80k 上限） | ✅ 完成 | 25cdca9 |
| WhisperKit 模型下载、切换、删除 UI | ✅ 完成 | aec0fe9 |
| 媒体库搜索、排序、滑动删除 | ✅ 完成 | d6a1814 |
| 转录导出（Markdown） | ✅ 完成 | 9e27f15 |
| 简体中文本地化（zh-Hans，~110 条） | ✅ 完成 | d86d238 |
| 设置页内 NavigationStack 工具栏齿轮按钮 | ✅ 完成 | 44b13ba |

---

## 二、功能矩阵

| 模块 | 已实现内容 | 备注 |
|------|-----------|------|
| **播放** | VLCKit（100+ 格式）+ AVPlayer 备用 | `#if canImport(MobileVLCKit)` 切换 |
| **转录** | WhisperKit（本地）/ Apple Speech（本地）/ OpenAI API（云端） | 播放器内可切换 |
| **模型管理** | 下载、切换、删除、进度 UI | WhisperKit 缓存于 `Documents/huggingface/` |
| **AI 对话** | Claude（流式）、OpenAI（流式）、Ollama、OpenAI 兼容 | SSE + 非流式回退 |
| **媒体库** | 导入文件/链接，搜索，5 种排序 | JSON 存 UserDefaults |
| **安全** | API 密钥存 Keychain | `kSecAttrAccessibleAfterFirstUnlock` |
| **本地化** | 英语 + 简体中文 | `zh-Hans.lproj`，~110 条字符串 |

---

## 三、已解决的技术债务与 Bug

| ID | 问题 | 修复方案 | Commit |
|----|------|---------|--------|
| TD-001 | 转录结果不保存 | PlayerViewModel 调用 `mediaLibraryService.updateItem()` | 25cdca9 |
| TD-002 | PlayerView 使用不可变 `let mediaItem` | 改读 `viewModel.mediaItem` | 25cdca9 |
| TD-003 | WhisperKit 无进度回调 | `TranscriptionCallback` 通过 `windowId` 估算 | 25cdca9 |
| TD-004 | API 密钥明文存 UserDefaults | 迁移到 `KeychainService` | 25cdca9 |
| TD-005 | 长转录无 Token 截断 | `buildSystemContext()` 80k 上限 + 截断提示 | 25cdca9 |
| TD-006 | VLCKit 被注释掉无法编译 | `#if canImport(MobileVLCKit)` 条件编译 | 25cdca9 |
| TD-007 | 无设置入口 | ContentView 工具栏齿轮按钮 | 25cdca9 |
| TD-008 | 真机崩溃：AVLinearPCMIsNonInterleaved | 分离 readerSettings/writerSettings | 5559bcf |
| TD-009 | AI 供应商设置退出后丢失 | 改用 providerID 引用，onAppear 重读 | 44b13ba |
| TD-010 | 转录成功后切 Chat 标签页内容消失 | `onTranscriptReady` 回调更新 `appState.activeMediaItem` | 当前 |
| TD-011 | WhisperKit 时间戳 Token 污染转录文本 | `stripTimestampTokens` 正则过滤 `<\|[\d.]+\|>` | 当前 |

---

## 四、当前已知局限

| 问题 | 影响 | 计划 |
|------|------|------|
| WhisperKit 模拟器为 CPU 模式 | 模拟器转录慢 | 预期行为，Neural Engine 仅真机 |
| 大模型下载需要 Wi-Fi | 用户体验 | 下载前显示大小警告（v1.1） |
| 转录文件不同步 iCloud | 重装丢数据 | v1.1 目标 |
| Apple Speech 无逐段时间戳（按词分块） | 时间轴不如 WhisperKit 精准 | 可接受，SFSpeechRecognizer 能力限制 |
| OpenAI API 上传大文件耗时较长 | 体验 | 可考虑切片上传（v1.2） |

---

## 五、路线图

### v1.1 — 云同步与分享
- [ ] iCloud Drive 同步转录 JSON 文件
- [ ] Share Sheet 扩展 — 从任意 App 触发转录
- [ ] 导出格式：SRT 字幕、JSON、纯文本
- [ ] 说话人分离（多说话人检测）

### v1.2 — 集成扩展
- [ ] 直接导入 YouTube / 播客流 URL
- [ ] Siri 快捷指令："转录最新导入"
- [ ] 主屏小组件：当前播放 + 快速转录
- [ ] CarPlay 音频支持

### v2.0 — 多平台
- [ ] iPad 多列布局（视频 + 转录 + 对话同屏）
- [ ] macOS（Catalyst）支持，含菜单栏控制
- [ ] 批量转录队列 + 后台处理
- [ ] 每条媒体独立配置 AI 系统提示词
- [ ] 领域词汇 Whisper 微调模型支持

---

## 六、构建说明

```bash
git clone https://github.com/ViffyGwaanl/VoiceAiTok.git && cd VoiceAiTok
pod install                        # 安装 MobileVLCKit 3.7
open VoiceTok.xcworkspace         # WhisperKit SPM 自动解析
# Xcode：设置 Development Team → 连接 iPhone → ⌘R
```

**xcodegen**（如需从 project.yml 重新生成 .xcodeproj）：
```bash
brew install xcodegen && xcodegen generate && pod install
```

**模拟器构建（无需签名）：**
```bash
xcodebuild build -workspace VoiceTok.xcworkspace -scheme VoiceTok \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

---

## 七、依赖版本表

| 包 | 版本 | 来源 |
|----|------|------|
| MobileVLCKit | 3.7.3 | CocoaPods |
| WhisperKit | 0.18.0 | SPM (argmaxinc/WhisperKit) |
| swift-transformers | 1.1.9 | SPM（传递依赖） |
| swift-crypto | 4.3.1 | SPM（传递依赖） |
| Xcode | 16+ | 必需 |
| iOS Deployment Target | 17.0 | 最低版本 |
