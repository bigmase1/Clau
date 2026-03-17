import SwiftUI

struct ContentView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var modelManager: LocalModelManager
    @State private var showSettings = false
    @State private var showConversationList = false
    @State private var showModelDownload = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if modelManager.modelState == .ready || modelManager.modelState == .downloaded {
                    ChatView()
                } else {
                    onboardingView
                }
            }
            .navigationTitle(chatViewModel.currentConversation?.title ?? "AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showConversationList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        chatViewModel.createNewConversation()
                    } label: {
                        Image(systemName: "plus.message")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showConversationList) {
                ConversationListView()
            }
            .sheet(isPresented: $showModelDownload) {
                ModelDownloadView()
            }
        }
    }

    private var onboardingView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            Text("Local AI Assistant")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("A powerful AI that runs entirely on your iPhone.\nYour conversations never leave this device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                FeatureRow(icon: "lock.shield", title: "100% Private", detail: "Everything runs on-device")
                FeatureRow(icon: "wifi.slash", title: "Works Offline", detail: "No internet required")
                FeatureRow(icon: "bolt", title: "Fast & Local", detail: "Powered by Apple Neural Engine")
                FeatureRow(icon: "magnifyingglass", title: "Web Search", detail: "Search for videos and content")
            }
            .padding()

            Button {
                showModelDownload = true
            } label: {
                Text("Download a Model to Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            // Quick start: use demo mode without downloading
            Button {
                Task {
                    await modelManager.loadModel(.smolLM135M)
                    chatViewModel.createNewConversation()
                }
            } label: {
                Text("Try Demo Mode")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
