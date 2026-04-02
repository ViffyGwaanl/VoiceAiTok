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

        // Get audio duration for progress estimation
        let audioDuration = await getAudioDuration(url: audioURL)

        do {
            let options = DecodingOptions(
                task: .transcribe,
                language: config.language,
                wordTimestamps: config.wordTimestamps
            )

            // Progress callback: each window is ~30s; use windowId as proxy for progress
            let windowDuration = 30.0
            let callback: TranscriptionCallback = { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, audioDuration > 0 else { return }
                    let processed = Double(progress.windowId + 1) * windowDuration
                    let pct = min(processed / audioDuration, 0.99)
                    self.state = .transcribing(progress: pct)
                }
                return nil // nil = continue transcribing
            }

            let results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options,
                callback: callback
            )
            guard !results.isEmpty else {
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

    // MARK: - Model Management

    /// Fetch recommended model for this device and available model list
    func fetchModelInfo() async {
        // Get device-recommended models
        let recommended = WhisperKit.recommendedModels()
        recommendedModel = recommended.default

        // Fetch available models from remote
        do {
            let models = try await WhisperKit.fetchAvailableModels()
            availableModels = models.sorted()
        } catch {
            // Fallback to hardcoded list
            availableModels = Self.fallbackModels
        }

        // Check which models are already cached
        await refreshLocalModelStates()
    }

    /// Scan local cache to determine which models are downloaded
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

    /// Download a specific model with progress tracking
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

    /// Switch to a different model (downloads if needed, then initializes)
    func switchModel(to modelName: String) async throws {
        config.modelName = modelName
        isInitialized = false
        whisperKit = nil
        try await initialize()
        await refreshLocalModelStates()
    }

    /// Delete a cached model from disk
    func deleteModel(_ modelName: String) {
        let cacheDir = modelCacheBaseURL
        let fm = FileManager.default

        // Scan for snapshot directories containing this model variant
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

    /// Get estimated size for a model (rough estimates in MB)
    static func estimatedSize(for model: String) -> String {
        let sizes: [String: Int] = [
            "tiny": 75, "tiny.en": 75,
            "base": 145, "base.en": 145,
            "small": 480, "small.en": 480,
            "medium": 1500, "medium.en": 1500,
            "large-v3": 3100, "large-v3-turbo": 1600,
            "distil-large-v3": 1600
        ]
        if let mb = sizes.first(where: { model.contains($0.key) })?.value {
            return mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
        }
        return ""
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
            if contents.contains(where: { $0.contains(modelName) }) {
                return true
            }
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

// MARK: - Errors
enum TranscriptionError: LocalizedError {
    case notInitialized
    case transcriptionFailed
    case audioExtractionFailed
    case noAudioTrack
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .notInitialized: return String(localized: "WhisperKit is not initialized")
        case .transcriptionFailed: return String(localized: "Transcription failed")
        case .audioExtractionFailed: return String(localized: "Could not extract audio from media")
        case .noAudioTrack: return String(localized: "No audio track found in media")
        case .invalidAudioFormat: return String(localized: "Invalid audio format")
        }
    }
}
