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
