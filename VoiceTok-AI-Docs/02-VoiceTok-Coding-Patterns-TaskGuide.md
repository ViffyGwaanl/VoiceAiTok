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
