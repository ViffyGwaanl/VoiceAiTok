// TranscriptionService.swift
// Multi-provider speech transcription: WhisperKit, Apple Speech, OpenAI API

import Foundation
import WhisperKit
import AVFoundation
import Speech

// MARK: - Transcription Provider

enum TranscriptionProvider: String, CaseIterable, Codable {
    case whisperKit = "whisperKit"
    case appleSpeech = "appleSpeech"
    case openAIAPI = "openAIAPI"

    var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .appleSpeech: return "Apple"
        case .openAIAPI: return "OpenAI API"
        }
    }

    var description: String {
        switch self {
        case .whisperKit: return "On-device AI transcription. High accuracy, requires model download."
        case .appleSpeech: return "Apple's on-device speech recognition. No download needed, requires iOS permission."
        case .openAIAPI: return "OpenAI Whisper API. Cloud-based, requires OpenAI API key."
        }
    }
}

// MARK: - TranscriptionService

@MainActor
final class TranscriptionService: ObservableObject {
    // MARK: - Published State
    @Published var state: TranscriptionState = .idle
    @Published var currentTranscript: Transcript?

    // MARK: - Model Management State
    @Published var availableModels: [String] = []
    @Published var recommendedModel: String = "base"
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var downloadingModelName: String?
    @Published var localModelStates: [String: ModelDownloadState] = [:]

