# VoiceTok — 项目状态与开发路线图

> **文档类型**：工程状态追踪 + 产品路线图  
> **最后更新**：2026-04-01  
> **当前版本**：v1.0.0（源码生成完毕，待 Xcode 工程集成）  
> **负责人**：独立开发者

---

## 一、当前版本状态（v1.0.0）

### 1.1 交付物清单

| 类别 | 文件 | 行数 | 状态 |
|------|------|------|------|
| **App 层** | `VoiceTokApp.swift` | 16 | ✅ 完成 |
| **App 层** | `AppState.swift` | 46 | ✅ 完成 |
| **数据模型** | `MediaItem.swift` | 153 | ✅ 完成 |
| **服务层** | `TranscriptionService.swift` | 225 | ✅ 完成 |
| **服务层** | `MediaPlayerService.swift` | 236 | ✅ 完成 |
| **服务层** | `ChatService.swift` | 240 | ✅ 完成 |
| **服务层** | `MediaLibraryService.swift` | 178 | ✅ 完成 |
| **ViewModel** | `PlayerViewModel.swift` | 115 | ✅ 完成 |
| **视图层** | `ContentView.swift` | 109 | ✅ 完成 |
| **视图层** | `LibraryView.swift` | 227 | ✅ 完成 |
| **视图层** | `PlayerView.swift` | 440 | ✅ 完成 |
| **视图层** | `ChatView.swift` | 278 | ✅ 完成 |
| **视图层** | `SettingsView.swift` | 210 | ✅ 完成 |
| **工具扩展** | `Extensions.swift` | 89 | ✅ 完成 |
| **资源** | `Info.plist` | 109 | ✅ 完成 |
| **配置** | `Package.swift` | 24 | ✅ 完成 |
| **配置** | `Podfile` | 20 | ✅ 完成 |
| **配置** | `.gitignore` | 25 | ✅ 完成 |
| **配置** | `README.md` | 35 | ✅ 完成 |
| **合计** | 19 个源文件 | ~4,789 行 | ✅ |

### 1.2 功能覆盖

| 功能模块 | 设计范围 | 实现状态 | 备注 |
|---------|---------|---------|------|
| 多格式媒体导入 | ✅ | ✅ | Files + URL 导入，15 种格式 |
| AVPlayer 播放 | ✅ | ✅ | 默认播放器，基础格式支持 |
| VLCKit 播放 | ✅ | ⚠️ 注释态 | 代码已写，需 pod install 后激活 |
| WhisperKit 初始化 | ✅ | ✅ | App 启动异步预热 |
| 音频提取（WAV 16kHz）| ✅ | ✅ | AVAssetReader pipeline |
| 语音转写（带时间戳）| ✅ | ✅ | WhisperKit 10 个模型可选 |
| 转写进度显示 | ✅ | ⚠️ 部分 | 状态文字更新，百分比始终 0% |
| 播放↔字幕实时同步 | ✅ | ✅ | Combine throttle 200ms |
| 字幕面板高亮+滚动 | ✅ | ✅ | ScrollViewReader 自动定位 |
| Claude API 对话 | ✅ | ✅ | system 参数独立 |
| OpenAI API 对话 | ✅ | ✅ | 兼容 OpenAI-compatible 接口 |
| Ollama 本地对话 | ✅ | ✅ | localhost:11434 |
| 快捷操作（总结/翻译）| ✅ | ✅ | 4 个预设操作 |
| 媒体库搜索+排序 | ✅ | ✅ | 5 种排序方式 |
| 转写稿导出（Markdown）| ✅ | ✅ | UIActivityViewController |
| 横竖屏自适应布局 | ✅ | ✅ | GeometryReader 55/45 分割 |
| 设置页（API/模型）| ✅ | ✅ | 18 种语言，10 种 Whisper 模型 |
| 后台播放 | ✅ | ✅ | AVAudioSession + Info.plist |
| 转写持久化（重启后）| ✅（设计）| ❌ 未完成 | 见技术债 #1 |
| API Key 安全存储 | ⚠️（UserDefaults）| ❌ 未完成 | 见技术债 #4 |
| 流式响应 | ✅（设计）| ❌ 未做 | v1.1.0 |
| Token 截断 | ✅（设计）| ❌ 未做 | v1.1.0 |

---

## 二、技术债追踪

### P0 — 阻断性问题（上线前必须修复）

#### TD-001：转写结果未持久化
- **文件**：`PlayerViewModel.swift:startTranscription()`
- **现象**：转写完成后关闭 App，下次打开转写结果消失
- **根因**：`updatedItem` 只更新了 `viewModel.mediaItem`，未调用 `mediaLibraryService.updateItem()`
- **修复**：
  ```swift
  // PlayerViewModel.swift — startTranscription() 中，transcript 写入后添加：
  await appState.mediaLibraryService.updateItem(updatedItem)
  // 需要将 mediaLibraryService 注入 PlayerViewModel
  ```

#### TD-002：PlayerView 转写完成后面板不刷新
- **文件**：`PlayerView.swift:transcriptPanel`
- **现象**：转写成功，但面板仍显示"Ready to Transcribe"
- **根因**：`transcriptPanel` 读取的是 `let mediaItem`（init 参数，不可变），而非 `viewModel.mediaItem`
- **修复**：将 `transcriptPanel` 中所有 `mediaItem.transcript` 替换为 `viewModel.mediaItem?.transcript`

