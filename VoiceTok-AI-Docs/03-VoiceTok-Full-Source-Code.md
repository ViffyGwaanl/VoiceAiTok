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

