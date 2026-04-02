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