### P1 — 高优先级（v1.0.1 内修复）

#### TD-003：WhisperKit 进度始终 0%
- **文件**：`TranscriptionService.swift:transcribe(audioURL:)`
- **现象**：转写过程中进度条文字始终为 "Transcribing... 0%"
- **修复**：使用 WhisperKit `DecodingOptions` 的进度回调（`progressCallback`）更新 state

#### TD-006：VLCKit 未激活
- **文件**：`MediaPlayerService.swift`（注释块）
- **步骤**：
  1. `pod install`（需 macOS + CocoaPods 1.4+）
  2. 取消 `VLCPlayerService` 类的注释
  3. `PlayerViewModel` 中将 `AVMediaPlayerService()` 替换为 `VLCPlayerService()`
  4. 添加 `import MobileVLCKit`

#### TD-007：SettingsView 无入口
- **文件**：`ContentView.swift`
- **现象**：`showSettings` state 声明但无按钮触发
- **修复**：在 TabView 的 `toolbar` 上添加齿轮按钮

### P2 — 中优先级（v1.1.0）

#### TD-004：API Key 明文存储
- **文件**：`SettingsView.swift` `@AppStorage("api_key")`
- **修复**：使用 `Security.framework` 的 `SecItemAdd` / `SecItemCopyMatching`

#### TD-005：超长转写稿无 Token 截断
- **文件**：`ChatService.swift:buildSystemContext()`
- **现象**：1 小时视频约 3000 段转写 ≈ 15 万字符 ≈ 3.7 万 tokens，可能超出 LLM 上限
- **修复**：参见 `02-VoiceTok-Coding-Patterns-TaskGuide.md` Task F 代码示例

---

## 三、开发路线图

### v1.0.1 — 紧急修复（目标：2026-04 内）

```
修复 TD-001  转写持久化
修复 TD-002  PlayerView 绑定刷新
修复 TD-003  WhisperKit 进度回调
修复 TD-006  VLCKit 激活
修复 TD-007  Settings 入口
```

**验收标准**：
- 转写后关闭 App 重启，转写结果仍然可见
- 转写完成后不需要重新选择文件即可看到字幕
- 转写进度实时更新（10% → 50% → 100%）
- MKV / AVI 文件可正常播放

---

### v1.1.0 — 安全与体验（目标：2026-Q2）

**功能**：
- [ ] API Key 迁移 Keychain
- [ ] Token 截断（80k token 上限 + 尾部 "... [截断]" 提示）
- [ ] Claude / OpenAI 流式响应（实时打字机输出）
- [ ] 单元测试套件（TranscriptSegment / ChatService / PlayerViewModel）

**测试目标**：核心逻辑覆盖率 ≥ 60%

---

### v1.2.0 — 功能扩展（目标：2026-Q3）

**功能**：
- [ ] **实时转写**：麦克风实时输入 → WhisperKit streaming → 字幕同步
- [ ] **字幕导出**：SRT / VTT / LRC 三种格式
- [ ] **网络流媒体**：VLCKit 播放 HLS / RTSP 流地址 + 网络缓存优化
- [ ] **批量转写队列**：多文件后台排队转写（OperationQueue）
- [ ] **多语言 UI**：App 界面中英双语（LocalizedString）

---

### v2.0.0 — 平台拓展（目标：2027）

**功能**：
- [ ] **Speaker Diarization**：`speakerLabel` 字段激活（Argmax Pro SDK）
- [ ] **RAG 上下文注入**：超长转写稿按语义检索相关片段注入 LLM，突破 token 限制
- [ ] **iCloud Drive 同步**：转写稿 + 对话历史跨设备
- [ ] **macOS / Catalyst**：SwiftUI multiplatform 适配
- [ ] **App Intents**：Siri Shortcuts 集成（「总结 VoiceTok 最近一个视频」）
- [ ] **watchOS 伴侣**：播放控制 + 转写进度 Mini

---

## 四、依赖与版本锁定

| 依赖 | 当前版本 | 引入方式 | 上次验证 |
|------|---------|---------|---------|
| MobileVLCKit | ~3.6 | CocoaPods | 2026-04-01 |
| WhisperKit | ≥0.9.0 | SPM | 2026-04-01 |
| Xcode | 15+ | 系统 | — |
| CocoaPods | 1.4+ | gem | — |
| iOS Deployment Target | 17.0 | Build Settings | — |

---

## 五、已知外部限制

| 限制 | 说明 |
|------|------|
| WhisperKit 模型首次需联网 | 下载后缓存于 `~/Library/Caches/huggingface/` |
| WhisperKit 模拟器极慢 | Neural Engine 不可用，仅用于 UI 调试 |
| MobileVLCKit 包体积 | 约 30-50MB，增加 App 包体积 |
| VLCKit 不支持 SPM | 必须 CocoaPods，不可替代 |
| Claude API context window | claude-sonnet-4: ~200k tokens（目前足够，极长视频除外）|
| Ollama 需同 Wi-Fi | iOS 通过 NSAllowsLocalNetworking 访问 Mac 上 Ollama |

---

*本文档为 VoiceTok 项目工程状态的权威追踪来源。每次 milestone 完成后应同步更新。*
