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
        return String(prefix(maxLength)) + "..."
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
