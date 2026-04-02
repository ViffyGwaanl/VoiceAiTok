// PlayerViewModel.swift
// Coordinates playback, transcription, and transcript navigation

import SwiftUI
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - Dependencies
    #if canImport(MobileVLCKit)
    let player = VLCPlayerService()
    #else
    let player = AVMediaPlayerService()
    #endif
    let transcriptionService: TranscriptionService
    let chatService: ChatService
    let mediaLibraryService: MediaLibraryService

    // MARK: - State
    @Published var mediaItem: MediaItem?
    @Published var transcriptionState: TranscriptionState = .idle
    @Published var activeSegmentIndex: Int?
    @Published var showTranscript = true
    @Published var showChat = false

    private var cancellables = Set<AnyCancellable>()

    init(transcriptionService: TranscriptionService, chatService: ChatService, mediaLibraryService: MediaLibraryService) {
        self.transcriptionService = transcriptionService
        self.chatService = chatService
        self.mediaLibraryService = mediaLibraryService
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
              let url = item.fileURL ?? URL(fileURLWithPath: item.filePath) as URL? else { return }

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

            // Persist transcript to library (survives app restart)
            mediaLibraryService.updateItem(updatedItem)

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
