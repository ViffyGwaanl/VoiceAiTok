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

    // MARK: - Share Extension Inbox Import
    /// Scans the App Group shared container for files deposited by the Share Extension,
    /// imports each one into the library, then deletes it from the inbox.
    @discardableResult
    func importFromSharedContainer() async -> Int {
        let appGroupID = "group.com.voicetok.app"
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return 0 }

        let inbox = container.appendingPathComponent("ShareInbox")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        var imported = 0
        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }
            // Skip if already in library (same filename in our documents dir)
            let destName = fileURL.lastPathComponent
            let alreadyExists = mediaItems.contains { item in
                (item.fileURL?.lastPathComponent ?? URL(fileURLWithPath: item.filePath).lastPathComponent) == destName
            }
            guard !alreadyExists else {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }
            do {
                _ = try await importMedia(from: fileURL)
                try? FileManager.default.removeItem(at: fileURL)
                imported += 1
            } catch {
                print("[Library] Share inbox import failed: \(error)")
            }
        }
        return imported
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
