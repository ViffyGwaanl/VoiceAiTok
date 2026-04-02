# VoiceTok — AI 开发指导主文档

> **文档用途**：本文档是 VoiceTok iOS 项目的完整 AI 指导手册。将本文档提供给任何 AI 助手（Claude、GPT、Copilot 等），即可让其全面理解项目架构、代码规范、技术决策，并能正确地进行代码开发、review 和问题排查。
>
> **最后更新**：2026-04-01  
> **项目版本**：1.0.0（源码已实现）  
> **目标平台**：iOS 17+ / iPadOS 17+  
> **实现状态**：✅ v1.0.0 全部 15 个 Swift 源文件已生成，待 Xcode 工程集成

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

---

## 十二、实现状态（v1.0.0）

> 所有源文件已于 2026-04-01 生成完毕，下表为各文件的实现状态。

### 12.1 文件实现清单

| 文件 | 状态 | 备注 |
|------|------|------|
| `VoiceTokApp.swift` | ✅ 完成 | @main 入口，dark mode 默认 |
| `AppState.swift` | ✅ 完成 | 全局状态容器，启动预热 WhisperKit |
| `MediaItem.swift` | ✅ 完成 | 8 个核心数据类型 |
| `TranscriptionService.swift` | ✅ 完成 | WhisperKit 封装，AVAssetReader WAV 提取 |
| `MediaPlayerService.swift` | ✅ 完成 | AVPlayer 默认实现；VLCKit 实现已写，注释态 |
| `ChatService.swift` | ✅ 完成 | Claude / OpenAI / Ollama 三后端 |
| `MediaLibraryService.swift` | ✅ 完成 | 文件导入、缩略图、UserDefaults 持久化 |
| `PlayerViewModel.swift` | ✅ 完成 | Combine 时间同步，转写协调 |
| `ContentView.swift` | ✅ 完成 | TabView 三 Tab，空状态视图 |
| `LibraryView.swift` | ✅ 完成 | 搜索/排序/多格式导入/左滑删除 |
| `PlayerView.swift` | ✅ 完成 | 横竖屏自适应，转写面板，导出 |
| `ChatView.swift` | ✅ 完成 | 气泡/快捷操作/输入栏/打字动画 |
| `SettingsView.swift` | ✅ 完成 | 18 种语言/模型/播放配置 |
| `Extensions.swift` | ✅ 完成 | View/Color/String/URL/Haptic 扩展 |
| `Info.plist` | ✅ 完成 | 权限/后台音频/文件类型关联 |
| `Package.swift` | ✅ 完成 | SPM WhisperKit 依赖声明 |
| `Podfile` | ✅ 完成 | CocoaPods MobileVLCKit 声明 |

### 12.2 Xcode 工程集成步骤（剩余工作）

以下步骤需在 Xcode 中手动完成，代码无需修改：

1. **创建 Xcode 工程**
   ```
   Xcode → File → New → Project → App
   名称: VoiceTok, Bundle ID: com.yourteam.voicetok
   界面: SwiftUI, 语言: Swift
   ```

2. **添加所有 Swift 源文件到 Target**
   - 将 `VoiceTok/` 目录拖入 Xcode Project Navigator
   - 确认所有 `.swift` 文件勾选到 `VoiceTok` Target

3. **安装 CocoaPods**
   ```bash
   cd VoiceTok && pod install
   open VoiceTok.xcworkspace   # 此后只用 .xcworkspace
   ```

4. **添加 WhisperKit via SPM**
   ```
   File → Add Package Dependencies
   URL: https://github.com/argmaxinc/WhisperKit.git
   版本: from 0.9.0
   ```

5. **Build Settings 配置**

   | 设置项 | 值 |
   |--------|---|
   | iOS Deployment Target | 17.0 |
   | Enable Bitcode | NO |
   | Other Linker Flags | -ObjC |
   | Swift Language Version | Swift 5.9 |

6. **Info.plist 集成**：将 `VoiceTok/Resources/Info.plist` 中的键值合并到 Xcode 工程 Info.plist

---

## 十三、已知技术债与待修复问题

### 13.1 高优先级（影响核心功能）

