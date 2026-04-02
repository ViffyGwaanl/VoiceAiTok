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
        case .notInitialized: return String(localized: "WhisperKit is not initialized")
        case .transcriptionFailed: return String(localized: "Transcription failed")
        case .audioExtractionFailed: return String(localized: "Could not extract audio from media")
        case .noAudioTrack: return String(localized: "No audio track found in media")
        case .invalidAudioFormat: return String(localized: "Invalid audio format")
        }
    }
}
