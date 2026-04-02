# VoiceTok — AI 开发指导完整合集

> **本文件是 VoiceTok 项目全部 AI 指导文档的合集版本**  
> 包含：主指导文档 + API 集成参考 + 代码模式与任务指南 + 完整源代码 + AI 提示模板 + 项目状态与路线图
> 
> 适用场景：直接将此文件整体提供给 AI 助手（特别是支持大上下文的模型如 Claude），即可让其全面理解项目并进行开发。
> 
> **实现状态**：✅ v1.0.0 全部 15 个 Swift 源文件已生成（2026-04-01）  
> **紧急待修复**：TD-001（转写持久化）、TD-002（PlayerView 绑定刷新）— 见文档末尾路线图  
> 总计约 5,000+ 行

---
---


# VoiceTok — AI 开发指导主文档

> **文档用途**：本文档是 VoiceTok iOS 项目的完整 AI 指导手册。将本文档提供给任何 AI 助手（Claude、GPT、Copilot 等），即可让其全面理解项目架构、代码规范、技术决策，并能正确地进行代码开发、review 和问题排查。
>
> **最后更新**：2026-04-01  
> **项目版本**：1.0.0  
> **目标平台**：iOS 17+ / iPadOS 17+

---

## 一、项目定位与核心理念

### 1.1 产品定义

VoiceTok 是一个 iOS 原生应用，实现三大核心能力的融合：

1. **通用媒体播放** — 通过 VLCKit 支持 100+ 音视频格式（MKV、AVI、FLAC 等系统原生不支持的格式）
2. **端侧语音转写** — 通过 WhisperKit 在设备本地运行 OpenAI Whisper 模型，将音视频的语音内容转为带时间戳的文本
3. **AI 智能对话** — 将转写文稿注入 LLM 上下文，让用户可以和 AI 就媒体内容进行深度交互（总结、问答、翻译、笔记生成）

### 1.2 设计灵感

灵感来源于 PaperTok Reader 项目的理念 — 将被动阅读转化为主动交互。PaperTok 对论文 PDF 做的事，VoiceTok 对音视频内容做同样的事。

### 1.3 关键差异化

- **全离线转写**：WhisperKit 在 Apple Neural Engine 上本地推理，音频数据不离开设备
- **格式通吃**：VLCKit 支持几乎所有音视频格式，不受 iOS 原生 AVPlayer 格式限制
- **多 LLM 后端**：支持 Claude、OpenAI、Ollama（完全本地），用户可自由选择

---

## 二、技术栈总览

| 组件 | 技术 | 版本 | 引入方式 | 许可证 |
|------|------|------|---------|--------|
| UI 框架 | SwiftUI | iOS 17+ | 系统内置 | Apple |
| 媒体播放（主） | MobileVLCKit | ~3.6 | CocoaPods | LGPLv2.1 |
| 媒体播放（回退） | AVFoundation / AVPlayer | 系统 | 系统内置 | Apple |
| 语音转写 | WhisperKit | 0.9+ | Swift Package Manager | MIT |
| AI 对话 | Claude API / OpenAI API / Ollama | - | URLSession 运行时 | 各自 |
| 持久化 | UserDefaults + FileManager | 系统 | 系统内置 | Apple |
| 响应式 | Combine | 系统 | 系统内置 | Apple |

### 为什么用两套包管理器？

- **CocoaPods 用于 VLCKit**：VLCKit 是 C/ObjC 混编的大型框架，尚未官方支持 SPM
- **SPM 用于 WhisperKit**：WhisperKit 是纯 Swift 包，SPM 是官方推荐方式
- 两者通过 `.xcworkspace` 共存，Xcode 自动处理链接

---

## 三、项目结构

```
VoiceTok/
├── Package.swift                        # SPM 清单（WhisperKit 依赖）
├── Podfile                              # CocoaPods 清单（MobileVLCKit）
├── README.md                            # 项目说明
├── .gitignore
│
├── VoiceTok/
│   ├── App/                             # ===== 应用入口 =====
│   │   ├── VoiceTokApp.swift           # @main，WindowGroup，注入 AppState
│   │   └── AppState.swift              # @MainActor 全局状态容器
│   │
│   ├── Models/                          # ===== 数据模型 =====
│   │   └── MediaItem.swift             # MediaItem, Transcript, TranscriptSegment,
│   │                                   # ChatMessage, ChatRole, MediaType,
│   │                                   # TranscriptionState, PlaybackState
│   │
│   ├── Services/                        # ===== 业务服务 =====
│   │   ├── TranscriptionService.swift  # WhisperKit 封装（初始化/转写/音频提取/模型切换）
│   │   ├── MediaPlayerService.swift    # 播放器协议 + AVPlayer 实现 + VLCKit 实现（注释态）
│   │   ├── ChatService.swift           # LLM 对话（Claude/OpenAI/Ollama 三后端）
│   │   └── MediaLibraryService.swift   # 文件导入/存储/缩略图/持久化
│   │
│   ├── ViewModels/                      # ===== 视图模型 =====
│   │   └── PlayerViewModel.swift       # 播放 ↔ 转写同步协调器
│   │
│   ├── Views/                           # ===== SwiftUI 视图 =====
│   │   ├── ContentView.swift           # 主 TabView 容器
│   │   ├── SettingsView.swift          # 设置页（API/模型/播放/数据）
│   │   ├── Library/
│   │   │   └── LibraryView.swift       # 媒体库（导入/列表/搜索/排序）
│   │   ├── Player/
│   │   │   └── PlayerView.swift        # 播放器 + 转写面板（横竖屏自适应）
│   │   └── Chat/
│   │       └── ChatView.swift          # AI 对话界面（气泡/快捷操作/输入栏）
│   │
│   ├── Extensions/                      # ===== 工具扩展 =====
│   │   └── Extensions.swift            # View/Color/String/Date/URL 扩展 + HapticFeedback
│   │
│   └── Resources/                       # ===== 资源 =====
│       └── Info.plist                  # 权限声明/后台模式/文件类型关联
```

---

## 四、架构设计

### 4.1 整体架构模式

采用 **MVVM + Service Layer** 分层架构：

```
┌─────────────────────────────────────┐
│          Views (SwiftUI)            │  纯展示 + 用户交互
├─────────────────────────────────────┤
│        ViewModels (协调器)           │  状态管理 + 业务编排
├─────────────────────────────────────┤
│         Services (服务层)            │  框架封装 + API 调用
├─────────────────────────────────────┤
│          Models (数据层)             │  数据结构定义
├─────────────────────────────────────┤
│    Frameworks (VLCKit/WhisperKit)   │  底层引擎
└─────────────────────────────────────┘
```

### 4.2 依赖注入

`AppState` 作为全局依赖容器，通过 `@EnvironmentObject` 注入到视图树：

```swift
@main
struct VoiceTokApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
```

`AppState` 持有所有 Service 实例：
- `transcriptionService: TranscriptionService`
- `chatService: ChatService`
- `mediaLibraryService: MediaLibraryService`

### 4.3 线程模型

- **所有 Service 和 ViewModel 标记 `@MainActor`**：确保 `@Published` 属性在主线程更新
- **耗时操作使用 `async/await`**：WhisperKit 转写、音频提取、API 调用
- **Combine 用于播放时间同步**：`player.$currentTime` → `throttle` → `updateActiveSegment()`

### 4.4 播放器抽象

通过 Protocol 实现播放器可切换：

```swift
protocol MediaPlayerProtocol: ObservableObject {
    var playbackState: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Float { get set }
    var playbackRate: Float { get set }
    func load(url: URL) async
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func togglePlayPause()
}
```

默认实现：`AVMediaPlayerService`（AVFoundation）  
生产实现：`VLCPlayerService`（MobileVLCKit，代码已写好，注释状态）

切换方式：在 `PlayerViewModel` 中将 `AVMediaPlayerService` 替换为 `VLCPlayerService`

---

## 五、核心数据流

### 5.1 媒体导入流程

```
用户选择文件 (fileImporter / URL)
    │
    ▼
MediaLibraryService.importMedia(from:)
    ├── startAccessingSecurityScopedResource()
    ├── copyItem 到 Documents/VoiceTok/
    ├── AVURLAsset.load(.duration) 读取时长
    ├── AVAssetImageGenerator 生成缩略图 (仅视频)
    ├── 构建 MediaItem 结构体
    ├── 插入 mediaItems 数组头部
    └── JSONEncoder → UserDefaults 持久化
```

### 5.2 转写流程

```
用户点击「开始转写」
    │
    ▼
TranscriptionService.transcribeMedia(at:)
    ├── state = .extractingAudio
    ├── extractAudio(from:)
    │   ├── AVAssetReader + AVAssetReaderTrackOutput
    │   ├── 输出格式: 16kHz, 单声道, 16-bit PCM
    │   ├── AVAssetWriter 写入临时 .wav 文件
    │   └── 返回 WAV URL
    │
    ├── state = .transcribing(progress:)
    ├── WhisperKit.transcribe(audioPath:, decodeOptions:)
    │   ├── DecodingOptions(language:, task:, wordTimestamps:)
    │   └── Neural Engine 推理
    │
    ├── 结果映射
    │   ├── result.segments → [TranscriptSegment]
    │   │   每段包含: startTime, endTime, text
    │   └── 拼接 fullText
    │
    └── 返回 Transcript 结构体
        ├── segments: [TranscriptSegment]
        ├── fullText: String
        ├── language: String?
        └── dateCreated: Date
```

### 5.3 播放-转写同步

```
player.$currentTime                    // AVPlayer 0.1s 周期发送
    │
    ▼
.throttle(200ms)                       // 降频避免过度计算
    │
    ▼
updateActiveSegment(for: time)         // 二分查找匹配段落
    │  segments.lastIndex { $0.startTime <= time && $0.endTime >= time }
    │
    ▼
@Published activeSegmentIndex          // 驱动 UI 更新
    ├── TranscriptListView 行背景高亮 (orange.opacity(0.15))
    ├── ScrollViewReader.scrollTo(segmentId, anchor: .center)
    └── TranscriptSegmentRow 文字加粗 + 时间戳变色
```

### 5.4 AI 对话上下文注入

```
转写完成
    │
    ▼
ChatService.setTranscript(transcript)
    │
    ▼
构建 System Prompt:
    ┌──────────────────────────────────────────┐
    │ "You are VoiceTok AI..."                 │  ← 角色定义
    │                                          │
    │ === MEDIA TRANSCRIPT ===                 │
    │ Language: zh                             │
    │                                          │
    │ [00:00 → 00:05] 大家好，欢迎来到...      │  ← 完整转写稿
    │ [00:05 → 00:12] 今天我们要讨论的是...     │     含每段时间戳
    │ [00:12 → 00:20] 第一个要点是...           │
    │ ...                                      │
    │ === END TRANSCRIPT ===                   │
    │                                          │
    │ 120 segments, total: 45:30              │  ← 元数据摘要
    └──────────────────────────────────────────┘
    │
    ▼
用户发送消息 → messages 数组（含 system + 历史）→ LLM API
    │
    ▼
AI 回复引用具体时间戳段落
```

---

## 六、各文件详细说明

### 6.1 App/VoiceTokApp.swift

**职责**：应用入口  
**关键点**：
- `@main` 标记
- 创建 `AppState` 为 `@StateObject`
- 通过 `.environmentObject(appState)` 注入全局
- `.preferredColorScheme(.dark)` 默认深色主题

### 6.2 App/AppState.swift

**职责**：全局状态容器 + 依赖注入源  
**关键属性**：
- `selectedTab: AppTab` — 当前 Tab（.library / .player / .chat）
- `activeMediaItem: MediaItem?` — 当前选中的媒体项
- `isTranscribing: Bool` — 全局转写状态标记
- `whisperKitReady: Bool` — WhisperKit 初始化完成标记

**初始化行为**：
```swift
init() {
    Task { await prepareWhisperKit() }  // 启动即异步初始化 WhisperKit
}
```

### 6.3 Models/MediaItem.swift

**定义的类型**：

| 类型 | 用途 | 协议 |
|------|------|------|
| `MediaItem` | 媒体文件元数据 | Identifiable, Codable, Hashable |
| `MediaType` | .video / .audio | Codable |
| `Transcript` | 转写结果容器 | Codable, Hashable |
| `TranscriptSegment` | 单个转写段落（含时间戳） | Identifiable, Codable, Hashable |
| `ChatMessage` | 对话消息 | Identifiable, Codable, Hashable |
| `ChatRole` | .user / .assistant / .system | Codable |
| `TranscriptionState` | 转写状态机 | Equatable |
| `PlaybackState` | 播放状态 | — |

