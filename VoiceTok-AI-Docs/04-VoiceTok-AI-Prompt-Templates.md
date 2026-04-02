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