    enum ModelDownloadState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
    }

    // MARK: - WhisperKit
    private var whisperKit: WhisperKit?
    private var isInitialized = false

    // MARK: - Configuration
    struct Config {
        var provider: TranscriptionProvider = .whisperKit
        var modelName: String = "base"
        var language: String? = nil        // nil = auto-detect
        var task: String = "transcribe"    // "transcribe" or "translate"
        var wordTimestamps: Bool = true
        var chunkLength: Int = 30
        var openAIAPIKey: String? = nil
    }

    var config = Config()

    // MARK: - Initialization (WhisperKit)
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

    // MARK: - Main Entry Point

    /// Transcribe media at the given URL using the configured provider.
    func transcribeMedia(at url: URL) async throws -> Transcript {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.audioExtractionFailed
        }

        switch config.provider {
        case .whisperKit:
            return try await transcribeWithWhisperKit(mediaURL: url)
        case .appleSpeech:
            return try await transcribeWithAppleSpeech(mediaURL: url)
        case .openAIAPI:
            guard let apiKey = config.openAIAPIKey, !apiKey.isEmpty else {
                throw TranscriptionError.missingAPIKey
            }
            return try await transcribeWithOpenAIAPI(mediaURL: url, apiKey: apiKey)
        }
    }

    // MARK: - WhisperKit Path

    private func transcribeWithWhisperKit(mediaURL: URL) async throws -> Transcript {
        if !isInitialized {
            state = .preparing
            try await initialize()
        }

        state = .extractingAudio
        let audioURL = try await extractAudio(from: AVURLAsset(url: mediaURL))
        return try await transcribeAudioWithWhisperKit(audioURL: audioURL)
    }

    private func transcribeAudioWithWhisperKit(audioURL: URL) async throws -> Transcript {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.notInitialized
        }

        state = .transcribing(progress: 0.0)
        let audioDuration = await getAudioDuration(url: audioURL)

        let options = DecodingOptions(
            task: .transcribe,
            language: config.language,
            wordTimestamps: config.wordTimestamps
        )

        let windowDuration = 30.0
        let callback: TranscriptionCallback = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, audioDuration > 0 else { return }
                let processed = Double(progress.windowId + 1) * windowDuration
                let pct = min(processed / audioDuration, 0.99)
                self.state = .transcribing(progress: pct)
            }
            return nil
        }

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: callback
        )
        guard !results.isEmpty else {
            throw TranscriptionError.transcriptionFailed
        }

        var segments: [TranscriptSegment] = []
        var fullText = ""

        for result in results {
            for segment in result.segments {
                let cleanedText = Self.stripTimestampTokens(segment.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedText.isEmpty else { continue }
                let seg = TranscriptSegment(
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    text: cleanedText
                )
                segments.append(seg)
                fullText += cleanedText + " "
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
    }

    // MARK: - Apple Speech Path

    private func transcribeWithAppleSpeech(mediaURL: URL) async throws -> Transcript {
        // Request permission
        let authorized = await requestSpeechPermission()
        guard authorized else {
            throw TranscriptionError.permissionDenied
        }

        // Determine locale
        let localeID = config.language.map { Locale.init(identifier: $0) } ?? Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: localeID), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        state = .transcribing(progress: 0.0)

        let request = SFSpeechURLRecognitionRequest(url: mediaURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let resumeOnce: (Result<Transcript, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error {
                    resumeOnce(.failure(error))
                    return
                }
                guard let result, result.isFinal else { return }

                let rawSegments = result.bestTranscription.segments
                var segments: [TranscriptSegment] = []
                var fullText = result.bestTranscription.formattedString

                // Group word-level segments into sentence-like chunks (~15 words each)
                let chunkSize = 15
                var idx = 0
                while idx < rawSegments.count {
                    let chunk = Array(rawSegments[idx..<min(idx + chunkSize, rawSegments.count)])
                    let text = chunk.map(\.substring).joined(separator: " ")
                    let startTime = TimeInterval(chunk.first!.timestamp)
                    let lastSeg = chunk.last!
                    let endTime = TimeInterval(lastSeg.timestamp + lastSeg.duration)
                    segments.append(TranscriptSegment(startTime: startTime, endTime: endTime, text: text))
                    idx += chunkSize
                }

                Task { @MainActor [weak self] in
                    self?.state = .completed
                    let transcript = Transcript(
                        segments: segments,
                        fullText: fullText,
                        language: self?.config.language,
                        dateCreated: Date()
                    )
                    self?.currentTranscript = transcript
                    resumeOnce(.success(transcript))
                }
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - OpenAI API Path

    private func transcribeWithOpenAIAPI(mediaURL: URL, apiKey: String) async throws -> Transcript {
        state = .extractingAudio
        let asset = AVURLAsset(url: mediaURL)
        let audioURL = try await extractAudio(from: asset)

        state = .transcribing(progress: 0.1)

        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audioData = try Data(contentsOf: audioURL)

        // file field
        body.appendFormField(boundary: boundary, name: "file", fileName: "audio.wav", mimeType: "audio/wav", data: audioData)
        // model field
        body.appendFormString(boundary: boundary, name: "model", value: "whisper-1")
        // response_format
        body.appendFormString(boundary: boundary, name: "response_format", value: "verbose_json")
        // timestamp_granularities
        body.appendFormString(boundary: boundary, name: "timestamp_granularities[]", value: "segment")
        // language (optional)
        if let language = config.language, !language.isEmpty {
            body.appendFormString(boundary: boundary, name: "language", value: language)
        }
        body.append("--\(boundary)--\r\n".utf8Data)

        request.httpBody = body
        state = .transcribing(progress: 0.3)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.apiError("Invalid response")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranscriptionError.apiError(msg)
        }

        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)

        let segments: [TranscriptSegment] = (decoded.segments ?? []).compactMap { seg in
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(startTime: seg.start, endTime: seg.end, text: text)
        }

        let transcript = Transcript(
            segments: segments,
            fullText: decoded.text,
            language: decoded.language ?? config.language,
            dateCreated: Date()
        )

        state = .completed
        currentTranscript = transcript
        return transcript
    }

    // MARK: - Audio Extraction (shared)

    private func extractAudio(from asset: AVURLAsset) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw TranscriptionError.noAudioTrack
        }

        return try await convertToWav(asset: asset, outputURL: outputURL)
    }

    private func convertToWav(asset: AVURLAsset, outputURL: URL) async throws -> URL {
        let reader = try AVAssetReader(asset: asset)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw TranscriptionError.noAudioTrack
        }

        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false      // Required on device
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writer.add(writerInput)

        guard reader.startReading() else { throw TranscriptionError.audioExtractionFailed }
        guard writer.startWriting() else { throw TranscriptionError.audioExtractionFailed }
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            let resumeOnce: (Result<Void, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.export")) {
                while writerInput.isReadyForMoreMediaData {
                    guard reader.status == .reading else {
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        resumeOnce(.failure(TranscriptionError.audioExtractionFailed))
                        return
                    }
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                resumeOnce(.success(()))
                            } else {
                                resumeOnce(.failure(TranscriptionError.audioExtractionFailed))
                            }
                        }
                        return
                    }
                }
            }
        }

        return outputURL
    }

    // MARK: - Audio Duration Helper

    private func getAudioDuration(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds.isNaN ? 0 : duration.seconds
        } catch {
            return 0
        }
    }

    // MARK: - Token Stripping

    /// Strips WhisperKit special timestamp tokens like <|6.00|> from text.
    static func stripTimestampTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[\\d.]+\\|>", with: "", options: .regularExpression)
    }

    // MARK: - Model Management

    func fetchModelInfo() async {
        let recommended = WhisperKit.recommendedModels()
        recommendedModel = recommended.default

        do {
            let models = try await WhisperKit.fetchAvailableModels()
            availableModels = models.sorted()
        } catch {
            availableModels = Self.fallbackModels
        }

        await refreshLocalModelStates()
    }

    func refreshLocalModelStates() async {
        let cacheDir = modelCacheBaseURL
        for model in availableModels {
            if isModelCached(model, in: cacheDir) {
                localModelStates[model] = .downloaded
            } else if localModelStates[model] == nil {
                localModelStates[model] = .notDownloaded
            }
        }
    }

    func downloadModel(_ modelName: String) async throws {
        isDownloading = true
        downloadingModelName = modelName
        downloadProgress = 0
        localModelStates[modelName] = .downloading(progress: 0)

        defer {
            isDownloading = false
            downloadingModelName = nil
        }

        do {
            _ = try await WhisperKit.download(variant: modelName) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let pct = progress.fractionCompleted
                    self.downloadProgress = pct
                    self.localModelStates[modelName] = .downloading(progress: pct)
                }
            }
            localModelStates[modelName] = .downloaded
        } catch {
            localModelStates[modelName] = .notDownloaded
            throw error
        }
    }

    func switchModel(to modelName: String) async throws {
        config.modelName = modelName
        isInitialized = false
        whisperKit = nil
        try await initialize()
        await refreshLocalModelStates()
    }

    func deleteModel(_ modelName: String) {
        let cacheDir = modelCacheBaseURL
        let fm = FileManager.default

        let repoDir = cacheDir.appendingPathComponent("models--argmaxinc--whisperkit-coreml")
        let snapshotsDir = repoDir.appendingPathComponent("snapshots")

        guard let snapshots = try? fm.contentsOfDirectory(atPath: snapshotsDir.path) else { return }
        for snapshot in snapshots {
            let snapshotPath = snapshotsDir.appendingPathComponent(snapshot)
            guard let contents = try? fm.contentsOfDirectory(atPath: snapshotPath.path) else { continue }
            for dir in contents where dir.contains(modelName) {
                let fullPath = snapshotPath.appendingPathComponent(dir)
                try? fm.removeItem(at: fullPath)
            }
        }

        localModelStates[modelName] = .notDownloaded
    }

    static func estimatedSize(for model: String) -> String {
        estimatedSizeOptional(for: model) ?? ""
    }

    static func estimatedSizeOptional(for model: String) -> String? {
        let sizes: [String: Int] = [
            "tiny": 75, "tiny.en": 75,
            "base": 145, "base.en": 145,
            "small": 480, "small.en": 480,
            "medium": 1500, "medium.en": 1500,
            "large-v3": 3100, "large-v3-turbo": 1600,
            "distil-large-v3": 1600
        ]
        guard let mb = sizes.first(where: { model.contains($0.key) })?.value else { return nil }
        return mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
    }

    // MARK: - Private Helpers

    private var modelCacheBaseURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface")
    }

    private func isModelCached(_ modelName: String, in cacheDir: URL) -> Bool {
        let fm = FileManager.default
        let repoDir = cacheDir.appendingPathComponent("models--argmaxinc--whisperkit-coreml")
        let snapshotsDir = repoDir.appendingPathComponent("snapshots")

        guard let snapshots = try? fm.contentsOfDirectory(atPath: snapshotsDir.path) else { return false }
        for snapshot in snapshots {
            let snapshotPath = snapshotsDir.appendingPathComponent(snapshot)
            guard let contents = try? fm.contentsOfDirectory(atPath: snapshotPath.path) else { continue }
            if contents.contains(where: { $0.contains(modelName) }) { return true }
        }
        return false
    }

    static let fallbackModels = [
        "tiny", "tiny.en",
        "base", "base.en",
        "small", "small.en",
        "medium", "medium.en",
        "large-v3", "distil-large-v3"
    ]
}

