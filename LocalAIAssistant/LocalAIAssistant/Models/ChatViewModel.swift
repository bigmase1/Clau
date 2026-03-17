import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?

    let modelManager: LocalModelManager
    private let tokenizer = TokenizerService()
    private let persistence = PersistenceManager.shared
    private var settings: AppSettings

    init(modelManager: LocalModelManager) {
        self.modelManager = modelManager
        self.settings = persistence.loadSettings()
        self.conversations = persistence.loadConversations()
    }

    // MARK: - Conversation Management

    func createNewConversation() {
        let conversation = Conversation(systemPrompt: settings.systemPrompt)
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        persistence.saveConversation(conversation)
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        persistence.deleteConversation(conversation)
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
    }

    func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let conversation = conversations[index]
            persistence.deleteConversation(conversation)
        }
        conversations.remove(atOffsets: offsets)
        if let current = currentConversation, !conversations.contains(where: { $0.id == current.id }) {
            currentConversation = conversations.first
        }
    }

    // MARK: - Message Sending

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isGenerating else { return }

        // Ensure we have a conversation
        if currentConversation == nil {
            createNewConversation()
        }

        guard var conversation = currentConversation else { return }

        // Add user message
        let userMessage = Message(role: .user, content: text)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        // Auto-title on first message
        if conversation.messages.count == 1 {
            conversation.generateTitle()
        }

        currentConversation = conversation
        updateConversationInList(conversation)
        inputText = ""

        // Generate response
        isGenerating = true
        errorMessage = nil

        // Create placeholder assistant message
        var assistantMessage = Message(role: .assistant, content: "", isStreaming: true)
        conversation.messages.append(assistantMessage)
        currentConversation = conversation

        // Build prompt from conversation history
        let prompt = tokenizer.buildPrompt(
            messages: conversation.messages.dropLast().map { $0 }, // exclude empty assistant msg
            systemPrompt: conversation.systemPrompt,
            maxContextTokens: modelManager.currentModelType.contextLength
        )

        // Stream tokens from the local model
        let stream = await modelManager.generate(
            prompt: prompt,
            maxTokens: settings.maxTokens,
            temperature: settings.temperature
        )

        var fullResponse = ""
        for await token in stream {
            fullResponse += token

            // Update the assistant message in real-time
            assistantMessage.content = fullResponse
            if var conv = currentConversation {
                if let lastIndex = conv.messages.indices.last {
                    conv.messages[lastIndex] = assistantMessage
                    currentConversation = conv
                    conversation = conv
                }
            }
        }

        // Finalize message
        assistantMessage.isStreaming = false
        if var conv = currentConversation {
            if let lastIndex = conv.messages.indices.last {
                conv.messages[lastIndex] = assistantMessage
                conv.updatedAt = Date()
                currentConversation = conv
                conversation = conv
            }
        }

        updateConversationInList(conversation)
        persistence.saveConversation(conversation)
        isGenerating = false

        // Haptic feedback
        if settings.hapticFeedback {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    private func updateConversationInList(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
    }

    // MARK: - Settings

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        persistence.saveSettings(newSettings)
    }

    var currentSettings: AppSettings { settings }
}
