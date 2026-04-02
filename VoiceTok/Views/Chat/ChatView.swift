// ChatView.swift
// AI conversation interface for discussing transcript content

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatService: ChatService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showQuickActions = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages List
                messagesScrollView

                Divider()

                // Quick Actions Bar
                if showQuickActions {
                    quickActionsBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Input Bar
                inputBar
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showQuickActions.toggle() }) {
                            Label(showQuickActions ? "Hide Quick Actions" : "Show Quick Actions",
                                  systemImage: "bolt.circle")
                        }
                        Button(action: { chatService.clearHistory() }) {
                            Label("Clear Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showQuickActions)
        }
    }

    // MARK: - Messages
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Welcome card
                    welcomeCard
                        .padding(.top, 8)

                    ForEach(chatService.messages.filter { $0.role != .system }) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    // Typing indicator
                    if chatService.isGenerating {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .onChange(of: chatService.messages.count) { _, _ in
                if let lastMsg = chatService.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMsg.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatService.isGenerating) { _, isGen in
                if isGen {
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
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
            // Quick actions toggle
            Button(action: { showQuickActions.toggle() }) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(showQuickActions ? .orange : .secondary)
            }

            // Text field
            TextField("Ask about the content...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary : Color.orange
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || chatService.isGenerating)
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
        Task { await chatService.send(text) }
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(.orange.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.orange : Color(.systemGray5))
                    .foregroundColor(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isUser { Spacer(minLength: 40) }
        }
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
                        .scaleEffect(dotScale(for: i))
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

    private func dotScale(for index: Int) -> CGFloat {
        phase == 0 ? 0.6 : 1.0
    }
}