// MARK: - OpenAI Response Models

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
    let language: String?
    let segments: [OpenAISegment]?

    struct OpenAISegment: Decodable {
        let start: Double
        let end: Double
        let text: String
    }
}

// MARK: - Multipart Form Helpers

private extension Data {
    mutating func appendFormField(boundary: String, name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".utf8Data)
        append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        append(data)
        append("\r\n".utf8Data)
    }

    mutating func appendFormString(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        append(value.utf8Data)
        append("\r\n".utf8Data)
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case notInitialized
    case transcriptionFailed
    case audioExtractionFailed
    case noAudioTrack
    case invalidAudioFormat
    case permissionDenied
    case recognizerUnavailable
    case missingAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: return String(localized: "WhisperKit is not initialized")
        case .transcriptionFailed: return String(localized: "Transcription failed")
        case .audioExtractionFailed: return String(localized: "Could not extract audio from media")
        case .noAudioTrack: return String(localized: "No audio track found in media")
        case .invalidAudioFormat: return String(localized: "Invalid audio format")
        case .permissionDenied: return String(localized: "Speech recognition permission denied. Enable in Settings.")
        case .recognizerUnavailable: return String(localized: "Speech recognizer unavailable for this language")
        case .missingAPIKey: return String(localized: "OpenAI API key is required. Set it in Transcription Settings.")
        case .apiError(let msg): return String(format: String(localized: "API error: %@"), msg)
        }
    }
}
