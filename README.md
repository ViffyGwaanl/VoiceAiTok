# VoiceTok

**AI-powered iOS media player with multi-provider transcription and AI chat.**

Import any audio or video file → choose a transcription provider → chat with Claude/OpenAI/Ollama about the content.

---

## Features

| Feature | Status |
|---------|--------|
| Universal media playback (100+ formats via VLCKit) | ✅ |
| On-device transcription — WhisperKit (Neural Engine) | ✅ |
| On-device transcription — Apple SFSpeechRecognizer (no download) | ✅ |
| Cloud transcription — OpenAI Whisper API | ✅ |
| Real-time transcription progress with word-level timestamps | ✅ |
| Transcription provider/model/language picker in Player UI | ✅ |
| AI chat about transcribed content (Claude, OpenAI, Ollama, OpenAI-compatible) | ✅ |
| Streaming AI responses (SSE) | ✅ |
| Multi-provider AI settings (add unlimited providers) | ✅ |
| WhisperKit model download & management UI | ✅ |
| Media library with search, sort, thumbnail generation | ✅ |
| Transcript export (Markdown) | ✅ |
| Secure API key storage (iOS Keychain) | ✅ |
| Simplified Chinese localization (zh-Hans) | ✅ |
| Background audio playback | ✅ |

---

## Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| UI | SwiftUI (iOS 17+) | MVVM, dark mode |
| Media Playback | MobileVLCKit 3.7 (CocoaPods) | 100+ formats |
| Transcription | WhisperKit 0.18 (SPM) + SFSpeechRecognizer + OpenAI API | Three providers |
| AI Chat | Claude API / OpenAI API / Ollama | Streaming SSE |
| Persistence | UserDefaults JSON + iOS Keychain | Library + API keys |
| Architecture | MVVM + Service Layer | AppState DI container |

---

## Build & Run

### Prerequisites
- macOS 14+ (Sonoma or later)
- Xcode 16+
- iOS 17+ physical device (WhisperKit requires Neural Engine for best performance)
- CocoaPods: `sudo gem install cocoapods`

### Steps

```bash
# 1. Clone
git clone https://github.com/ViffyGwaanl/VoiceAiTok.git
cd VoiceAiTok

# 2. Install CocoaPods dependencies (MobileVLCKit)
pod install

# 3. Open workspace (NOT .xcodeproj)
open VoiceTok.xcworkspace
```

In Xcode:
1. **Signing**: Targets → VoiceTok → Signing & Capabilities → set your Development Team
2. **Build & Run**: Select your iPhone → ⌘R

WhisperKit (SPM) and all transitive dependencies resolve automatically on first build.

### Simulator Build (no signing required)

```bash
xcodebuild build \
  -workspace VoiceTok.xcworkspace \
  -scheme VoiceTok \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

> **Note:** WhisperKit model inference runs on simulator but is CPU-only (no Neural Engine). Use a physical device for production-quality transcription speed.

---

## Architecture

```
VoiceTok/
├── App/
│   ├── VoiceTokApp.swift         # @main entry, injects AppState
│   └── AppState.swift            # Global DI container (@EnvironmentObject)
├── Models/
│   └── MediaItem.swift           # MediaItem, Transcript, ChatMessage, enums
├── Services/
│   ├── MediaLibraryService.swift # Import, thumbnail, persistence
│   ├── MediaPlayerService.swift  # VLCPlayerService + AVMediaPlayerService
│   ├── TranscriptionService.swift# Multi-provider: WhisperKit / Apple Speech / OpenAI API
│   ├── ChatService.swift         # Claude/OpenAI/Ollama + SSE streaming
│   └── KeychainService.swift     # Secure API key storage
├── ViewModels/
│   └── PlayerViewModel.swift     # Playback + transcription coordination
├── Views/
│   ├── ContentView.swift         # TabView shell
│   ├── Library/LibraryView.swift # Media library (search, sort, import)
│   ├── Player/PlayerView.swift   # Player + transcript panel + TranscriptionSettingsSheet
│   ├── Chat/ChatView.swift       # AI chat (streaming, copy, regenerate, stop)
│   └── Settings/
│       ├── SettingsView.swift           # Global settings
│       ├── AIProviderListView.swift     # Manage AI providers list
│       ├── AIProviderDetailView.swift   # Add/edit provider (model fetch, key test)
│       └── ModelManagementView.swift    # WhisperKit model download UI
├── Extensions/Extensions.swift  # View/Color/URL/Time helpers
└── Resources/
    ├── Info.plist
    └── zh-Hans.lproj/            # Simplified Chinese localization
        ├── Localizable.strings
        └── InfoPlist.strings
```

**Key design decisions:**
- `AppState` as single `@StateObject` at root — all services injected via `@EnvironmentObject`
- `TranscriptionProvider` enum routes `transcribeMedia(at:)` to WhisperKit / Apple Speech / OpenAI API
- `PlayerViewModel.onTranscriptReady` callback propagates transcript to `appState.activeMediaItem` so the Chat tab unlocks immediately after transcription
- WhisperKit timestamp tokens (`<|6.00|>`) stripped via regex before building `TranscriptSegment`
- `#if canImport(MobileVLCKit)` conditional compilation — app builds with AVPlayer fallback if VLCKit absent
- Chat context: transcript injected as system message, token-truncated at ~80k tokens

---

## Transcription Providers

Access via **Player → ⋯ → Transcription Settings**

| Provider | Model | Notes |
|----------|-------|-------|
| **WhisperKit** | tiny / base / small / medium / large-v3 | On-device, Neural Engine, requires download |
| **Apple Speech** | System | On-device, no download, iOS permission required |
| **OpenAI API** | whisper-1 | Cloud, requires OpenAI API key |

Language can be set to Auto-detect or pinned to any of 13 supported languages.

---

## AI Chat Configuration

Open **Settings → AI Providers** and add or configure providers:

| Field | Description |
|-------|-------------|
| Provider Type | Claude, OpenAI, Ollama, or OpenAI-compatible |
| API Key | Stored securely in iOS Keychain |
| Base URL | Custom endpoint for self-hosted / proxy APIs |
| Model | Fetched live from provider, or entered manually |
| Temperature / Top-P / Max Tokens | Per-provider tuning |

---

## WhisperKit Models

| Model | Size | Notes |
|-------|------|-------|
| tiny | ~75 MB | Fastest, lowest accuracy |
| base | ~145 MB | Recommended for most devices |
| small | ~480 MB | Good balance |
| medium | ~1.5 GB | High accuracy |
| large-v3 | ~3.1 GB | Best quality, requires A17+ |

---

## Roadmap

### v1.1 (Next)
- [ ] iCloud sync for transcripts and library metadata
- [ ] Share extension (transcribe from Share Sheet)
- [ ] SRT / JSON / plain-text export formats
- [ ] Speaker diarization (multi-speaker detection)

### v1.2
- [ ] Widget — now-playing info + quick transcribe
- [ ] Siri Shortcuts integration
- [ ] Podcast/YouTube URL import with direct stream transcription

### v2.0
- [ ] iPad split-view: video + transcript + chat simultaneously
- [ ] macOS (Catalyst) support
- [ ] Batch transcription queue
- [ ] Custom AI system prompts per media item

---

## License

MIT — see [LICENSE](LICENSE)
