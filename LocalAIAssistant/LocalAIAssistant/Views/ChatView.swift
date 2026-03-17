import SwiftUI

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var modelManager: LocalModelManager
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let conversation = viewModel.currentConversation {
                            if conversation.messages.isEmpty {
                                emptyStateView
                                    .padding(.top, 60)
                            }

                            ForEach(conversation.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isGenerating {
                                TypingIndicatorView()
                                    .id("typing-indicator")
                            }
                        } else {
                            emptyStateView
                                .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.currentConversation?.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        if let lastMessage = viewModel.currentConversation?.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.currentConversation?.messages.last?.content) { _, _ in
                    // Auto-scroll during streaming
                    if viewModel.isGenerating {
                        withAnimation(.easeOut(duration: 0.1)) {
                            if let lastMessage = viewModel.currentConversation?.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Divider()

            // Input bar
            inputBar
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Start a Conversation")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Ask me anything — I'm running locally on your device")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Quick action suggestions
            VStack(spacing: 8) {
                SuggestionChip(text: "What can you do?") {
                    viewModel.inputText = "What can you do?"
                    Task { await viewModel.sendMessage() }
                }
                SuggestionChip(text: "Search for videos about Swift programming") {
                    viewModel.inputText = "Search for videos about Swift programming"
                    Task { await viewModel.sendMessage() }
                }
                SuggestionChip(text: "Write me a short poem") {
                    viewModel.inputText = "Write me a short poem"
                    Task { await viewModel.sendMessage() }
                }
                SuggestionChip(text: "Explain quantum computing simply") {
                    viewModel.inputText = "Explain quantum computing simply"
                    Task { await viewModel.sendMessage() }
                }
            }
            .padding(.top, 8)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isGenerating
                            ? Color(.tertiaryLabel)
                            : .blue
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isGenerating)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
