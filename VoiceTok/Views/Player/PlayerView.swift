// PlayerView.swift
// Full-featured media player with integrated transcript sidebar

import SwiftUI
import AVKit

struct PlayerView: View {
    let mediaItem: MediaItem
    let transcriptionService: TranscriptionService
    let chatService: ChatService
    let mediaLibraryService: MediaLibraryService

    @StateObject private var viewModel: PlayerViewModel
    @State private var showModelPicker = false
    @State private var selectedModel = "base"

    init(mediaItem: MediaItem, transcriptionService: TranscriptionService, chatService: ChatService, mediaLibraryService: MediaLibraryService) {
        self.mediaItem = mediaItem
        self.transcriptionService = transcriptionService
        self.chatService = chatService
        self.mediaLibraryService = mediaLibraryService
        _viewModel = StateObject(wrappedValue: PlayerViewModel(
            transcriptionService: transcriptionService,
            chatService: chatService,
            mediaLibraryService: mediaLibraryService
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
                            .frame(height: (viewModel.mediaItem ?? mediaItem).mediaType == .video ? 280 : 200)
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
            #if canImport(MobileVLCKit)
            VLCVideoRepresentable(playerService: viewModel.player)
            #else
            if let avPlayer = viewModel.player.player {
                VideoPlayer(player: avPlayer)
                    .disabled(true) // We use custom controls
            } else {
                Rectangle()
                    .fill(.black)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
            #endif
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
                        Button("\(rate, specifier: "%.2g")x") {
                            viewModel.player.playbackRate = Float(rate)
                        }
                    }
                } label: {
                    Text("\(viewModel.player.playbackRate, specifier: "%.2g")x")
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
        let currentItem = viewModel.mediaItem ?? mediaItem
        VStack(spacing: 0) {
            // Panel Header
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if viewModel.hasTranscript {
                    if let lang = currentItem.transcript?.language {
                        Text(lang.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Text("\(currentItem.transcript?.segments.count ?? 0) segments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Content
            if let transcript = currentItem.transcript {
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
        let currentItem = viewModel.mediaItem ?? mediaItem
        guard let transcript = currentItem.transcript else { return }

        var text = "# \(currentItem.title)\n"
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
