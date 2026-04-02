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
