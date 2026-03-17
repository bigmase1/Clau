import Foundation

class PersistenceManager {
    static let shared = PersistenceManager()

    private let fileManager = FileManager.default

    private var conversationsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Conversations", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var settingsURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("settings.json")
    }

    // MARK: - Conversations

    func saveConversation(_ conversation: Conversation) {
        let url = conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(conversation) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadConversations() -> [Conversation] {
        guard let files = try? fileManager.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Conversation? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Conversation.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteConversation(_ conversation: Conversation) {
        let url = conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Settings

    func saveSettings(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }
}

struct AppSettings: Codable {
    var selectedModel: ModelType = .smolLM135M
    var temperature: Float = 0.7
    var maxTokens: Int = 512
    var systemPrompt: String = DefaultPrompts.assistant
    var hapticFeedback: Bool = true
    var streamResponses: Bool = true
    var fontSize: FontSizeOption = .medium

    enum FontSizeOption: String, Codable, CaseIterable {
        case small, medium, large

        var textSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            }
        }
    }
}
