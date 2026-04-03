// ChatHistoryView.swift
// Conversation history list — view, load, delete, rename sessions

import SwiftUI

struct ChatHistoryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private var historyService: ChatHistoryService { appState.chatHistoryService }
    private var chatService: ChatService { appState.chatService }

    @State private var editingId: UUID?
    @State private var editingTitle = ""
    @State private var deleteTarget: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if historyService.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: newChat) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .alert("Rename", isPresented: .constant(editingId != nil)) {
                TextField("Title", text: $editingTitle)
                Button("Save") {
                    if let id = editingId {
                        historyService.renameSession(id, to: editingTitle)
                    }
                    editingId = nil
                }
                Button("Cancel", role: .cancel) { editingId = nil }
            }
            .confirmationDialog("Delete this conversation?", isPresented: .constant(deleteTarget != nil)) {
                Button("Delete", role: .destructive) {
                    if let id = deleteTarget { historyService.deleteSession(id) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
        }
    }

    private var sessionList: some View {
        List {
            ForEach(historyService.sessions) { session in
                Button(action: { loadSession(session) }) {
                    SessionRow(session: session, isActive: session.id == historyService.activeSessionId)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteTarget = session.id
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editingId = session.id
                        editingTitle = session.title
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundStyle(.tertiary)
            Text("No Conversations Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start a new chat to begin.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Button(action: newChat) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
    }

    private func loadSession(_ session: ChatSession) {
        chatService.loadSession(session)
        dismiss()
    }

    private func newChat() {
        let transcript = appState.activeMediaItem?.transcript
        chatService.startNewSession(
            transcript: transcript,
            mediaItemId: appState.activeMediaItem?.id
        )
        dismiss()
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(isActive ? .orange : (session.isCompleted ? .green : .gray))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let provider = session.providerName {
                        Text(provider)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let model = session.modelName {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(session.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Message count
            let msgCount = session.messages.filter { $0.role != .system }.count
            if msgCount > 0 {
                Text("\(msgCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
