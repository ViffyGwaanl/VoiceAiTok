// ChatView.swift
// AI conversation interface — inspired by PaperTok Reader
// Features: history, edit, regenerate-from-any, thinking collapse, copy, smart scroll

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatService: ChatService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var providerService: AIProviderService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showQuickActions = true
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showClearConfirm = false
    @State private var pinnedToBottom = true
    @State private var editingMessageId: UUID?
    @State private var showEditSheet = false
    @State private var editText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesScrollView

                Divider()

                if showQuickActions && !chatService.isGenerating && chatService.hasConfiguredProvider
                    && visibleMessages.filter({ $0.role == .user }).isEmpty {
                    quickActionsBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                inputBar
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button(action: { showHistory = true }) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // New chat
                        Button(action: newChat) {
                            Image(systemName: "square.and.pencil")
                        }
                        Menu {
                            Button(action: { showQuickActions.toggle() }) {
                                Label(showQuickActions ? "Hide Quick Actions" : "Show Quick Actions",
                                      systemImage: "bolt.circle")
                            }
                            Button(action: { showClearConfirm = true }) {
                                Label("Clear Chat", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showHistory) { ChatHistoryView() }
            .sheet(isPresented: $showEditSheet) {
                EditMessageSheet(
                    originalText: editText,
                    editText: $editText,
                    onSave: { newText in
                        if let id = editingMessageId {
                            Task { await chatService.editMessage(at: id, newContent: newText) }
                        }
                    }
                )
            }
            .confirmationDialog("Clear all messages?", isPresented: $showClearConfirm) {
                Button("Clear Chat", role: .destructive) { chatService.clearHistory() }
            }
            .animation(.easeInOut(duration: 0.25), value: showQuickActions)
        }
    }

    // MARK: - Messages

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    welcomeCard
                        .padding(.top, 8)

                    // Provider badge
                    if let active = providerService.activeProvider {
                        HStack(spacing: 4) {
                            Image(systemName: active.type.icon)
                            Text(active.name)
                            Text("·")
                            Text(active.modelName)
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                    }

                    if !chatService.hasConfiguredProvider {
                        noProviderPrompt
                    }

                    ForEach(visibleMessages) { message in
                        makeBubble(for: message)
                            .id(message.id)
                    }

                    if chatService.isGenerating && chatService.currentStreamText.isEmpty {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .onAppear { pinnedToBottom = true }
            .onChange(of: chatService.messages.count) { _, _ in
                if pinnedToBottom { scrollToBottom(proxy) }
            }
            .onChange(of: chatService.currentStreamText) { _, _ in
                if pinnedToBottom, let last = visibleMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .simultaneousGesture(
                DragGesture().onChanged { value in
                    if value.translation.height > 10 { pinnedToBottom = false }
                    if value.translation.height < -10 { pinnedToBottom = true }
                }
            )
        }
    }

    private var visibleMessages: [ChatMessage] {
        chatService.messages.filter { $0.role != .system }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastMsg = visibleMessages.last {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(lastMsg.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func makeBubble(for message: ChatMessage) -> some View {
        let streaming = chatService.isGenerating && isLastAssistantMessage(message)
        let lastAssistant = isLastAssistantMessage(message)
        let editAction: (() -> Void)? = message.role == .user ? { startEdit(message) } : nil
        let regenAction: (() -> Void)? = message.role == .assistant ? {
            Task { await chatService.regenerateFrom(messageId: message.id) }
        } : nil
        ChatBubble(
            message: message,
            isStreaming: streaming,
            isLastAssistant: lastAssistant,
            onCopy: { copyMessage(message) },
            onEdit: editAction,
            onRegenerate: regenAction
        )
    }

    private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return visibleMessages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func copyMessage(_ message: ChatMessage) {
        // Strip thinking tags when copying
        let text = Self.stripThinkingTags(message.content)
        UIPasteboard.general.string = text
    }

    private func startEdit(_ message: ChatMessage) {
        editText = message.content
        editingMessageId = message.id
        showEditSheet = true
    }

    private func newChat() {
        let transcript = appState.activeMediaItem?.transcript
        chatService.startNewSession(
            transcript: transcript,
            mediaItemId: appState.activeMediaItem?.id
        )
    }

    /// Strip <think>...</think> tags for clipboard
    static func stripThinkingTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<think>[\\s\\S]*?</think>\\s*", with: "", options: .regularExpression)
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )

            Text("Chat About Your Media")
                .font(.headline)

            Text("Ask questions about the transcribed content.\nI can summarize, explain, translate, and more.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - No Provider Prompt

    private var noProviderPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text("AI Provider Not Configured")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Go to Settings → AI Providers to add your API key before chatting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { showSettings = true }) {
                Label("Open Settings", systemImage: "gearshape")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Quick Actions

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                QuickActionButton(title: "Summarize", icon: "text.alignleft") {
                    Task { await chatService.summarize() }
                }
                QuickActionButton(title: "Key Topics", icon: "list.bullet.rectangle") {
                    Task { await chatService.extractKeyTopics() }
                }
                QuickActionButton(title: "Study Notes", icon: "note.text") {
                    Task { await chatService.generateNotes() }
                }
                QuickActionButton(title: "Translate to 中文", icon: "globe") {
                    Task { await chatService.translateSummary(to: "Chinese") }
                }
                QuickActionButton(title: "Translate to EN", icon: "globe") {
                    Task { await chatService.translateSummary(to: "English") }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: { showQuickActions.toggle() }) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(showQuickActions ? .orange : .secondary)
            }

            TextField("Ask about the content...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendMessage() }

            if chatService.isGenerating {
                Button(action: { chatService.stopGeneration() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.orange : Color.secondary)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chatService.hasConfiguredProvider
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        pinnedToBottom = true
        Task { await chatService.send(text) }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var isLastAssistant: Bool = false
    var onCopy: (() -> Void)?
    var onEdit: (() -> Void)?
    var onRegenerate: (() -> Void)?

    var isUser: Bool { message.role == .user }
    var isError: Bool { !isUser && message.content.hasPrefix("⚠️") }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: isError ? "exclamationmark.triangle" : "sparkles")
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .orange)
                    .frame(width: 24, height: 24)
                    .background((isError ? Color.red : Color.orange).opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Thinking section (collapsible)
                if !isUser, let thinking = extractThinking(from: message.content), !thinking.isEmpty {
                    ThinkingSection(text: thinking)
                }

                // Main content (strip thinking if present)
                let displayContent = isUser ? message.content : stripThinkingForDisplay(message.content)
                if !displayContent.isEmpty {
                    Text(displayContent)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleBackground)
                        .foregroundColor(isUser ? .white : (isError ? .red : .primary))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                // Action buttons
                messageActions
            }

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var messageActions: some View {
        HStack(spacing: 12) {
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if !isStreaming {
                if !message.content.isEmpty {
                    Button(action: { onCopy?() }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }

                // Edit button (user messages only)
                if isUser, let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }

                // Regenerate (assistant messages only)
                if !isUser, let onRegenerate {
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var bubbleBackground: Color {
        if isUser { return .orange }
        if isError { return Color.red.opacity(0.1) }
        return Color(.systemGray5)
    }

    // MARK: - Thinking Extraction

    private func extractThinking(from text: String) -> String? {
        guard let range = text.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) else {
            return nil
        }
        var thinking = String(text[range])
        thinking = thinking.replacingOccurrences(of: "<think>", with: "")
        thinking = thinking.replacingOccurrences(of: "</think>", with: "")
        return thinking.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripThinkingForDisplay(_ text: String) -> String {
        text.replacingOccurrences(of: "<think>[\\s\\S]*?</think>\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Thinking Section (Collapsible)

struct ThinkingSection: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Thinking")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text(text.prefix(80) + (text.count > 80 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Edit Message Sheet

struct EditMessageSheet: View {
    let originalText: String
    @Binding var editText: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editText)
                    .font(.body)
                    .padding()
                    .scrollContentBackground(.hidden)

                Divider()

                Text("Editing will regenerate the response from this point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Regenerate") {
                        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(phase == 0 ? 0.6 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .onAppear { phase = 1.0 }
    }
}
