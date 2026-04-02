// ShareViewController.swift
// VoiceTok Share Extension — copies shared audio/video into the App Group container.
// The main app imports them the next time it enters the foreground.

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    // MARK: - Constants
    private static let appGroupID  = "group.com.voicetok.app"
    private static let inboxFolder = "ShareInbox"
    private static let supportedExtensions: Set<String> = [
        "mp4", "m4v", "mov", "avi", "mkv", "ts", "flv", "wmv", "webm",
        "mp3", "m4a", "wav", "aiff", "flac", "ogg", "wma", "aac"
    ]
    // Ordered from most specific to broadest so the first match wins
    private static let mediaUTIs: [String] = [
        UTType.mpeg4Movie.identifier,
        UTType.quickTimeMovie.identifier,
        "com.apple.quicktime-movie",
        "public.avi",
        UTType.movie.identifier,
        UTType.mpeg4Audio.identifier,
        UTType.mp3.identifier,
        "com.apple.m4a-audio",
        UTType.wav.identifier,
        UTType.aiff.identifier,
        "public.flac",
        UTType.audio.identifier,
    ]

    // MARK: - Thread-safe counter
    private let countQueue = DispatchQueue(label: "voicetok.share.counter")
    private var copiedCount = 0

    // MARK: - UI
    private let card: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 20
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.18
        v.layer.shadowRadius = 16
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconLabel: UILabel = {
        let l = UILabel()
        l.text = "🎙"
        l.font = .systemFont(ofSize: 36)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "VoiceTok"
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.text = NSLocalizedString("Importing…", comment: "")
        l.font = .systemFont(ofSize: 14)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let spinner: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .medium)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        copySharedFiles()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)

        view.addSubview(card)
        card.addSubview(iconLabel)
        card.addSubview(titleLabel)
        card.addSubview(spinner)
        card.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 220),
            card.heightAnchor.constraint(equalToConstant: 160),

            iconLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            iconLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            spinner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
        ])

        spinner.startAnimating()
    }

    // MARK: - Copy Logic
    private func copySharedFiles() {
        guard
            let inputItems = extensionContext?.inputItems as? [NSExtensionItem],
            let inboxURL = Self.makeInboxURL()
        else {
            finish(success: false)
            return
        }

        let providers = inputItems.flatMap { $0.attachments ?? [] }
        let mediaProviders = providers.filter { provider in
            Self.mediaUTIs.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }

        guard !mediaProviders.isEmpty else {
            finish(success: false)
            return
        }

        let group = DispatchGroup()

        for provider in mediaProviders {
            guard let uti = Self.mediaUTIs.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else { continue }

            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: uti) { [weak self] url, _ in
                defer { group.leave() }
                guard let self, let url else { return }

                let ext = url.pathExtension.lowercased()
                guard Self.supportedExtensions.contains(ext) else { return }

                let dest = Self.uniqueDest(for: url, in: inboxURL)
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    self.countQueue.sync { self.copiedCount += 1 }
                } catch {
                    print("[ShareExt] Copy failed: \(error)")
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(success: (self?.copiedCount ?? 0) > 0)
        }
    }

    private func finish(success: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            spinner.stopAnimating()
            iconLabel.text = success ? "✅" : "⚠️"
            if success {
                let n = copiedCount
                statusLabel.text = n == 1
                    ? NSLocalizedString("Added to library", comment: "")
                    : String(format: NSLocalizedString("Added %d files", comment: ""), n)
            } else {
                statusLabel.text = NSLocalizedString("Unsupported format", comment: "")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    // MARK: - Path Helpers
    private static func makeInboxURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let inbox = container.appendingPathComponent(inboxFolder)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private static func uniqueDest(for source: URL, in dir: URL) -> URL {
        var dest = dir.appendingPathComponent(source.lastPathComponent)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext  = source.pathExtension
            dest = dir.appendingPathComponent("\(base)_\(n).\(ext)")
            n += 1
        }
        return dest
    }
}