**TranscriptSegment 关键字段**：
```swift
struct TranscriptSegment {
    let id: UUID
    var startTime: TimeInterval    // 段落开始时间（秒）
    var endTime: TimeInterval      // 段落结束时间（秒）
    var text: String               // 转写文本
    var speakerLabel: String?      // 预留说话人标签（未来功能）
}
```

### 6.4 Services/TranscriptionService.swift

**职责**：WhisperKit 完整封装  
**核心方法**：

| 方法 | 功能 |
|------|------|
| `initialize()` | 初始化 WhisperKit，下载/加载模型 |
| `transcribe(audioURL:)` | 直接转写音频文件 |
| `transcribeMedia(at:)` | 从视频提取音频后转写（完整流程） |
| `extractAudio(from:)` | AVAssetReader → 16kHz WAV |
| `convertToWav(asset:outputURL:)` | PCM 格式转换核心逻辑 |
| `switchModel(to:)` | 热切换 Whisper 模型 |

**音频提取参数**（WhisperKit 要求）：
```swift
AVSampleRateKey: 16000.0          // 16kHz 采样率
AVNumberOfChannelsKey: 1           // 单声道
AVLinearPCMBitDepthKey: 16         // 16-bit
AVLinearPCMIsFloatKey: false       // 整数 PCM
```

**可用模型列表**：
```swift
["tiny", "tiny.en", "base", "base.en", "small", "small.en",
 "medium", "medium.en", "large-v3", "distil-large-v3"]
```

### 6.5 Services/MediaPlayerService.swift

**职责**：媒体播放抽象  
**设计模式**：Protocol + 双实现

- `MediaPlayerProtocol` — 统一接口
- `AVMediaPlayerService` — 基于 AVFoundation（默认启用）
- `VLCPlayerService` — 基于 MobileVLCKit（注释态，取消注释启用）

**AVPlayer 时间观察**：
```swift
let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
    self.currentTime = time.seconds
}
```

**切换到 VLCKit 的步骤**：
1. `Podfile` 中 `pod 'MobileVLCKit'` 已声明
2. 运行 `pod install`
3. 取消 `VLCPlayerService` 类的注释
4. 在 `PlayerViewModel` 中将 `AVMediaPlayerService` 替换为 `VLCPlayerService`
5. 添加 `import MobileVLCKit`

### 6.6 Services/ChatService.swift

**职责**：LLM 对话核心  
**支持的后端**：

| 后端 | API 端点 | 认证方式 | 特点 |
|------|---------|---------|------|
| Claude | `api.anthropic.com/v1/messages` | x-api-key | 默认推荐 |
| OpenAI | `api.openai.com/v1/chat/completions` | Bearer token | 兼容接口 |
| Ollama | `localhost:11434/api/chat` | 无需认证 | 完全离线 |

**上下文注入策略**：
- System prompt 包含完整转写稿（每段带时间戳）
- 每次对话发送完整 messages 历史
- Claude API 使用独立的 `system` 参数（不放在 messages 中）
- OpenAI/Ollama 使用 `role: "system"` 消息

**快捷操作方法**：
```swift
func summarize()                    // 总结全文
func extractKeyTopics()             // 提取关键主题
func generateNotes()                // 生成学习笔记
func translateSummary(to:)          // 翻译摘要
```

### 6.7 Services/MediaLibraryService.swift

**职责**：文件生命周期管理  
**支持的文件格式**：

```swift
// 视频
"mp4", "m4v", "mov", "avi", "mkv", "ts", "flv", "wmv", "webm"
// 音频
"mp3", "m4a", "wav", "aiff", "flac", "ogg", "wma", "aac"
```

**持久化策略**：
- 媒体文件 → `Documents/VoiceTok/` 目录（沙盒内）
- 缩略图 → `Documents/VoiceTok/thumb_xxx.jpg`
- 元数据 → UserDefaults key `"voicetok_media_library"`（JSON 编码）
- 启动时验证文件存在性，自动清理无效条目

### 6.8 ViewModels/PlayerViewModel.swift

**职责**：播放 ↔ 转写 协调中枢  
**核心逻辑**：

```swift
// Combine 管线：播放时间 → 活跃段落索引
player.$currentTime
    .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
    .sink { time in self.updateActiveSegment(for: time) }

// 段落匹配算法
func updateActiveSegment(for time: TimeInterval) {
    activeSegmentIndex = segments.lastIndex {
        $0.startTime <= time && $0.endTime >= time
    }
}
```

**协调职责**：
1. 加载媒体 → 初始化播放器 + 检查已有转写
2. 触发转写 → 转发 TranscriptionService 状态
3. 转写完成 → 更新 MediaItem + 设置 ChatService 上下文
4. 播放时间 → 计算活跃段落 → 驱动 UI 同步
5. 段落点击 → player.seek() + play()

### 6.9 Views/ContentView.swift

**职责**：主容器  
**结构**：TabView with 3 tabs

```swift
TabView(selection: $appState.selectedTab) {
    LibraryView()           // Tab 1: 媒体库
    PlayerContainerView()   // Tab 2: 播放器（需要 activeMediaItem）
    ChatContainerView()     // Tab 3: AI 对话（需要 transcript）
}
```

**空状态处理**：
- 无选中媒体 → `EmptyPlayerView`
- 无转写结果 → `EmptyChatView`

### 6.10 Views/Library/LibraryView.swift

**职责**：媒体库管理  
**功能**：
- `fileImporter` 系统文件选择器（支持多选）
- URL 输入 alert
- 搜索栏 `.searchable()`
- 排序菜单（日期/标题/时长）
- 左滑删除 `.swipeActions()`
- 点击 → 设置 `activeMediaItem` + 切换到 Player Tab

### 6.11 Views/Player/PlayerView.swift

**职责**：核心播放界面  
**布局策略**：

```
竖屏 (portrait):          横屏 (landscape):
┌──────────────┐          ┌────────┬──────────┐
│  Video/Audio │          │ Video  │ Transcript│
│   Player     │          │ Player │  Panel    │
├──────────────┤          │        │           │
│  Controls    │          │Controls│           │
├──────────────┤          └────────┴──────────┘
│  Transcript  │               55%      45%
│   Panel      │
└──────────────┘
```

**转写面板组件层次**：
```
TranscriptPanel
├── 头部 (Label + 语言标签 + 段落计数)
├── TranscriptListView (if 有转写)
│   └── TranscriptSegmentRow × N
│       ├── 时间戳 (monospaced)
│       ├── 竖线分隔 (active 时变橙色)
│       └── 文本 (active 时加粗)
└── transcriptionPrompt (if 无转写)
    └── 状态显示 + 开始按钮 / 进度 / 错误
```

### 6.12 Views/Chat/ChatView.swift

**职责**：AI 对话界面  
**组件**：
- `ChatBubble` — 消息气泡（用户右对齐橙色，AI 左对齐灰色）
- `QuickActionButton` — 快捷操作胶囊按钮
- `TypingIndicator` — 三点跳动动画
- 底部输入栏 — TextField + 发送按钮 + 快捷操作切换

### 6.13 Views/SettingsView.swift

**职责**：应用设置  
**配置项**：

| 分组 | 设置项 | 存储方式 |
|------|--------|---------|
| AI Chat | Provider / API Key / Base URL / Model | @AppStorage |
| WhisperKit | Model / Word Timestamps / Auto-transcribe / Language | @AppStorage |
| Playback | Background / Default Rate / Skip Interval | @AppStorage |
| Data | Clear Transcripts / Clear All | 直接操作 |

### 6.14 Extensions/Extensions.swift

**提供的扩展**：

| 扩展目标 | 功能 |
|---------|------|
| `View` | `.if()` 条件修饰符, `hideKeyboard()` |
| `Color` | `.voiceTokOrange`, `.voiceTokDark`, `.voiceTokSurface` |
| `String` | `.truncated(to:)`, `.cleaned` |
| `Date` | `.relativeFormatted` |
| `TimeInterval` | `.formattedDuration` |
| `URL` | `.isMediaFile`, `.isAudioOnly` |
| `HapticFeedback` | `.light()`, `.medium()`, `.success()`, `.error()` |

### 6.15 Resources/Info.plist

**声明的权限**：
- `NSMicrophoneUsageDescription` — 实时转写（未来功能）
- `NSSpeechRecognitionUsageDescription` — 语音识别
- `NSPhotoLibraryUsageDescription` — 导入媒体
- `UIBackgroundModes: audio` — 后台播放

**文件类型关联**：
- `public.movie`, `public.mpeg-4`, `com.apple.quicktime-movie`, `public.avi`
- `public.audio`, `public.mp3`, `com.apple.m4a-audio`, `public.aiff-audio`

**网络安全**：
- `NSAllowsLocalNetworking: true` — 允许连接本地 Ollama 服务器

---

## 七、代码规范

### 7.1 命名规范

| 类别 | 规范 | 示例 |
|------|------|------|
| 类型 | UpperCamelCase | `MediaItem`, `TranscriptionService` |
| 属性/方法 | lowerCamelCase | `currentTime`, `startTranscription()` |
| 枚举值 | lowerCamelCase | `.playing`, `.transcribing(progress:)` |
| 常量 | lowerCamelCase | `storageKey`, `availableModels` |
| 文件名 | 与主类型同名 | `MediaItem.swift`, `ChatService.swift` |

### 7.2 架构规范

- **View 不直接持有 Service**：通过 ViewModel 或 EnvironmentObject 间接访问
- **Service 之间不互相引用**：通过 ViewModel 协调
- **所有 @Published 属性更新在主线程**：`@MainActor` 标记
- **异步操作使用 async/await**：不使用 completion handler
- **错误处理使用 LocalizedError**：每个 Service 定义自己的错误枚举

### 7.3 SwiftUI 规范

- 视图体积控制：单个 View 不超过 200 行，超出拆分为子组件
- 使用 `@ViewBuilder` 标记条件视图属性
- 动画使用 `.animation(.easeInOut, value:)` 绑定值变化
- 列表使用 `ForEach` + `Identifiable`，不使用索引

### 7.4 注释规范

```swift
// MARK: - 区块分隔
/// 文档注释用于 public API
// 行内注释用于实现细节
```

---

## 八、构建与配置

### 8.1 环境要求

- macOS 14+
- Xcode 15+
- CocoaPods 1.4+ (`gem install cocoapods`)
- 物理 iOS 17+ 设备（WhisperKit 需要 Neural Engine；模拟器可运行但转写极慢）

### 8.2 构建步骤

```bash
git clone <repo-url> VoiceTok && cd VoiceTok
pod install                           # 安装 VLCKit
# Apple Silicon Mac: arch -x86_64 pod install
open VoiceTok.xcworkspace             # 打开 workspace（非 .xcodeproj）
# Xcode: File → Add Package → https://github.com/argmaxinc/WhisperKit.git
# 选择 Team → Build & Run
```

### 8.3 关键 Build Settings

| 设置 | 值 | 原因 |
|------|---|------|
| iOS Deployment Target | 17.0 | SwiftUI Observable 等新 API |
| Swift Language Version | 5.9 | async/await, Macro 支持 |
| Enable Bitcode | NO | VLCKit 不支持 Bitcode |
| Other Linker Flags | -ObjC | VLCKit ObjC 类别加载 |

---

## 九、扩展指南

### 9.1 添加新的 LLM 后端

1. 在 `ChatService.APIProvider` 枚举添加新值
2. 在 `callLLM()` switch 中添加分支
3. 实现具体的 API 调用方法（参考 `callClaude()`）
4. 在 `SettingsView` 的 Picker 中添加选项

### 9.2 添加实时转写

```swift
// WhisperKit 支持流式转写
// 在 TranscriptionService 中添加:
func startRealtimeTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>) async {
    // 使用 WhisperKit 的 streaming API
}
```

### 9.3 添加 Speaker Diarization

`TranscriptSegment` 已预留 `speakerLabel: String?` 字段，可通过 Argmax Pro SDK 或 pyannote 集成。

### 9.4 添加字幕导出

```swift
func exportSRT(transcript: Transcript) -> String {
    transcript.segments.enumerated().map { i, seg in
        "\(i+1)\n\(formatSRTTime(seg.startTime)) --> \(formatSRTTime(seg.endTime))\n\(seg.text)\n"
    }.joined(separator: "\n")
}
```

---

## 十、安全与隐私

| 关注点 | 处理方式 |
|--------|---------|
| 音频数据 | WhisperKit 全程本地推理，音频不离开设备 |
| API 密钥 | 存储在 @AppStorage（UserDefaults）；生产环境应迁移至 Keychain |
| 对话数据 | 完整转写稿发送至选定的 LLM API；Ollama 可完全离线 |
| 文件存储 | 沙盒 Documents 目录，其他应用无法访问 |
| 网络请求 | 仅在调用 LLM API 时发起 HTTPS 请求 |

---

## 十一、已知限制与注意事项

