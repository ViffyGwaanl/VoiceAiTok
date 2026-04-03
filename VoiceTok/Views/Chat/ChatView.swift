// ChatView.swift
// AI conversation interface — inspired by PaperTok Reader
// Features: copy, regenerate, stop, smart scroll, provider badge, error guidance

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatService: ChatService
    @EnvironmentObject var providerService: AIProviderService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showQuickActions = true
    @State private var showSettings = false
    @State private var showClearConfirm = false
    @State private var pinnedToBottom = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesScrollView

                Divider()

                if showQuickActions && !chatService.isGenerating && chatService.hasConfiguredProvider {
                    quickActionsBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                inputBar
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
            .sheet(isPresented: $showSettings) { SettingsView() }
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

                    // Setup prompt if no provider configured
                    if !chatService.hasConfiguredProvider {
                        noProviderPrompt
                    }

                    ForEach(visibleMessages) { message in
                        ChatBubble(
                            message: message,
                            isStreaming: chatService.isGenerating && isLastAssistantMessage(message),
                            isLastAssistant: isLastAssistantMessage(message),
                            onCopy: { copyMessage(message) },
                            onRegenerate: { Task { await chatService.regenerate() } }
                        )
                        .id(message.id)
                    }

                    // Typing dots only before first chunk arrives
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
                    // User scrolled up → unpin
                    if value.translation.height > 10 { pinnedToBottom = false }
                    // User scrolled to bottom → re-pin
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

    private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return visibleMessages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func copyMessage(_ message: ChatMessage) {
        UIPasteboard.general.string = message.content
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

            // Send or Stop button
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
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary : Color.orange
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chatService.hasConfiguredProvider)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
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

// MARK: - Chat Bubble (with copy, regenerate)

struct ChatBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var isLastAssistant: Bool = false
    var onCopy: (() -> Void)?
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
                Text(message.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundColor(isUser ? .white : (isError ? .red : .primary))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                // Action buttons for AI messages
                if !isUser && !message.content.isEmpty {
                    HStack(spacing: 12) {
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !isStreaming {
                            Button(action: { onCopy?() }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.tertiary)

                            if isLastAssistant {
                                Button(action: { onRegenerate?() }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else if isUser {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.vertical, 2)
    }

    private var bubbleBackground: Color {
        if isUser { return .orange }
        if isError { return Color.red.opacity(0.1) }
        return Color(.systemGray5)
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
