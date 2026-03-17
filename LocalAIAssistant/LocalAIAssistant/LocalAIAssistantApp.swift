import SwiftUI

@main
struct LocalAIAssistantApp: App {
    @StateObject private var modelManager = LocalModelManager()
    @StateObject private var chatViewModel: ChatViewModel

    init() {
        let manager = LocalModelManager()
        _modelManager = StateObject(wrappedValue: manager)
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(modelManager: manager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(chatViewModel)
        }
    }
}