1. **WhisperKit 模型首次下载需要网络**：之后缓存在本地
2. **VLCKit 体积较大**：MobileVLCKit 约 30-50MB，会增加包体积
3. **长视频转写耗时**：1小时视频在 iPhone 15 Pro 上用 base 模型约需 3 分钟
4. **Token 上限**：对于很长的转写稿，可能超出 LLM 的 context window，需要截断策略
5. **模拟器限制**：WhisperKit 在模拟器上使用 CPU 推理，速度极慢

---

*本文档由 VoiceTok 项目自动生成，可直接提供给 AI 助手作为开发指导。*

---
---


# VoiceTok — API 集成参考文档

> 本文档详细说明 VoiceTok 中所有外部 API 和框架的集成方式、调用协议、参数格式，供 AI 理解和生成正确的集成代码。

---

## 一、WhisperKit 集成

### 1.1 依赖引入

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
]
```

### 1.2 初始化

```swift
import WhisperKit

let config = WhisperKitConfig(
    model: "base",        // 模型名称
    verbose: false,        // 关闭调试日志
    prewarm: true          // 预热模型（加速首次推理）
)
let whisperKit = try await WhisperKit(config)
```

**模型自动下载**：WhisperKit 会自动从 HuggingFace (`argmaxinc/whisperkit-coreml`) 下载指定模型的 CoreML 版本并缓存到本地。

### 1.3 转写调用

```swift
let options = DecodingOptions(
    language: nil,              // nil = 自动检测语言
    task: .transcribe,          // .transcribe 或 .translate（翻译为英语）
    wordTimestamps: true        // 启用词级时间戳
)

guard let results = try await whisperKit.transcribe(
    audioPath: audioURL.path,   // 音频文件路径（推荐 WAV 16kHz）
    decodeOptions: options
) else { throw TranscriptionError.transcriptionFailed }
```

### 1.4 结果结构

```swift
// results 类型: [TranscriptionResult]
for result in results {
    result.text        // String — 完整文本
    result.language    // String? — 检测到的语言代码
    result.segments    // [TranscriptionSegment]
    
    for segment in result.segments {
        segment.start  // Float — 开始时间（秒）
        segment.end    // Float — 结束时间（秒）
        segment.text   // String — 段落文本
    }
}
```

### 1.5 音频输入要求

WhisperKit 期望的音频格式：
- **采样率**：16,000 Hz（必须）
- **声道**：单声道（Mono）
- **位深**：16-bit PCM
- **格式**：WAV（推荐）或其他 AVFoundation 支持的格式

如果输入是视频文件，需要先提取音频并转换格式（见 `TranscriptionService.convertToWav()`）。

### 1.6 支持的 Whisper 模型

| 模型 | CoreML 文件大小 | iPhone 15 Pro 速率 | 适用场景 |
|------|----------------|-------------------|---------|
| tiny | ~40MB | ~30× 实时 | 快速预览、测试 |
| tiny.en | ~40MB | ~30× 实时 | 纯英语内容 |
| base | ~75MB | ~20× 实时 | **默认推荐** |
| base.en | ~75MB | ~20× 实时 | 纯英语、速度优先 |
| small | ~250MB | ~10× 实时 | 多数内容 |
| small.en | ~250MB | ~10× 实时 | 纯英语、质量优先 |
| medium | ~750MB | ~4× 实时 | 专业级转写 |
| medium.en | ~750MB | ~4× 实时 | 英语最佳性价比 |
| large-v3 | ~1.5GB | ~2× 实时 | 最高准确度 |
| distil-large-v3 | ~750MB | ~6× 实时 | 准确度/速度最佳平衡 |

---

## 二、MobileVLCKit 集成

### 2.1 依赖引入

```ruby
# Podfile
pod 'MobileVLCKit', '~> 3.6'
```

### 2.2 播放器初始化

```swift
import MobileVLCKit

let mediaPlayer = VLCMediaPlayer()
mediaPlayer.delegate = self

// 设置渲染视图
let videoView = UIView()
mediaPlayer.drawable = videoView
```

### 2.3 加载媒体

```swift
let media = VLCMedia(url: fileURL)
media.addOptions([
    "network-caching": 300,    // 网络缓存 ms
    "file-caching": 500        // 文件缓存 ms
])
mediaPlayer.media = media

// 获取时长（需要先解析）
media.parse(withOptions: VLCMediaParsingOptions(VLCMediaParseLocal))
// 等待解析完成后
let durationMs = media.length.intValue  // 毫秒
```

### 2.4 播放控制

```swift
mediaPlayer.play()
mediaPlayer.pause()
mediaPlayer.stop()

// 跳转（position 是 0.0-1.0 的浮点数）
mediaPlayer.position = Float(targetTime / totalDuration)

// 变速
mediaPlayer.rate = 1.5

// 音量（0-200）
mediaPlayer.audio?.volume = 100
```

### 2.5 Delegate 回调

```swift
extension VLCPlayerService: VLCMediaPlayerDelegate {
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let currentMs = mediaPlayer.time.intValue  // 当前时间（毫秒）
    }
    
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch mediaPlayer.state {
        case .playing:   // 播放中
        case .paused:    // 暂停
        case .stopped:   // 停止
        case .buffering: // 缓冲中
        case .error:     // 错误
        default: break
        }
    }
}
```

### 2.6 支持的格式（部分）

视频容器：MP4, MKV, AVI, MOV, FLV, WMV, WebM, TS, M2TS, 3GP, OGV  
视频编解码：H.264, H.265/HEVC, VP8, VP9, AV1, MPEG-2, MPEG-4, Theora  
音频容器：MP3, M4A, WAV, FLAC, OGG, WMA, AAC, AIFF, APE  
音频编解码：AAC, MP3, Vorbis, Opus, FLAC, AC3, DTS, PCM  
字幕：SRT, ASS, SSA, VTT, PGS, DVB

---

## 三、Claude API (Anthropic) 集成

### 3.1 请求格式

```
POST https://api.anthropic.com/v1/messages

Headers:
  Content-Type: application/json
  x-api-key: <API_KEY>
  anthropic-version: 2023-06-01
```

### 3.2 请求体

```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 2048,
  "system": "You are VoiceTok AI... [完整转写稿]",
  "messages": [
    {"role": "user", "content": "请总结这段视频的主要内容"},
    {"role": "assistant", "content": "...之前的回复..."},
    {"role": "user", "content": "第15分钟谈到了什么？"}
  ]
}
```

**注意**：Claude API 的 `system` 是独立顶层参数，不放在 `messages` 数组中。

### 3.3 响应格式

```json
{
  "id": "msg_xxx",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "AI 的回复内容..."
    }
  ],
  "model": "claude-sonnet-4-20250514",
  "usage": {
    "input_tokens": 1500,
    "output_tokens": 300
  }
}
```

**提取文本**：`response.content[0].text`

### 3.4 Swift 实现要点

```swift
var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

// system 和 messages 分离
let body: [String: Any] = [
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 2048,
    "system": systemPromptWithTranscript,     // 含转写稿的 system prompt
    "messages": conversationMessages           // 不含 system role
]
```

---

## 四、OpenAI API 集成

### 4.1 请求格式

```
POST https://api.openai.com/v1/chat/completions

Headers:
  Content-Type: application/json
  Authorization: Bearer <API_KEY>
```

### 4.2 请求体

```json
{
  "model": "gpt-4",
  "max_tokens": 2048,
  "temperature": 0.7,
  "messages": [
    {"role": "system", "content": "You are VoiceTok AI... [转写稿]"},
    {"role": "user", "content": "请总结"},
    {"role": "assistant", "content": "..."},
    {"role": "user", "content": "下一个问题"}
  ]
}
```

**注意**：OpenAI 的 system prompt 是 messages 数组的第一条消息。

### 4.3 响应提取

```swift
let text = response["choices"][0]["message"]["content"] as? String
```

---

## 五、Ollama (本地 LLM) 集成

### 5.1 请求格式

```
POST http://localhost:11434/api/chat

Headers:
  Content-Type: application/json
```

### 5.2 请求体

```json
{
  "model": "llama3.2",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "stream": false
}
```

### 5.3 响应提取

```swift
let text = response["message"]["content"] as? String
```

### 5.4 Info.plist 配置

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

必须声明 `NSAllowsLocalNetworking` 才能访问 `localhost`。

---

## 六、AVFoundation 音频提取

### 6.1 从视频提取音频为 WAV

```swift
// 1. 创建 Reader
let asset = AVURLAsset(url: videoURL)
let reader = try AVAssetReader(asset: asset)
let audioTrack = try await asset.loadTracks(withMediaType: .audio).first!

// 2. 配置输出格式（WhisperKit 要求）
let outputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 16000.0,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false
]

// 3. 创建 ReaderOutput + Writer
let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
reader.add(readerOutput)

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
writer.add(writerInput)

// 4. 开始转换
reader.startReading()
writer.startWriting()
writer.startSession(atSourceTime: .zero)

// 5. 拷贝数据
writerInput.requestMediaDataWhenReady(on: queue) {
    while writerInput.isReadyForMoreMediaData {
        if let buffer = readerOutput.copyNextSampleBuffer() {
            writerInput.append(buffer)
        } else {
            writerInput.markAsFinished()
            writer.finishWriting { /* 完成 */ }
            return
        }
    }
}
```

---

*本文档覆盖 VoiceTok 所有外部 API 和框架的集成细节，可作为 AI 编码参考。*

---
---


# VoiceTok — 代码模式与 AI 任务指南

> 本文档整理了项目中所有已使用的代码模式、SwiftUI 惯用法、以及 AI 在接手常见开发任务时应遵循的具体步骤。

---

## 一、已使用的核心代码模式

### 1.1 MVVM + Service 注入模式

```
View (SwiftUI)
  │ @EnvironmentObject
  ▼
AppState (@MainActor, ObservableObject)
  │ 持有
  ▼
Services (@MainActor, ObservableObject)
  │ 封装
  ▼
Frameworks (WhisperKit, AVFoundation, URLSession)
```

**规则**：
- View 只通过 `@EnvironmentObject` 或构造参数获取依赖
- ViewModel 通过构造参数注入 Service
- Service 之间不互相引用
- 所有状态变更通过 `@Published` 属性驱动 UI

### 1.2 Protocol 抽象模式（播放器）

```swift
protocol MediaPlayerProtocol: ObservableObject {
    var playbackState: PlaybackState { get }
    var currentTime: TimeInterval { get }
    // ... 统一接口
}

// 实现 A: AVFoundation
final class AVMediaPlayerService: ObservableObject, MediaPlayerProtocol { ... }

// 实现 B: VLCKit
final class VLCPlayerService: NSObject, ObservableObject, MediaPlayerProtocol { ... }
```

**使用方式**：在 ViewModel 中指定具体实现类型（非泛型，因 SwiftUI 需要具体类型）。

### 1.3 Async/Await 异步模式

所有耗时操作使用 Swift Concurrency：

```swift
// Service 方法
func transcribe(audioURL: URL) async throws -> Transcript

// View 中调用
Button("开始") {
    Task { await viewModel.startTranscription() }
}

// ViewModel 中转发
func startTranscription() async {
    do {
        let transcript = try await transcriptionService.transcribeMedia(at: url)
    } catch {
        transcriptionState = .failed(error.localizedDescription)
    }
}
```

### 1.4 Combine 管线模式（时间同步）

```swift
player.$currentTime
    .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
    .sink { [weak self] time in
        self?.updateActiveSegment(for: time)
    }
    .store(in: &cancellables)
```

**为什么用 Combine 而不是 async**：播放时间是连续流式数据，Combine 的 `throttle` 运算符天然适合。

### 1.5 状态机模式（转写状态）

```swift
enum TranscriptionState: Equatable {
    case idle
    case preparing
    case extractingAudio
    case transcribing(progress: Double)
    case completed
    case failed(String)
    
    var displayText: String { /* 每个状态对应 UI 文案 */ }
}
```

**使用方式**：Service 更新状态 → `@Published` 驱动 View 刷新

### 1.6 安全文件访问模式

```swift
let accessing = sourceURL.startAccessingSecurityScopedResource()
defer {
    if accessing { sourceURL.stopAccessingSecurityScopedResource() }
}
try FileManager.default.copyItem(at: sourceURL, to: destURL)
```

**规则**：通过 `fileImporter` 获取的 URL 必须用 `startAccessingSecurityScopedResource()` 包裹。

---

## 二、SwiftUI 视图模式

### 2.1 条件内容（@ViewBuilder）

```swift
@ViewBuilder
private var transcriptPanel: some View {
    if let transcript = mediaItem.transcript {
        TranscriptListView(segments: transcript.segments, ...)
    } else {
        transcriptionPrompt
    }
}
```

### 2.2 自适应布局（横竖屏）

```swift
GeometryReader { geo in
    let isLandscape = geo.size.width > geo.size.height
    if isLandscape {
        HStack(spacing: 0) { playerSection.frame(width: geo.size.width * 0.55); Divider(); transcriptPanel }
    } else {
        VStack(spacing: 0) { playerSection.frame(height: 280); Divider(); transcriptPanel }
    }
}
```

### 2.3 ScrollView 自动滚动

```swift
ScrollViewReader { proxy in
    List { ForEach(...) { item in Row(item).id(item.id) } }
    .onChange(of: activeIndex) { _, newIndex in
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(segments[newIndex].id, anchor: .center)
        }
    }
}
```

### 2.4 Sheet / Alert / ConfirmationDialog

```swift
// Sheet
.sheet(isPresented: $showSettings) { SettingsView() }

