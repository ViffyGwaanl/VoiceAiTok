// LibraryView.swift
// Media library with import, browse, and management

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFilePicker = false
    @State private var showURLInput = false
    @State private var urlInput = ""
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var showSettings = false

    enum SortOrder: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case titleAsc = "Title A→Z"
        case titleDesc = "Title Z→A"
        case durationDesc = "Longest"
    }

    var filteredItems: [MediaItem] {
        var items = appState.mediaLibraryService.mediaItems

        if !searchText.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOrder {
        case .dateDesc: items.sort { $0.dateAdded > $1.dateAdded }
        case .dateAsc: items.sort { $0.dateAdded < $1.dateAdded }
        case .titleAsc: items.sort { $0.title < $1.title }
        case .titleDesc: items.sort { $0.title > $1.title }
        case .durationDesc: items.sort { $0.duration > $1.duration }
        }

        return items
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.mediaLibraryService.mediaItems.isEmpty {
                    emptyLibraryView
                } else {
                    mediaListView
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                        Menu {
                            Button(action: { showFilePicker = true }) {
                                Label("Import from Files", systemImage: "folder")
                            }
                            Button(action: { showURLInput = true }) {
                                Label("Import from URL", systemImage: "link")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .searchable(text: $searchText, prompt: "Search media...")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: MediaLibraryService.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                Task {
                    switch result {
                    case .success(let urls):
                        for url in urls {
                            do {
                                let item = try await appState.mediaLibraryService.importMedia(from: url)
                                appState.activeMediaItem = item
                            } catch {
                                print("[Library] Import failed: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("[Library] File picker error: \(error)")
                    }
                }
            }
            .alert("Import from URL", isPresented: $showURLInput) {
                TextField("https://...", text: $urlInput)
                    .textInputAutocapitalization(.never)
                Button("Import") {
                    guard let url = URL(string: urlInput) else { return }
                    Task {
                        let item = try? await appState.mediaLibraryService.importMedia(from: url)
                        if let item { appState.activeMediaItem = item }
                    }
                    urlInput = ""
                }
                Button("Cancel", role: .cancel) { urlInput = "" }
            }
        }
    }

    // MARK: - Empty State
    private var emptyLibraryView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Your Media Library")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Import video or audio files to transcribe\nand chat about their content with AI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showFilePicker = true }) {
                Label("Import Media", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 14)
                    .background(.orange.gradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Media List
    private var mediaListView: some View {
        List {
            ForEach(filteredItems) { item in
                MediaItemRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.activeMediaItem = item
                        appState.selectedTab = .player
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.mediaLibraryService.deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Media Item Row
struct MediaItemRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail / Icon
            ZStack {
                if let thumbPath = item.thumbnailPath,
                   let image = UIImage(contentsOfFile: thumbPath) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    Image(systemName: item.mediaType.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(MediaLibraryService.formatDuration(item.duration), systemImage: "clock")
                    if item.transcript != nil {
                        Label("Transcribed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
