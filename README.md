# VoiceTok

AI-Powered Media Player with Transcription & Chat for iOS.

## Features

- **Universal Media Playback** - VLCKit supports 100+ audio/video formats (MKV, AVI, FLAC, etc.)
- **On-Device Transcription** - WhisperKit runs OpenAI Whisper locally on Apple Neural Engine
- **AI Chat** - Chat with AI about transcribed content (Claude, OpenAI, Ollama)

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (iOS 17+) |
| Media Playback | MobileVLCKit (CocoaPods) |
| Transcription | WhisperKit (SPM) |
| AI Chat | Claude API / OpenAI API / Ollama |

## Build

```bash
git clone <repo-url> VoiceTok && cd VoiceTok
pod install
open VoiceTok.xcworkspace
# Xcode: File > Add Package > https://github.com/argmaxinc/WhisperKit.git
# Select Team > Build & Run
```

Requires: macOS 14+, Xcode 15+, iOS 17+ device (WhisperKit needs Neural Engine).

## Architecture

MVVM + Service Layer with `AppState` as global dependency container via `@EnvironmentObject`.

## License

MIT