// Alert with TextField
.alert("导入 URL", isPresented: $showURLInput) {
    TextField("https://...", text: $urlInput)
    Button("导入") { /* ... */ }
    Button("取消", role: .cancel) { }
}

// Confirmation Dialog
.confirmationDialog("选择模型", isPresented: $showModelPicker) {
    ForEach(models, id: \.self) { model in
        Button(model) { selectedModel = model }
    }
}
```

### 2.5 列表操作

```swift
List {
    ForEach(items) { item in
        Row(item)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { delete(item) } label: {
                    Label("删除", systemImage: "trash")
                }
            }
    }
}
.listStyle(.insetGrouped)
.searchable(text: $searchText, prompt: "搜索...")
```

---

## 三、常见开发任务指南

### 任务 A：添加新的视图页面

**步骤**：
1. 在 `Views/` 下创建新的子目录和 `.swift` 文件
2. 如果需要复杂状态逻辑，在 `ViewModels/` 创建对应 ViewModel
3. 在 `ContentView.swift` 中添加 Tab 或 NavigationLink
4. 如果需要新的 Tab，在 `AppState.AppTab` 枚举添加新值

### 任务 B：添加新的数据模型

**步骤**：
1. 在 `Models/MediaItem.swift` 或新建文件中定义 struct/enum
2. 确保遵循 `Identifiable, Codable, Hashable`
3. 如果需要持久化，确保所有属性都是 `Codable`
4. 在相关 Service 中添加 CRUD 方法
5. 注意：`URL` 类型需要额外的 Codable 处理，项目中使用 `filePath: String` + `fileURL: URL?`

### 任务 C：添加新的 LLM 后端

**步骤**：
1. 在 `ChatService.APIProvider` 添加新枚举值
2. 在 `ChatService` 添加 `callNewProvider(messages:) async throws -> String` 方法
3. 在 `callLLM()` 的 switch 中路由新后端
4. 在 `SettingsView` 的 Provider Picker 中添加新选项
5. 如果需要特殊配置（如自定义 header），在 `ChatService.Config` 中添加属性
6. 在 `SettingsView.applySettings()` 中写入新配置

### 任务 D：修改转写流程

**涉及文件**：
- `TranscriptionService.swift` — 核心逻辑
- `PlayerViewModel.swift` — 调用和状态转发
- `PlayerView.swift` — UI 状态展示
- `MediaItem.swift` — `TranscriptionState` 枚举

**注意事项**：
- 音频必须转为 16kHz 单声道 WAV
- 状态通过 `@Published state` 驱动 UI
- 转写结果要回写到 `MediaItem.transcript`
- 完成后要调用 `chatService.setTranscript()`

### 任务 E：修改播放器行为

**涉及文件**：
- `MediaPlayerService.swift` — 播放器实现
- `PlayerViewModel.swift` — 控制逻辑
- `PlayerView.swift` — UI 控件

**AVPlayer vs VLCKit 注意**：
- AVPlayer 使用 `addPeriodicTimeObserver` 获取当前时间
- VLCKit 使用 `VLCMediaPlayerDelegate.mediaPlayerTimeChanged` 回调
- AVPlayer 时间是 `CMTime`，需要 `.seconds` 转换
- VLCKit 时间是毫秒整数，需要 `/1000.0` 转换
- AVPlayer 跳转使用 `seek(to: CMTime)`
- VLCKit 跳转使用 `position` (0.0-1.0 浮点) 或 `time` (毫秒)

### 任务 F：优化长转写稿的 Token 管理

**当前问题**：超长转写稿可能超出 LLM context window  
**建议实现**：

```swift
func buildSystemContext(_ transcript: Transcript, maxTokens: Int = 80000) -> String {
    var context = config.systemPrompt + "\n\n=== MEDIA TRANSCRIPT ===\n"
    var tokenCount = 0
    
    for segment in transcript.segments {
        let segmentText = "[\(segment.formattedTimeRange)] \(segment.text)\n"
        let estimatedTokens = segmentText.count / 4  // 粗略估算
        
        if tokenCount + estimatedTokens > maxTokens {
            context += "\n[... 转写稿因长度截断，共 \(transcript.segments.count) 段 ...]\n"
            break
        }
        
        context += segmentText
        tokenCount += estimatedTokens
    }
    
    context += "=== END TRANSCRIPT ===\n"
    return context
}
```

### 任务 G：添加单元测试

**建议结构**：
```
Tests/VoiceTokTests/
├── TranscriptionServiceTests.swift
├── ChatServiceTests.swift
├── MediaLibraryServiceTests.swift
├── PlayerViewModelTests.swift
└── ModelTests.swift
```

**关键测试点**：
- `TranscriptSegment.formattedTimeRange` 格式化
- `MediaLibraryService` 文件去重逻辑
- `ChatService` 消息构建（system prompt 分离）
- `PlayerViewModel.updateActiveSegment()` 段落匹配
- `MediaItem` Codable 编解码

---

## 四、错误处理约定

### 4.1 自定义错误类型

每个 Service 定义自己的错误枚举：

```swift
enum TranscriptionError: LocalizedError {
    case notInitialized
    case transcriptionFailed
    case audioExtractionFailed
    case noAudioTrack
    case invalidAudioFormat
    
    var errorDescription: String? { /* 用户可读描述 */ }
}

enum ChatError: LocalizedError {
    case missingAPIKey
    case apiError(String)
    
    var errorDescription: String? { ... }
}
```

### 4.2 错误传播

```
Service throws → ViewModel catches → 更新 @Published 状态 → View 展示
```

**不要**在 Service 中 catch 错误后静默忽略，除非有明确的恢复策略。

---

## 五、性能注意事项

| 场景 | 优化策略 |
|------|---------|
| 播放时间同步 | Combine throttle 200ms，避免每帧计算 |
| 转写面板滚动 | LazyVStack + ScrollViewReader，不预渲染全部 |
| 缩略图生成 | maximumSize 400×400，JPEG 0.7 质量 |
| 媒体库加载 | 启动时从 UserDefaults 反序列化，过滤无效文件 |
| WhisperKit 初始化 | 应用启动异步 prewarm，不阻塞 UI |
| API 调用 | async/await + URLSession 默认复用连接 |

---

## 六、文件命名对应关系速查

| 功能 | View | ViewModel | Service | Model |
|------|------|-----------|---------|-------|
| 媒体库 | LibraryView | — | MediaLibraryService | MediaItem |
| 播放器 | PlayerView | PlayerViewModel | MediaPlayerService | PlaybackState |
| 转写 | PlayerView (内嵌) | PlayerViewModel | TranscriptionService | Transcript, TranscriptSegment |
| AI 对话 | ChatView | — | ChatService | ChatMessage |
| 设置 | SettingsView | — | — (直接 @AppStorage) | — |
| 全局状态 | ContentView | — | — | AppState |

---

*本文档为 AI 开发助手提供具体的代码模式和任务执行指南。*

---
---


# VoiceTok — 完整源代码参考

> 本文档包含 VoiceTok 项目全部 19 个源文件的完整代码。将此文档提供给 AI，即可让其在完整上下文中进行代码修改、审查、扩展。

---

## `VoiceTok/App/VoiceTokApp.swift`

```swift
// VoiceTokApp.swift
// VoiceTok - AI-Powered Media Player with Transcription & Chat
// Combines VLCKit playback + WhisperKit transcription + AI conversation

import SwiftUI

@main
struct VoiceTokApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

```

---

## `VoiceTok/App/AppState.swift`

```swift
// AppState.swift
// Global application state

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Navigation
    @Published var selectedTab: AppTab = .library
    @Published var activeMediaItem: MediaItem?

    // MARK: - Services
    let transcriptionService = TranscriptionService()
    let chatService = ChatService()
    let mediaLibraryService = MediaLibraryService()

    // MARK: - Flags
    @Published var isTranscribing = false
    @Published var whisperKitReady = false

    init() {
        Task {
            await prepareWhisperKit()
        }
    }

    func prepareWhisperKit() async {
        do {
            try await transcriptionService.initialize()
            whisperKitReady = true
        } catch {
            print("[VoiceTok] WhisperKit initialization failed: \(error)")
        }
    }
}

enum AppTab: String, CaseIterable {
    case library = "Library"
    case player = "Player"
    case chat = "Chat"

    var icon: String {
        switch self {
        case .library: return "square.grid.2x2.fill"
        case .player: return "play.circle.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
}

```

---

## `VoiceTok/Models/MediaItem.swift`

```swift
// MediaItem.swift
// Core data models for VoiceTok

import Foundation

// MARK: - Media Item
struct MediaItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var filePath: String
    var fileURL: URL?
    var duration: TimeInterval
    var mediaType: MediaType
    var dateAdded: Date
    var thumbnailPath: String?
    var transcript: Transcript?
    var chatHistory: [ChatMessage]?

    init(
        id: UUID = UUID(),
        title: String,
        filePath: String,
        fileURL: URL? = nil,
        duration: TimeInterval = 0,
        mediaType: MediaType = .video,
        dateAdded: Date = Date(),
        thumbnailPath: String? = nil,
        transcript: Transcript? = nil,
        chatHistory: [ChatMessage]? = nil
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.fileURL = fileURL
        self.duration = duration
        self.mediaType = mediaType
        self.dateAdded = dateAdded
        self.thumbnailPath = thumbnailPath
        self.transcript = transcript
        self.chatHistory = chatHistory
    }
}

enum MediaType: String, Codable {
    case video
    case audio

    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
}

// MARK: - Transcript
struct Transcript: Codable, Hashable {
    var segments: [TranscriptSegment]
    var fullText: String
    var language: String?
    var dateCreated: Date

    init(segments: [TranscriptSegment] = [], fullText: String = "", language: String? = nil, dateCreated: Date = Date()) {
        self.segments = segments
        self.fullText = fullText
        self.language = language
        self.dateCreated = dateCreated
    }
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var speakerLabel: String?

    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String, speakerLabel: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speakerLabel = speakerLabel
    }

    var formattedTimeRange: String {
        "\(Self.format(startTime)) → \(Self.format(endTime))"
    }

    static func format(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Chat
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: ChatRole
    var content: String
    var timestamp: Date
    var referencedSegments: [UUID]?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        referencedSegments: [UUID]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.referencedSegments = referencedSegments
    }
}

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Transcription State
enum TranscriptionState: Equatable {
    case idle
    case preparing
    case extractingAudio
    case transcribing(progress: Double)
    case completed
    case failed(String)

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Preparing WhisperKit..."
        case .extractingAudio: return "Extracting audio track..."
        case .transcribing(let p): return "Transcribing... \(Int(p * 100))%"
        case .completed: return "Transcription complete"
        case .failed(let e): return "Failed: \(e)"
        }
    }
}

// MARK: - Player State
enum PlaybackState {
    case stopped
    case playing
    case paused
    case buffering
}

```

---

## `VoiceTok/Services/TranscriptionService.swift`

```swift
// TranscriptionService.swift
// Wraps WhisperKit for on-device speech-to-text transcription

import Foundation
import WhisperKit
import AVFoundation

@MainActor
final class TranscriptionService: ObservableObject {
    // MARK: - Published State
    @Published var state: TranscriptionState = .idle
    @Published var currentTranscript: Transcript?

    // MARK: - WhisperKit
    private var whisperKit: WhisperKit?
    private var isInitialized = false

    // MARK: - Configuration
    struct Config {
        var modelName: String = "base"           // base model balances speed/quality
        var language: String? = nil               // nil = auto-detect
        var task: String = "transcribe"           // "transcribe" or "translate"
        var wordTimestamps: Bool = true
        var chunkLength: Int = 30                 // seconds per chunk
    }

    var config = Config()