| # | 问题 | 影响 | 修复方向 |
|---|------|------|---------|
| 1 | 转写完成后未回写 `MediaLibraryService` | App 重启后转写结果丢失 | 在 `PlayerViewModel.startTranscription()` 完成后调用 `appState.mediaLibraryService.updateItem(updatedItem)` |
| 2 | `PlayerView` 的 `transcriptPanel` 使用 `let mediaItem`（参数绑定），转写完成后不会自动刷新 | 转写成功但面板不显示 | 改为读取 `viewModel.mediaItem?.transcript` 而非 `mediaItem.transcript` |
| 3 | WhisperKit 转写进度始终为 0% | `transcribing(progress: 0.0)` 无实际进度 | 使用 WhisperKit DecodingCallback 更新 `state = .transcribing(progress: p)` |

### 13.2 中优先级（安全与体验）

| # | 问题 | 影响 | 修复方向 |
|---|------|------|---------|
| 4 | API Key 存储在 `@AppStorage`（UserDefaults，明文） | 生产安全风险 | 迁移至 `KeychainAccess` 或 Security framework |
| 5 | 超长转写稿无 Token 截断 | 超出 LLM context window 导致 API 报错 | 参考文档 `02` 中 Task F 实现 `buildSystemContext(_:maxTokens:)` |
| 6 | VLCKit 注释未激活 | 仅能播放 AVFoundation 支持的格式 | `pod install` 后取消 `VLCPlayerService` 注释，在 `PlayerViewModel` 中切换 |

### 13.3 低优先级（体验优化）

| # | 问题 | 影响 |
|---|------|------|
| 7 | `ContentView` 顶层 `showSettings` 变量声明但无触发入口 | 设置页无法通过 Tab 外按钮打开 |
| 8 | `TypingIndicator` 的 `dotScale` 三点动画值相同（无波浪感） | 动画不够流畅 |
| 9 | `LibraryView` 的 URL 导入不验证 media 格式 | 可导入非媒体 URL |
| 10 | 无 iCloud/Files 应用备份支持 | 重装 App 后数据丢失 |

---

## 十四、开发路线图

### v1.0.1 — 稳定性修复（近期）

- [ ] **#1** 转写回写 MediaLibraryService，持久化跨重启
- [ ] **#2** `PlayerView` 绑定修复，转写完成后即时刷新面板
- [ ] **#3** WhisperKit 进度回调接入（实时百分比显示）
- [ ] **#6** 激活 VLCPlayerService（取消注释 + 测试 MKV/AVI 播放）
- [ ] SettingsView 补充入口（ContentView toolbar 齿轮按钮）

### v1.1.0 — 安全与质量提升

- [ ] **#4** API Key 迁移至 Keychain
- [ ] **#5** Token 截断策略（80k token 上限，尾部省略摘要）
- [ ] Claude/OpenAI 流式响应（`stream: true`，实时打字机输出）
- [ ] 媒体库 transcript/chatHistory 持久化（目前仅 metadata 存 UserDefaults）
- [ ] 单元测试：TranscriptSegment 格式化、ChatService 消息构建、PlayerViewModel 段落匹配

### v1.2.0 — 功能扩展

- [ ] **实时转写**：麦克风输入经 WhisperKit streaming API 实时出字幕
- [ ] **字幕导出**：SRT / VTT / LRC 格式导出（`exportSRT()` 骨架已在扩展指南 9.4）
- [ ] **网络流媒体**：VLCKit 播放 HLS / RTSP 流地址
- [ ] **多轮对话上下文优化**：对超长转写稿实现 RAG 检索式片段注入
- [ ] **批量转写队列**：导入多文件时后台排队转写

### v2.0.0 — 平台拓展（长期）

- [ ] **Speaker Diarization**：`speakerLabel` 字段激活（Argmax Pro SDK 或 pyannote）
- [ ] **macOS / Catalyst**：SwiftUI 跨平台适配
- [ ] **iCloud Drive 同步**：转写稿 + 对话历史跨设备同步
- [ ] **Shortcuts 集成**：App Intents 支持「转写 + 总结」快捷指令
- [ ] **watchOS 伴侣应用**：播放控制 + 转写进度展示

---

*本文档由 VoiceTok 项目自动生成，可直接提供给 AI 助手作为开发指导。*  
*v1.0.0 源码实现完成于 2026-04-01。*
