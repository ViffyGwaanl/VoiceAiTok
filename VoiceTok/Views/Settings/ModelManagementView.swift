// ModelManagementView.swift
// WhisperKit model download, management, and selection

import SwiftUI

struct ModelManagementView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("whisper_model") private var selectedModel = "base"
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var service: TranscriptionService { appState.transcriptionService }

    var body: some View {
        List {
            // MARK: - Recommended
            Section {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommended for this device")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(service.recommendedModel)
                            .font(.headline)
                    }
                    Spacer()
                    if selectedModel != service.recommendedModel {
                        Button("Use") {
                            selectModel(service.recommendedModel)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    } else {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Label("Device Recommendation", systemImage: "sparkles")
            }

            // MARK: - Model List
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Fetching models...")
                            .foregroundStyle(.secondary)
                    }
                } else if service.availableModels.isEmpty {
                    Text("Could not load model list")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.availableModels, id: \.self) { model in
                        ModelRow(
                            name: model,
                            size: TranscriptionService.estimatedSize(for: model),
                            state: service.localModelStates[model] ?? .notDownloaded,
                            isSelected: selectedModel == model,
                            isRecommended: model == service.recommendedModel,
                            onDownload: { Task { await downloadModel(model) } },
                            onSelect: { selectModel(model) },
                            onDelete: { deleteModel(model) }
                        )
                    }
                }
            } header: {
                Label("Available Models", systemImage: "square.and.arrow.down")
            } footer: {
                Text("Larger models produce more accurate transcriptions but require more storage and processing time. English-only models (.en) are faster for English content.")
            }

            // MARK: - Storage
            Section {
                HStack {
                    Text("Model Cache")
                    Spacer()
                    Text(cacheSize)
                        .foregroundStyle(.secondary)
                }
                Button("Clear All Downloaded Models", role: .destructive) {
                    clearAllModels()
                }
            } header: {
                Label("Storage", systemImage: "internaldrive")
            }
        }
        .navigationTitle("Whisper Models")
        .task {
            await service.fetchModelInfo()
            isLoading = false
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Actions

    private func selectModel(_ model: String) {
        selectedModel = model
        service.config.modelName = model
    }

    private func downloadModel(_ model: String) async {
        do {
            try await service.downloadModel(model)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteModel(_ model: String) {
        service.deleteModel(model)
        // If deleting the active model, reset to recommended
        if selectedModel == model {
            selectModel(service.recommendedModel)
        }
    }

    private func clearAllModels() {
        for model in service.availableModels {
            if service.localModelStates[model] == .downloaded {
                service.deleteModel(model)
            }
        }
    }

    private var cacheSize: String {
        let cacheDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface")
        let size = directorySize(url: cacheDir)
        if size > 1_000_000_000 {
            return String(format: "%.1f GB", Double(size) / 1_000_000_000)
        } else if size > 1_000_000 {
            return String(format: "%.0f MB", Double(size) / 1_000_000)
        }
        return "0 MB"
    }

    private func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let name: String
    let size: String
    let state: TranscriptionService.ModelDownloadState
    let isSelected: Bool
    let isRecommended: Bool
    let onDownload: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Model info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)

                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if !size.isEmpty {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if name.hasSuffix(".en") {
                        Text("English only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // State-dependent action
            switch state {
            case .notDownloaded:
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

            case .downloading(let progress):
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 30, height: 30)

            case .downloaded:
                HStack(spacing: 10) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Use") {
                            onSelect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