    // MARK: - Initialization
    func initialize() async throws {
        guard !isInitialized else { return }

        state = .preparing
        do {
            let whisperConfig = WhisperKitConfig(
                model: config.modelName,
                verbose: false,
                prewarm: true
            )
            whisperKit = try await WhisperKit(whisperConfig)
            isInitialized = true
            state = .idle
            print("[TranscriptionService] WhisperKit initialized with model: \(config.modelName)")
        } catch {
            state = .failed("WhisperKit init failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Transcribe Audio File
    func transcribe(audioURL: URL) async throws -> Transcript {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.notInitialized
        }

        state = .transcribing(progress: 0.0)

        do {
            let options = DecodingOptions(
                language: config.language,
                task: .transcribe,
                wordTimestamps: config.wordTimestamps
            )

            guard let results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            ) else {
                throw TranscriptionError.transcriptionFailed
            }

            // Convert WhisperKit results to our Transcript model
            var segments: [TranscriptSegment] = []
            var fullText = ""

            for result in results {
                for segment in result.segments {
                    let seg = TranscriptSegment(
                        startTime: TimeInterval(segment.start),
                        endTime: TimeInterval(segment.end),
                        text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    segments.append(seg)
                    fullText += seg.text + " "
                }
            }

            let transcript = Transcript(
                segments: segments,
                fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                language: results.first?.language ?? config.language,
                dateCreated: Date()
            )

            state = .completed
            currentTranscript = transcript
            return transcript

        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Transcribe from Media (extract audio first)
    func transcribeMedia(at url: URL) async throws -> Transcript {
        state = .extractingAudio

        // Extract audio from video if needed
        let audioURL = try await extractAudio(from: url)

        // Transcribe the extracted audio
        return try await transcribe(audioURL: audioURL)
    }

    // MARK: - Audio Extraction
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }

        // Check if it's already audio-only
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw TranscriptionError.noAudioTrack
        }

        // For WhisperKit, we need WAV format — use AVAssetReader + AVAssetWriter
        let wavURL = try await convertToWav(asset: asset, outputURL: outputURL)
        return wavURL
    }

    private func convertToWav(asset: AVURLAsset, outputURL: URL) async throws -> URL {
        let reader = try AVAssetReader(asset: asset)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw TranscriptionError.noAudioTrack
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,              // WhisperKit expects 16kHz
            AVNumberOfChannelsKey: 1,               // Mono
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: outputSettings
        )
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.export")) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            continuation.resume()
                        }
                        return
                    }
                }
            }
        }

        return outputURL
    }

    // MARK: - Model Management
    func switchModel(to modelName: String) async throws {
        config.modelName = modelName
        isInitialized = false
        whisperKit = nil
        try await initialize()
    }

    static let availableModels = [
        "tiny",
        "tiny.en",
        "base",
        "base.en",
        "small",
        "small.en",
        "medium",
        "medium.en",
        "large-v3",
        "distil-large-v3"
    ]
}

// MARK: - Errors
enum TranscriptionError: LocalizedError {
    case notInitialized
    case transcriptionFailed
    case audioExtractionFailed
    case noAudioTrack
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "WhisperKit is not initialized"
        case .transcriptionFailed: return "Transcription failed"
        case .audioExtractionFailed: return "Could not extract audio from media"
        case .noAudioTrack: return "No audio track found in media"
        case .invalidAudioFormat: return "Invalid audio format"
        }
    }
}

```

---

## `VoiceTok/Services/MediaPlayerService.swift`

```swift
// MediaPlayerService.swift
// Wraps VLCKit for robust media playback (video + audio)
// VLCKit imported via CocoaPods: pod 'MobileVLCKit', '~> 3.6'

import Foundation
import Combine
import AVFoundation

// NOTE: In production, import MobileVLCKit and use VLCMediaPlayer.
// This file provides the protocol and a fallback AVPlayer implementation
// so the project compiles standalone. Swap to VLCPlayerService for VLCKit.

// MARK: - Player Protocol
protocol MediaPlayerProtocol: ObservableObject {
    var playbackState: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Float { get set }
    var playbackRate: Float { get set }

    func load(url: URL) async
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func togglePlayPause()
}

// MARK: - AVFoundation-based Player (Default / Fallback)
@MainActor
final class AVMediaPlayerService: ObservableObject, MediaPlayerProtocol {
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }
    @Published var playbackRate: Float = 1.0 {
        didSet { player?.rate = playbackRate }
    }

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupAudioSession()
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }

    // MARK: - Audio Session
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[MediaPlayer] Audio session setup failed: \(error)")
        }
    }

    // MARK: - Load
    func load(url: URL) async {
        stop()
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume

        // Observe duration
        do {
            let dur = try await asset.load(.duration)
            duration = dur.seconds.isNaN ? 0 : dur.seconds
        } catch {
            duration = 0
        }

        // Periodic time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds.isNaN ? 0 : time.seconds
            }
        }

        // Observe end of playback
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.playbackState = .stopped
                    self?.currentTime = 0
                }
            }
            .store(in: &cancellables)

        playbackState = .paused
    }

    // MARK: - Controls
    func play() {
        player?.play()
        player?.rate = playbackRate
        playbackState = .playing
    }

    func pause() {
        player?.pause()
        playbackState = .paused
    }

    func stop() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player = nil
        playbackState = .stopped
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func togglePlayPause() {
        switch playbackState {
        case .playing: pause()
        case .paused, .stopped: play()
        default: break
        }
    }
}

// MARK: - VLCKit-based Player (Production)
// Uncomment and use when VLCKit is available via CocoaPods
/*
import MobileVLCKit

@MainActor
final class VLCPlayerService: NSObject, ObservableObject, MediaPlayerProtocol {
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 {
        didSet { mediaPlayer.audio?.volume = Int32(volume * 200) }
    }
    @Published var playbackRate: Float = 1.0 {
        didSet { mediaPlayer.rate = playbackRate }
    }

    let mediaPlayer = VLCMediaPlayer()
    var drawable: UIView?

    override init() {
        super.init()
        mediaPlayer.delegate = self
    }

    func setDrawable(_ view: UIView) {
        drawable = view
        mediaPlayer.drawable = view
    }

    func load(url: URL) async {
        let media = VLCMedia(url: url)
        media.addOptions([
            "network-caching": 300,
            "file-caching": 500
        ])
        mediaPlayer.media = media

        // Parse media for duration
        media.parse(withOptions: VLCMediaParsingOptions(VLCMediaParseLocal))
        try? await Task.sleep(nanoseconds: 500_000_000)
        duration = TimeInterval(media.length.intValue) / 1000.0
    }

    func play() {
        mediaPlayer.play()
        playbackState = .playing
    }

    func pause() {
        mediaPlayer.pause()
        playbackState = .paused
    }

    func stop() {
        mediaPlayer.stop()
        playbackState = .stopped
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        let position = Float(time / max(duration, 1))
        mediaPlayer.position = min(max(position, 0), 1)
        currentTime = time
    }

    func togglePlayPause() {
        switch playbackState {
        case .playing: pause()
        case .paused, .stopped: play()
        default: break
        }
    }
}

extension VLCPlayerService: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            currentTime = TimeInterval(mediaPlayer.time.intValue) / 1000.0
        }
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            switch mediaPlayer.state {
            case .playing:   playbackState = .playing
            case .paused:    playbackState = .paused
            case .stopped:   playbackState = .stopped
            case .buffering: playbackState = .buffering
            default:         break
            }
        }
    }
}
*/

```

---

## `VoiceTok/Services/ChatService.swift`

```swift
// ChatService.swift
// AI conversation service that uses transcripts as context
// Supports multiple LLM backends: Claude API, OpenAI, local LLM

import Foundation

@MainActor
final class ChatService: ObservableObject {
    // MARK: - Published State
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var currentStreamText = ""

    // MARK: - Configuration
    struct Config {
        var apiProvider: APIProvider = .claude
        var apiKey: String = ""
        var baseURL: String = ""
        var modelName: String = "claude-sonnet-4-20250514"
        var maxTokens: Int = 2048
        var temperature: Double = 0.7
        var systemPrompt: String = """
        You are VoiceTok AI, an intelligent assistant that helps users understand \
        and interact with media content through its transcript. You can answer \
        questions about the content, summarize sections, explain concepts mentioned, \
        identify key topics, and provide analysis. Always reference specific parts \
        of the transcript when relevant. Be concise but thorough.
        """
    }

    enum APIProvider: String, CaseIterable {
        case claude = "Claude (Anthropic)"
        case openai = "OpenAI"
        case ollama = "Ollama (Local)"
    }

    var config = Config()
    private var transcript: Transcript?

    // MARK: - Set Context
    func setTranscript(_ transcript: Transcript) {
        self.transcript = transcript
        messages = [
            ChatMessage(
                role: .system,
                content: buildSystemContext(transcript)
            )
        ]
    }

    private func buildSystemContext(_ transcript: Transcript) -> String {
        var context = config.systemPrompt + "\n\n"
        context += "=== MEDIA TRANSCRIPT ===\n"

        if let lang = transcript.language {
            context += "Language: \(lang)\n\n"
        }

        for segment in transcript.segments {
            context += "[\(segment.formattedTimeRange)] \(segment.text)\n"
        }

        context += "\n=== END TRANSCRIPT ===\n"
        context += "\nFull text summary available. \(transcript.segments.count) segments, "
        context += "total length: \(TranscriptSegment.format(transcript.segments.last?.endTime ?? 0))"

        return context
    }

    // MARK: - Send Message
    func send(_ userMessage: String) async {
        let userMsg = ChatMessage(role: .user, content: userMessage)
        messages.append(userMsg)
        isGenerating = true
        currentStreamText = ""

        do {
            let response = try await callLLM(messages: messages)
            let assistantMsg = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMsg)
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Sorry, I encountered an error: \(error.localizedDescription)"
            )
            messages.append(errorMsg)
        }

        isGenerating = false
    }

    // MARK: - Quick Actions
    func summarize() async {
        await send("Please provide a comprehensive summary of this media content, highlighting the main topics and key points discussed.")
    }

    func extractKeyTopics() async {
        await send("What are the main topics and themes discussed in this content? List them with brief descriptions.")
    }

    func generateNotes() async {
        await send("Create structured study notes from this transcript with headings, bullet points, and key takeaways.")
    }

    func translateSummary(to language: String) async {
        await send("Please summarize the main content and translate the summary to \(language).")
    }

    // MARK: - LLM API Call
    private func callLLM(messages: [ChatMessage]) async throws -> String {
        switch config.apiProvider {
        case .claude:
            return try await callClaude(messages: messages)
        case .openai:
            return try await callOpenAI(messages: messages)
        case .ollama:
            return try await callOllama(messages: messages)
        }
    }

    // MARK: - Claude API
    private func callClaude(messages: [ChatMessage]) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw ChatError.missingAPIKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Separate system message from conversation
        let systemContent = messages.first(where: { $0.role == .system })?.content ?? config.systemPrompt
        let conversationMessages = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": config.modelName,
            "max_tokens": config.maxTokens,
            "system": systemContent,
            "messages": conversationMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatError.apiError("Claude API error: \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String

        return text ?? "No response generated."
    }

    // MARK: - OpenAI API
    private func callOpenAI(messages: [ChatMessage]) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw ChatError.missingAPIKey
        }

        let url = URL(string: "\(config.baseURL.isEmpty ? "https://api.openai.com" : config.baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": config.modelName,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]

        return message?["content"] as? String ?? "No response generated."
    }

    // MARK: - Ollama (Local)
    private func callOllama(messages: [ChatMessage]) async throws -> String {
        let url = URL(string: "\(config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": config.modelName.isEmpty ? "llama3.2" : config.modelName,
            "messages": apiMessages,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = json?["message"] as? [String: Any]

        return message?["content"] as? String ?? "No response generated."
    }

    // MARK: - Clear
    func clearHistory() {
        if let transcript = transcript {
            messages = [ChatMessage(role: .system, content: buildSystemContext(transcript))]
        } else {
            messages = []
        }
    }
}

// MARK: - Errors
enum ChatError: LocalizedError {
    case missingAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key not configured. Go to Settings to add your key."
        case .apiError(let msg): return msg
        }
    }
}

```

---

## `VoiceTok/Services/MediaLibraryService.swift`

```swift
// MediaLibraryService.swift
// Manages media file import, storage, and persistence

import Foundation
import UniformTypeIdentifiers
import UIKit
import AVFoundation

@MainActor
final class MediaLibraryService: ObservableObject {
    @Published var mediaItems: [MediaItem] = []
    @Published var isImporting = false

    private let storageKey = "voicetok_media_library"
    private let documentsURL: URL

    init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceTok", isDirectory: true)

        // Create app directory
        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        loadLibrary()
    }

    // MARK: - Supported Types
    static let supportedTypes: [UTType] = [
        .mpeg4Movie, .quickTimeMovie, .avi, .movie,
        .mp3, .wav, .aiff, .mpeg4Audio,
        UTType("public.mpeg-2-transport-stream") ?? .movie,
        UTType("org.matroska.mkv") ?? .movie,
        UTType("public.flac") ?? .audio,
    ]

    static let supportedExtensions = [
        "mp4", "m4v", "mov", "avi", "mkv", "ts", "flv", "wmv", "webm",
        "mp3", "m4a", "wav", "aiff", "flac", "ogg", "wma", "aac"
    ]

    // MARK: - Import
    func importMedia(from sourceURL: URL) async throws -> MediaItem {
        isImporting = true
        defer { isImporting = false }

        // Copy file to app's documents
        let fileName = sourceURL.lastPathComponent
        let destURL = documentsURL.appendingPathComponent(fileName)

        // Handle duplicate filenames
        var finalURL = destURL
        var counter = 1
        while FileManager.default.fileExists(atPath: finalURL.path) {
            let name = destURL.deletingPathExtension().lastPathComponent
            let ext = destURL.pathExtension
            finalURL = documentsURL.appendingPathComponent("\(name)_\(counter).\(ext)")
            counter += 1
        }

        // Access security-scoped resource
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.copyItem(at: sourceURL, to: finalURL)

        // Determine media type
        let audioExtensions = Set(["mp3", "m4a", "wav", "aiff", "flac", "ogg", "wma", "aac"])
        let ext = finalURL.pathExtension.lowercased()
        let mediaType: MediaType = audioExtensions.contains(ext) ? .audio : .video

        // Get duration
        let asset = AVURLAsset(url: finalURL)
        let durationCMTime = try await asset.load(.duration)
        let duration = durationCMTime.seconds.isNaN ? 0 : durationCMTime.seconds

        // Generate thumbnail for video
        var thumbnailPath: String?
        if mediaType == .video {
            thumbnailPath = await generateThumbnail(from: finalURL)
        }

        let item = MediaItem(
            title: finalURL.deletingPathExtension().lastPathComponent,
            filePath: finalURL.path,
            fileURL: finalURL,
            duration: duration,
            mediaType: mediaType,
            thumbnailPath: thumbnailPath
        )

        mediaItems.insert(item, at: 0)
        saveLibrary()

        return item
    }

    // MARK: - Thumbnail Generation
    private func generateThumbnail(from url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        do {
            let (image, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 1))
            let uiImage = UIImage(cgImage: image)
            let thumbURL = documentsURL.appendingPathComponent("thumb_\(url.deletingPathExtension().lastPathComponent).jpg")

            if let data = uiImage.jpegData(compressionQuality: 0.7) {
                try data.write(to: thumbURL)
                return thumbURL.path
            }
        } catch {
            print("[Library] Thumbnail generation failed: \(error)")
        }
        return nil
    }

    // MARK: - Update Item
    func updateItem(_ item: MediaItem) {
        if let index = mediaItems.firstIndex(where: { $0.id == item.id }) {
            mediaItems[index] = item
            saveLibrary()
        }
    }

    // MARK: - Delete
    func deleteItem(_ item: MediaItem) {
        // Remove file
        try? FileManager.default.removeItem(atPath: item.filePath)
        if let thumb = item.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumb)
        }

        mediaItems.removeAll { $0.id == item.id }
        saveLibrary()
    }

    // MARK: - Persistence
    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(mediaItems) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return
        }
        // Validate files still exist
        mediaItems = items.filter { FileManager.default.fileExists(atPath: $0.filePath) }
    }

    // MARK: - Format Helpers
    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let mins = (Int(duration) % 3600) / 60
        let secs = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    static func formatFileSize(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return nil }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

```

---

## `VoiceTok/ViewModels/PlayerViewModel.swift`

```swift
// PlayerViewModel.swift
// Coordinates playback, transcription, and transcript navigation

import SwiftUI
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - Dependencies
    let player = AVMediaPlayerService()
    let transcriptionService: TranscriptionService
    let chatService: ChatService

    // MARK: - State
    @Published var mediaItem: MediaItem?
    @Published var transcriptionState: TranscriptionState = .idle
    @Published var activeSegmentIndex: Int?
    @Published var showTranscript = true
    @Published var showChat = false

    private var cancellables = Set<AnyCancellable>()

    init(transcriptionService: TranscriptionService, chatService: ChatService) {
        self.transcriptionService = transcriptionService
        self.chatService = chatService
        setupTimeTracking()
    }

    // MARK: - Load Media
    func loadMedia(_ item: MediaItem) async {
        mediaItem = item

        guard let url = item.fileURL ?? URL(string: item.filePath) else { return }
        await player.load(url: url)

        // If transcript exists, set it up
        if let transcript = item.transcript {
            chatService.setTranscript(transcript)
        }
    }

    // MARK: - Transcription
    func startTranscription() async {
        guard let item = mediaItem,
              let url = item.fileURL ?? URL(fileURLWithPath: item.filePath) else { return }

        transcriptionState = .preparing

        // Forward state from service
        transcriptionService.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$transcriptionState)

        do {
            let transcript = try await transcriptionService.transcribeMedia(at: url)

            // Update the media item with transcript
            var updatedItem = item
            updatedItem.transcript = transcript
            mediaItem = updatedItem

            // Set up chat context
            chatService.setTranscript(transcript)
            transcriptionState = .completed

        } catch {
            transcriptionState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Time Tracking → Active Segment
    private func setupTimeTracking() {
        player.$currentTime
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] time in
                self?.updateActiveSegment(for: time)
            }
            .store(in: &cancellables)
    }

    private func updateActiveSegment(for time: TimeInterval) {
        guard let segments = mediaItem?.transcript?.segments else {
            activeSegmentIndex = nil
            return
        }

        activeSegmentIndex = segments.lastIndex(where: { $0.startTime <= time && $0.endTime >= time })
    }

    // MARK: - Navigate to Segment
    func seekToSegment(_ segment: TranscriptSegment) {
        player.seek(to: segment.startTime)
        if player.playbackState != .playing {
            player.play()
        }
    }

    // MARK: - Playback Helpers
    var progress: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    var currentTimeFormatted: String {
        MediaLibraryService.formatDuration(player.currentTime)
    }

    var durationFormatted: String {
        MediaLibraryService.formatDuration(player.duration)
    }

    var hasTranscript: Bool {
        mediaItem?.transcript != nil
    }
}

```

---

## `VoiceTok/Views/ContentView.swift`

```swift
// ContentView.swift
// Main container view with tab-based navigation

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // Library Tab
            LibraryView()
                .tabItem {
                    Label(AppTab.library.rawValue, systemImage: AppTab.library.icon)
                }
                .tag(AppTab.library)

            // Player Tab
            PlayerContainerView()
                .tabItem {
                    Label(AppTab.player.rawValue, systemImage: AppTab.player.icon)
                }
                .tag(AppTab.player)

            // Chat Tab
            ChatContainerView()
                .tabItem {
                    Label(AppTab.chat.rawValue, systemImage: AppTab.chat.icon)
                }
                .tag(AppTab.chat)
        }
        .tint(.orange)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Player Container (passes dependencies)
struct PlayerContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let item = appState.activeMediaItem {
            PlayerView(
                mediaItem: item,
                transcriptionService: appState.transcriptionService,
                chatService: appState.chatService
            )
        } else {
            EmptyPlayerView()
        }
    }
}

// MARK: - Chat Container
struct ChatContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.activeMediaItem?.transcript != nil {
            ChatView(chatService: appState.chatService)
        } else {
            EmptyChatView()
        }
    }
}

// MARK: - Empty States
struct EmptyPlayerView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "play.circle")
                    .font(.system(size: 80))
                    .foregroundStyle(.tertiary)
                Text("No Media Selected")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Import a video or audio file from\nthe Library tab to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("Player")
        }
    }
}

struct EmptyChatView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 80))
                    .foregroundStyle(.tertiary)
                Text("No Transcript Available")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Transcribe a media file first, then\nyou can chat about its content with AI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("AI Chat")
        }
    }
}

```

---

## `VoiceTok/Views/Library/LibraryView.swift`

```swift
// LibraryView.swift
// Media library with import, browse, and management

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFilePicker = false
    @State private var showURLInput = false
    @State private var urlInput = ""
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDesc

    enum SortOrder: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case titleAsc = "Title A→Z"
        case titleDesc = "Title Z→A"
        case durationDesc = "Longest"
    }

    var filteredItems: [MediaItem] {
        var items = appState.mediaLibraryService.mediaItems

        if !searchText.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOrder {
        case .dateDesc: items.sort { $0.dateAdded > $1.dateAdded }
        case .dateAsc: items.sort { $0.dateAdded < $1.dateAdded }
        case .titleAsc: items.sort { $0.title < $1.title }
        case .titleDesc: items.sort { $0.title > $1.title }
        case .durationDesc: items.sort { $0.duration > $1.duration }
        }

        return items
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.mediaLibraryService.mediaItems.isEmpty {
                    emptyLibraryView
                } else {
                    mediaListView
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showFilePicker = true }) {
                            Label("Import from Files", systemImage: "folder")
                        }
                        Button(action: { showURLInput = true }) {
                            Label("Import from URL", systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search media...")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: MediaLibraryService.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                Task {
                    switch result {
                    case .success(let urls):
                        for url in urls {
                            do {
                                let item = try await appState.mediaLibraryService.importMedia(from: url)
                                appState.activeMediaItem = item
                            } catch {
                                print("[Library] Import failed: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("[Library] File picker error: \(error)")
                    }
                }
            }
            .alert("Import from URL", isPresented: $showURLInput) {
                TextField("https://...", text: $urlInput)
                    .textInputAutocapitalization(.never)
                Button("Import") {
                    guard let url = URL(string: urlInput) else { return }
                    Task {
                        let item = try? await appState.mediaLibraryService.importMedia(from: url)
                        if let item { appState.activeMediaItem = item }
                    }
                    urlInput = ""
                }
                Button("Cancel", role: .cancel) { urlInput = "" }
            }
        }
    }

    // MARK: - Empty State
    private var emptyLibraryView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Your Media Library")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Import video or audio files to transcribe\nand chat about their content with AI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showFilePicker = true }) {
                Label("Import Media", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 14)
                    .background(.orange.gradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Media List
    private var mediaListView: some View {
        List {
            ForEach(filteredItems) { item in
                MediaItemRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.activeMediaItem = item
                        appState.selectedTab = .player
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.mediaLibraryService.deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Media Item Row
struct MediaItemRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail / Icon
            ZStack {
                if let thumbPath = item.thumbnailPath,
                   let image = UIImage(contentsOfFile: thumbPath) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    Image(systemName: item.mediaType.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(MediaLibraryService.formatDuration(item.duration), systemImage: "clock")
                    if item.transcript != nil {
                        Label("Transcribed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

```

---

## `VoiceTok/Views/Player/PlayerView.swift`

```swift
// PlayerView.swift
// Full-featured media player with integrated transcript sidebar

import SwiftUI
import AVKit

struct PlayerView: View {
    let mediaItem: MediaItem
    let transcriptionService: TranscriptionService
    let chatService: ChatService

    @StateObject private var viewModel: PlayerViewModel
    @State private var showModelPicker = false
    @State private var selectedModel = "base"

    init(mediaItem: MediaItem, transcriptionService: TranscriptionService, chatService: ChatService) {
        self.mediaItem = mediaItem
        self.transcriptionService = transcriptionService
        self.chatService = chatService
        _viewModel = StateObject(wrappedValue: PlayerViewModel(
            transcriptionService: transcriptionService,
            chatService: chatService
        ))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                if isLandscape {
                    // Landscape: player left, transcript right
                    HStack(spacing: 0) {
                        playerSection
                            .frame(width: geo.size.width * 0.55)
                        Divider()
                        transcriptPanel
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // Portrait: player top, transcript bottom
                    VStack(spacing: 0) {
                        playerSection
                            .frame(height: mediaItem.mediaType == .video ? 280 : 200)
                        Divider()
                        transcriptPanel
                    }
                }
            }
            .navigationTitle(mediaItem.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !viewModel.hasTranscript {
                            Button(action: { showModelPicker = true }) {
                                Label("Select Model", systemImage: "cpu")
                            }
                            Button(action: { Task { await viewModel.startTranscription() } }) {
                                Label("Transcribe", systemImage: "waveform.badge.mic")
                            }
                        }
                        if viewModel.hasTranscript {
                            Button(action: { exportTranscript() }) {
                                Label("Export Transcript", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Select Whisper Model", isPresented: $showModelPicker) {
                ForEach(TranscriptionService.availableModels, id: \.self) { model in
                    Button(model) {
                        selectedModel = model
                        Task {
                            try? await transcriptionService.switchModel(to: model)
                            await viewModel.startTranscription()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                await viewModel.loadMedia(mediaItem)
            }
        }
    }

    // MARK: - Player Section
    @ViewBuilder
    private var playerSection: some View {
        VStack(spacing: 0) {
            // Video / Audio Artwork
            if mediaItem.mediaType == .video {
                videoPlayerView
            } else {
                audioArtworkView
            }

            // Playback Controls
            playbackControls
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Video Player
    private var videoPlayerView: some View {
        ZStack {
            if let player = viewModel.player.player {
                VideoPlayer(player: player)
                    .disabled(true) // We use custom controls
            } else {
                Rectangle()
                    .fill(.black)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .onTapGesture {
            viewModel.player.togglePlayPause()
        }
    }

    // MARK: - Audio Artwork
    private var audioArtworkView: some View {
        ZStack {
            LinearGradient(
                colors: [.orange.opacity(0.3), .purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)
                    .symbolEffect(.variableColor.iterative,
                                  isActive: viewModel.player.playbackState == .playing)

                Text(mediaItem.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    // MARK: - Playback Controls
    private var playbackControls: some View {
        VStack(spacing: 8) {
            // Progress Bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { viewModel.player.currentTime },
                        set: { viewModel.player.seek(to: $0) }
                    ),
                    in: 0...max(viewModel.player.duration, 1)
                )
                .tint(.orange)

                HStack {
                    Text(viewModel.currentTimeFormatted)
                    Spacer()
                    Text(viewModel.durationFormatted)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            // Transport Controls
            HStack(spacing: 32) {
                // Playback Rate
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.2g")×") {
                            viewModel.player.playbackRate = Float(rate)
                        }
                    }
                } label: {
                    Text("\(viewModel.player.playbackRate, specifier: "%.2g")×")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                // Skip backward
                Button(action: { viewModel.player.seek(to: max(0, viewModel.player.currentTime - 15)) }) {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                }

                // Play / Pause
                Button(action: { viewModel.player.togglePlayPause() }) {
                    Image(systemName: viewModel.player.playbackState == .playing
                          ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                }

                // Skip forward
                Button(action: { viewModel.player.seek(to: min(viewModel.player.duration, viewModel.player.currentTime + 15)) }) {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                }

                // Volume
                Menu {
                    Slider(value: Binding(
                        get: { Double(viewModel.player.volume) },
                        set: { viewModel.player.volume = Float($0) }
                    ), in: 0...1)
                } label: {
                    Image(systemName: viewModel.player.volume > 0 ? "speaker.wave.2" : "speaker.slash")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Transcript Panel
    @ViewBuilder
    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            // Panel Header
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if viewModel.hasTranscript {
                    if let lang = mediaItem.transcript?.language {
                        Text(lang.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Text("\(mediaItem.transcript?.segments.count ?? 0) segments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Content
            if let transcript = mediaItem.transcript {
                TranscriptListView(
                    segments: transcript.segments,
                    activeIndex: viewModel.activeSegmentIndex,
                    onSegmentTap: { segment in
                        viewModel.seekToSegment(segment)
                    }
                )
            } else {
                transcriptionPrompt
            }
        }
    }

    // MARK: - Transcription Prompt
    private var transcriptionPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            switch viewModel.transcriptionState {
            case .idle:
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)

                    Text("Ready to Transcribe")
                        .font(.headline)

                    Text("Use WhisperKit to convert speech to text,\nthen chat about the content with AI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: { Task { await viewModel.startTranscription() } }) {
                        Label("Start Transcription", systemImage: "mic.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: 220)
                            .padding(.vertical, 12)
                            .background(.orange.gradient)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

            case .preparing, .extractingAudio, .transcribing:
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(viewModel.transcriptionState.displayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            case .failed(let error):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.startTranscription() }
                    }
                    .buttonStyle(.bordered)
                }

            case .completed:
                EmptyView() // Should show transcript above
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Export
    private func exportTranscript() {
        guard let transcript = mediaItem.transcript else { return }

        var text = "# \(mediaItem.title)\n"
        text += "## Transcript\n\n"
        for seg in transcript.segments {
            text += "[\(seg.formattedTimeRange)] \(seg.text)\n\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(mediaItem.title)_transcript.md")
        try? text.write(to: url, atomically: true, encoding: .utf8)

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }
}

// MARK: - Transcript List View
struct TranscriptListView: View {
    let segments: [TranscriptSegment]
    let activeIndex: Int?
    let onSegmentTap: (TranscriptSegment) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    TranscriptSegmentRow(
                        segment: segment,
                        isActive: index == activeIndex
                    )
                    .id(segment.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSegmentTap(segment)
                    }
                    .listRowBackground(
                        index == activeIndex
                        ? Color.orange.opacity(0.15)
                        : Color.clear
                    )
                }
            }
            .listStyle(.plain)
            .onChange(of: activeIndex) { _, newIndex in
                if let newIndex, newIndex < segments.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(segments[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(TranscriptSegment.format(segment.startTime))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(isActive ? .orange : .secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            Rectangle()
                .fill(isActive ? .orange : .secondary.opacity(0.3))
                .frame(width: 2)

            Text(segment.text)
                .font(.subheadline)
                .foregroundStyle(isActive ? .primary : .secondary)
                .fontWeight(isActive ? .medium : .regular)
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

```

---

## `VoiceTok/Views/Chat/ChatView.swift`

```swift
// ChatView.swift
// AI conversation interface for discussing transcript content

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatService: ChatService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showQuickActions = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages List
                messagesScrollView

                Divider()

                // Quick Actions Bar
                if showQuickActions {
                    quickActionsBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Input Bar
                inputBar
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showQuickActions.toggle() }) {
                            Label(showQuickActions ? "Hide Quick Actions" : "Show Quick Actions",
                                  systemImage: "bolt.circle")
                        }
                        Button(action: { chatService.clearHistory() }) {
                            Label("Clear Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showQuickActions)
        }
    }

    // MARK: - Messages
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Welcome card
                    welcomeCard
                        .padding(.top, 8)

                    ForEach(chatService.messages.filter { $0.role != .system }) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    // Typing indicator
                    if chatService.isGenerating {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .onChange(of: chatService.messages.count) { _, _ in
                if let lastMsg = chatService.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMsg.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatService.isGenerating) { _, isGen in
                if isGen {
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Welcome Card
    private var welcomeCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )

            Text("Chat About Your Media")
                .font(.headline)

            Text("Ask questions about the transcribed content.\nI can summarize, explain, translate, and more.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Quick Actions
    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                QuickActionButton(title: "Summarize", icon: "text.alignleft") {
                    Task { await chatService.summarize() }
                }
                QuickActionButton(title: "Key Topics", icon: "list.bullet.rectangle") {
                    Task { await chatService.extractKeyTopics() }
                }
                QuickActionButton(title: "Study Notes", icon: "note.text") {
                    Task { await chatService.generateNotes() }
                }
                QuickActionButton(title: "Translate to 中文", icon: "globe") {
                    Task { await chatService.translateSummary(to: "Chinese") }
                }
                QuickActionButton(title: "Translate to EN", icon: "globe") {
                    Task { await chatService.translateSummary(to: "English") }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Quick actions toggle
            Button(action: { showQuickActions.toggle() }) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(showQuickActions ? .orange : .secondary)
            }

            // Text field
            TextField("Ask about the content...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .secondary : .orange
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || chatService.isGenerating)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        Task { await chatService.send(text) }
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(.orange.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.orange : Color(.systemGray5))
                    .foregroundColor(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotScale(for: i))
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .onAppear { phase = 1.0 }
    }

    private func dotScale(for index: Int) -> CGFloat {
        phase == 0 ? 0.6 : 1.0
    }
}

```

---

## `VoiceTok/Views/SettingsView.swift`

```swift
// SettingsView.swift
// App settings: API keys, model selection, preferences

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @AppStorage("api_provider") private var apiProvider = "claude"
    @AppStorage("api_key") private var apiKey = ""
    @AppStorage("api_base_url") private var apiBaseURL = ""
    @AppStorage("chat_model") private var chatModel = "claude-sonnet-4-20250514"
    @AppStorage("whisper_model") private var whisperModel = "base"
    @AppStorage("auto_transcribe") private var autoTranscribe = false
    @AppStorage("word_timestamps") private var wordTimestamps = true
    @AppStorage("transcript_language") private var transcriptLanguage = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - AI Chat API
                Section {
                    Picker("Provider", selection: $apiProvider) {
                        ForEach(ChatService.APIProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.rawValue).tag(provider.rawValue)
                        }
                    }

                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if apiProvider == "openai" || apiProvider == "ollama" {
                        TextField("Base URL (optional)", text: $apiBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    TextField("Model Name", text: $chatModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                } header: {
                    Label("AI Chat API", systemImage: "brain")
                } footer: {
                    Text("Configure the LLM provider for transcript-based AI conversations. Claude, OpenAI, or local Ollama are supported.")
                }

                // MARK: - Whisper Transcription
                Section {
                    Picker("Model", selection: $whisperModel) {
                        ForEach(TranscriptionService.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    Toggle("Word-level Timestamps", isOn: $wordTimestamps)

                    Toggle("Auto-transcribe on Import", isOn: $autoTranscribe)

                    Picker("Language", selection: $transcriptLanguage) {
                        Text("Auto-detect").tag("")
                        ForEach(supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }

                } header: {
                    Label("WhisperKit Transcription", systemImage: "waveform")
                } footer: {
                    Text("Larger models are more accurate but slower. 'base' is recommended for most devices. 'large-v3' provides the best quality on newer iPhones/iPads.")
                }

                // MARK: - Playback
                Section {
                    NavigationLink("Audio & Video Settings") {
                        PlaybackSettingsView()
                    }
                } header: {
                    Label("Playback", systemImage: "play.circle")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Built with")
                        Spacer()
                        Text("VLCKit + WhisperKit")
                            .foregroundStyle(.secondary)
                    }

                    Link("WhisperKit on GitHub", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                    Link("VLC for iOS on GitHub", destination: URL(string: "https://github.com/videolan/vlc-ios")!)
                } header: {
                    Label("About VoiceTok", systemImage: "info.circle")
                }

                // MARK: - Data
                Section {
                    Button("Clear All Transcripts", role: .destructive) {
                        // Clear all transcripts from media items
                        for i in appState.mediaLibraryService.mediaItems.indices {
                            appState.mediaLibraryService.mediaItems[i].transcript = nil
                            appState.mediaLibraryService.mediaItems[i].chatHistory = nil
                        }
                    }

                    Button("Clear All Data", role: .destructive) {
                        appState.mediaLibraryService.mediaItems.removeAll()
                        UserDefaults.standard.removeObject(forKey: "voicetok_media_library")
                    }
                } header: {
                    Label("Data Management", systemImage: "externaldrive")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        applySettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func applySettings() {
        // Apply chat settings
        if let provider = ChatService.APIProvider(rawValue: apiProvider) {
            appState.chatService.config.apiProvider = provider
        }
        appState.chatService.config.apiKey = apiKey
        appState.chatService.config.baseURL = apiBaseURL
        appState.chatService.config.modelName = chatModel

        // Apply transcription settings
        appState.transcriptionService.config.modelName = whisperModel
        appState.transcriptionService.config.wordTimestamps = wordTimestamps
        appState.transcriptionService.config.language = transcriptLanguage.isEmpty ? nil : transcriptLanguage
    }

    // MARK: - Languages
    struct LanguageItem {
        let code: String
        let name: String
    }

    let supportedLanguages: [LanguageItem] = [
        .init(code: "en", name: "English"),
        .init(code: "zh", name: "Chinese / 中文"),
        .init(code: "ja", name: "Japanese / 日本語"),
        .init(code: "ko", name: "Korean / 한국어"),
        .init(code: "es", name: "Spanish"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "ru", name: "Russian"),
        .init(code: "ar", name: "Arabic"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "it", name: "Italian"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "sv", name: "Swedish"),
        .init(code: "pl", name: "Polish"),
        .init(code: "tr", name: "Turkish"),
        .init(code: "th", name: "Thai"),
        .init(code: "vi", name: "Vietnamese"),
    ]
}

// MARK: - Playback Settings
struct PlaybackSettingsView: View {
    @AppStorage("continue_in_background") private var backgroundPlayback = true
    @AppStorage("default_playback_rate") private var defaultRate = 1.0
    @AppStorage("skip_interval") private var skipInterval = 15.0

    var body: some View {
        Form {
            Section("General") {
                Toggle("Background Playback", isOn: $backgroundPlayback)

                Picker("Default Speed", selection: $defaultRate) {
                    Text("0.5×").tag(0.5)
                    Text("0.75×").tag(0.75)
                    Text("1×").tag(1.0)
                    Text("1.25×").tag(1.25)
                    Text("1.5×").tag(1.5)
                    Text("2×").tag(2.0)
                }

                Picker("Skip Interval", selection: $skipInterval) {
                    Text("5 sec").tag(5.0)
                    Text("10 sec").tag(10.0)
                    Text("15 sec").tag(15.0)
                    Text("30 sec").tag(30.0)
                }
            }
        }
        .navigationTitle("Playback Settings")
    }
}

```

---

## `VoiceTok/Extensions/Extensions.swift`

```swift
// Extensions.swift
// Shared utility extensions

import SwiftUI

// MARK: - View Extensions
extension View {
    /// Conditionally apply a transform
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Hide keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Color Helpers
extension Color {
    static let voiceTokOrange = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let voiceTokDark = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let voiceTokSurface = Color(red: 0.12, green: 0.12, blue: 0.14)
}

// MARK: - String Helpers
extension String {
    /// Truncate string with ellipsis
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength)) + "…"
    }

    /// Clean whitespace
    var cleaned: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Date Helpers
extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - TimeInterval Helpers
extension TimeInterval {
    var formattedDuration: String {
        let hours = Int(self) / 3600
        let mins = (Int(self) % 3600) / 60
        let secs = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - URL Helpers
extension URL {
    var isMediaFile: Bool {
        let ext = pathExtension.lowercased()
        return MediaLibraryService.supportedExtensions.contains(ext)
    }

    var isAudioOnly: Bool {
        let audioExts = Set(["mp3", "m4a", "wav", "aiff", "flac", "ogg", "wma", "aac"])
        return audioExts.contains(pathExtension.lowercased())
    }
}

// MARK: - Haptic Feedback
enum HapticFeedback {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

```

---

## `VoiceTok/Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Info -->
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>VoiceTok</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>

    <!-- Deployment -->
    <key>MinimumOSVersion</key>
    <string>17.0</string>
    <key>UILaunchScreen</key>
    <dict>
        <key>UIColorName</key>
        <string>AccentColor</string>
        <key>UIImageName</key>
        <string>LaunchIcon</string>
    </dict>

    <!-- Orientations -->
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>

    <!-- Permissions -->
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceTok needs microphone access for real-time speech transcription.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>VoiceTok uses speech recognition to transcribe media content.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>VoiceTok can import media files from your photo library.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>VoiceTok stores your media files and transcripts.</string>

    <!-- Background Audio -->
    <key>UIBackgroundModes</key>
    <array>
        <string>audio</string>
    </array>

    <!-- File Types Supported (Open In) -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Video</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.mpeg-4</string>
                <string>com.apple.quicktime-movie</string>
                <string>public.avi</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Audio</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>public.mp3</string>
                <string>com.apple.m4a-audio</string>
                <string>public.aiff-audio</string>
            </array>
        </dict>
    </array>

    <!-- App Transport Security (for Ollama local server) -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>

```

---

## `Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceTok",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "VoiceTok", targets: ["VoiceTok"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "VoiceTok",
            dependencies: ["WhisperKit"],
            path: "VoiceTok"
        )
    ]
)

```

---

## `Podfile`

```
# VoiceTok Podfile
# VLCKit is distributed via CocoaPods (not SPM)

platform :ios, '17.0'
use_frameworks!
inhibit_all_warnings!

target 'VoiceTok' do
  # VLC Media Player Framework
  pod 'MobileVLCKit', '~> 3.6'
  
  # Note: WhisperKit is added via Swift Package Manager
  # in Xcode: File > Add Package Dependencies
  # URL: https://github.com/argmaxinc/WhisperKit.git
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end

```

---


---
---


# VoiceTok — AI 快速上下文注入模板

> **使用方法**：将本文档内容直接粘贴到任何 AI 对话的开头，即可让 AI 快速理解项目全貌并开始工作。
> 
> 如果需要更深入的细节，可以追加提供以下文档：
> - `00-VoiceTok-AI-Master-Guide.md` — 完整架构与设计文档
> - `01-VoiceTok-API-Integration-Reference.md` — API 集成参考
> - `02-VoiceTok-Coding-Patterns-TaskGuide.md` — 代码模式与任务指南
> - `03-VoiceTok-Full-Source-Code.md` — 全部源代码

---

## 以下为快速上下文（复制粘贴到 AI 对话开头）

```
你正在协助开发一个名为 VoiceTok 的 iOS 应用。以下是项目的核心信息：

## 项目概述
VoiceTok 是一个 iOS 17+ 的 SwiftUI 应用，核心功能：
1. 通过 VLCKit (CocoaPods) 播放 100+ 音视频格式
2. 通过 WhisperKit (SPM) 在设备端离线转写语音为文本（带时间戳）
3. 将转写稿注入 LLM 上下文，支持 AI 对话（Claude/OpenAI/Ollama）

## 架构
- 模式：MVVM + Service Layer
- 全局状态：AppState (@MainActor, @EnvironmentObject)
- 线程：@MainActor + async/await + Combine (播放时间同步)

## 核心文件（19个）
App 层：VoiceTokApp.swift（入口）、AppState.swift（全局状态容器）
Model 层：MediaItem.swift（MediaItem, Transcript, TranscriptSegment, ChatMessage 等）
Service 层：
- TranscriptionService.swift — WhisperKit 封装（初始化/音频提取→16kHz WAV/转写/模型切换）
- MediaPlayerService.swift — Protocol 抽象 + AVPlayer 默认实现 + VLCKit 实现（注释态）
- ChatService.swift — 三 LLM 后端（Claude/OpenAI/Ollama），转写稿注入 system prompt
- MediaLibraryService.swift — 文件导入/沙盒存储/缩略图/UserDefaults 持久化
ViewModel 层：PlayerViewModel.swift — 播放↔转写同步（Combine throttle 200ms → 活跃段落索引）
View 层：ContentView(TabView), LibraryView(导入/列表), PlayerView(播放器+转写面板), ChatView(AI对话), SettingsView(配置)
Extensions：View/Color/String/Date/URL 扩展 + HapticFeedback

## 关键技术决策
- WhisperKit 音频输入要求：16kHz, 单声道, 16-bit PCM WAV
- VLCKit 通过 CocoaPods 引入（不支持 SPM），WhisperKit 通过 SPM 引入
- 播放器通过 MediaPlayerProtocol 协议抽象，可在 AVPlayer 和 VLCKit 之间切换
- Claude API 的 system prompt 是顶层参数（不在 messages 中），OpenAI/Ollama 的 system 是 messages[0]
- 转写完成后自动将完整转写稿（含每段时间戳）注入 ChatService 的 system prompt
- 播放时间通过 Combine 管线与转写面板实时同步（高亮+自动滚动）

## 代码规范
- @MainActor 标记所有 Service 和 ViewModel
- async/await 用于所有耗时操作
- 每个 Service 定义自己的 LocalizedError 枚举
- View 不超过 200 行，超出拆分子组件
- Codable + Hashable 用于所有数据模型

请基于以上上下文回答问题或编写代码。如果需要更多细节，请告诉我你需要哪个文件的完整源码。
```

---

## 场景化提示模板

### 场景 1：让 AI 添加新功能

```
[粘贴上面的快速上下文]

我需要在 VoiceTok 中添加以下功能：[描述功能]

请：
1. 分析需要修改哪些文件
2. 给出每个文件的具体修改（包含完整的修改后代码）
3. 说明是否需要新建文件
4. 列出可能的边界情况和需要注意的问题
```

### 场景 2：让 AI 排查问题

```
[粘贴上面的快速上下文]

我遇到以下问题：[描述问题]

相关错误日志：[粘贴日志]
相关代码文件：[粘贴代码]

请分析问题原因并给出修复方案。
```

### 场景 3：让 AI 进行 Code Review

```
[粘贴上面的快速上下文]

请 review 以下代码改动，检查：
1. 是否符合项目架构规范（MVVM + Service Layer）
2. 线程安全（@MainActor）
3. 错误处理是否完善
4. SwiftUI 视图模式是否正确
5. 是否有性能隐患

[粘贴代码]
```

### 场景 4：让 AI 编写测试

```
[粘贴上面的快速上下文]

请为以下模块编写单元测试：[模块名]

要求：
- 使用 XCTest 框架
- 覆盖核心逻辑和边界情况
- Mock 外部依赖（WhisperKit, URLSession）
- 异步测试使用 async/await
```

### 场景 5：让 AI 生成文档

```
[粘贴上面的快速上下文]

请为以下功能/模块生成：
- API 文档（方法签名、参数、返回值、使用示例）
- 行内注释
- README 章节

模块：[模块名或代码]
```

---

*本模板帮助你高效地将 VoiceTok 项目上下文注入到任何 AI 对话中。*

---
---


# VoiceTok — 项目状态与开发路线图

> **文档类型**：工程状态追踪 + 产品路线图  
> **最后更新**：2026-04-01  
> **当前版本**：v1.0.0（源码生成完毕，待 Xcode 工程集成）

---

## 一、当前版本状态（v1.0.0）

### 1.1 交付物清单

| 文件 | 行数 | 状态 |
|------|------|------|
| `VoiceTokApp.swift` | 16 | ✅ |
| `AppState.swift` | 46 | ✅ |
| `MediaItem.swift` | 153 | ✅ |
| `TranscriptionService.swift` | 225 | ✅ |
| `MediaPlayerService.swift` | 236 | ✅（VLCKit 注释态）|
| `ChatService.swift` | 240 | ✅ |
| `MediaLibraryService.swift` | 178 | ✅ |
| `PlayerViewModel.swift` | 115 | ✅ |
| `ContentView.swift` | 109 | ✅ |
| `LibraryView.swift` | 227 | ✅ |
| `PlayerView.swift` | 440 | ✅ |
| `ChatView.swift` | 278 | ✅ |
| `SettingsView.swift` | 210 | ✅ |
| `Extensions.swift` | 89 | ✅ |
| `Info.plist` + `Package.swift` + `Podfile` | — | ✅ |
| **合计** | **~4,789 行** | **✅** |

### 1.2 功能实现矩阵

| 功能 | 状态 |
|------|------|
| 多格式媒体导入（Files + URL）| ✅ |
| AVPlayer 播放 | ✅ |
| VLCKit 播放 | ⚠️ 代码已写，注释态，需 pod install 后激活 |
| WhisperKit 端侧转写 | ✅ |
| 转写进度显示 | ⚠️ 状态文字 OK，百分比始终 0%（TD-003）|
| 播放↔字幕实时同步 | ✅ Combine throttle 200ms |
| Claude / OpenAI / Ollama 对话 | ✅ |
| 快捷操作（总结/主题/笔记/翻译）| ✅ |
| 横竖屏自适应布局 | ✅ |
| 转写稿跨重启持久化 | ❌ 未完成（TD-001，P0）|
| API Key Keychain 安全存储 | ❌ 当前 UserDefaults（TD-004，P1）|
| Token 截断（超长转写稿）| ❌ 未实现（TD-005，P1）|
| 流式响应 | ❌ v1.1.0 计划 |

---

## 二、技术债（优先级排序）

### P0 — 阻断性（上线前必修）

**TD-001：转写结果未持久化**
- 位置：`PlayerViewModel.swift:startTranscription()`
- 修复：转写完成后调用 `mediaLibraryService.updateItem(updatedItem)`

**TD-002：PlayerView 转写完成不刷新**
- 位置：`PlayerView.swift:transcriptPanel`
- 修复：`mediaItem.transcript` → `viewModel.mediaItem?.transcript`

### P1 — 高优先级（v1.0.1）

**TD-003**：WhisperKit 进度回调未接入（始终 0%）  
**TD-006**：VLCKit 未激活（需 pod install + 取消注释）  
**TD-007**：SettingsView 无入口（ContentView toolbar 缺齿轮按钮）

### P2 — 中优先级（v1.1.0）

**TD-004**：API Key 迁移 Keychain  
**TD-005**：超长转写稿 Token 截断（见 02 文档 Task F）

---

## 三、Xcode 工程集成步骤

1. Xcode → New → App（SwiftUI, Swift, iOS 17+）
2. 将 `VoiceTok/` 目录拖入 Project Navigator，勾选 Target
3. `pod install` → 打开 `.xcworkspace`
4. File → Add Package → `https://github.com/argmaxinc/WhisperKit.git`
5. Build Settings: Bitcode=NO, Other Linker Flags=-ObjC
6. 合并 `Info.plist` 权限声明

---

## 四、开发路线图

| 版本 | 目标 | 关键功能 |
|------|------|---------|
| **v1.0.1** | 稳定性修复 | TD-001/002/003/006/007 |
| **v1.1.0** | 安全+质量 | Keychain、Token 截断、流式响应、单元测试 |
| **v1.2.0** | 功能扩展 | 实时转写、SRT 导出、HLS 流、批量队列 |
| **v2.0.0** | 平台拓展 | Speaker Diarization、macOS Catalyst、iCloud、Siri |

---
---

