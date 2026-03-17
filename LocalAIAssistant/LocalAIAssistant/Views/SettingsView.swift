import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var modelManager: LocalModelManager
    @Environment(\.dismiss) private var dismiss

    @State private var settings: AppSettings = PersistenceManager.shared.loadSettings()
    @State private var showModelDownload = false

    var body: some View {
        NavigationStack {
            Form {
                // Model Section
                Section {
                    HStack {
                        Label("Current Model", systemImage: "cpu")
                        Spacer()
                        Text(modelManager.currentModelType.displayName)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Parameters", systemImage: "number")
                        Spacer()
                        Text(modelManager.currentModelType.parameterCount)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Context Length", systemImage: "text.alignleft")
                        Spacer()
                        Text("\(modelManager.currentModelType.contextLength) tokens")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Device Memory", systemImage: "memorychip")
                        Spacer()
                        Text(modelManager.deviceCapabilityInfo)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showModelDownload = true
                    } label: {
                        Label("Manage Models", systemImage: "arrow.down.circle")
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Larger models produce better responses but require more memory and are slower.")
                }

                // Generation Settings
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.1f", settings.temperature))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.temperature, in: 0.1...2.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(settings.maxTokens)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: .init(
                            get: { Double(settings.maxTokens) },
                            set: { settings.maxTokens = Int($0) }
                        ), in: 64...2048, step: 64)
                    }

                    Toggle("Stream Responses", isOn: $settings.streamResponses)
                } header: {
                    Text("Generation")
                } footer: {
                    Text("Higher temperature = more creative. Lower = more focused and deterministic.")
                }

                // System Prompt
                Section {
                    TextEditor(text: $settings.systemPrompt)
                        .frame(minHeight: 120)
                        .font(.system(.body, design: .monospaced))

                    Button("Reset to Default") {
                        settings.systemPrompt = DefaultPrompts.assistant
                    }
                    .foregroundStyle(.red)
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("Defines the AI's personality and behavior. The assistant has no built-in restrictions.")
                }

                // Appearance
                Section("Appearance") {
                    Picker("Font Size", selection: $settings.fontSize) {
                        ForEach(AppSettings.FontSizeOption.allCases, id: \.self) { size in
                            Text(size.rawValue.capitalized).tag(size)
                        }
                    }

                    Toggle("Haptic Feedback", isOn: $settings.hapticFeedback)
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Runtime")
                        Spacer()
                        Text("On-Device (CoreML)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Privacy")
                        Spacer()
                        Text("100% Local — No Data Leaves Device")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        for conversation in viewModel.conversations {
                            viewModel.deleteConversation(conversation)
                        }
                    } label: {
                        Label("Delete All Conversations", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.updateSettings(settings)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showModelDownload) {
                ModelDownloadView()
            }
        }
    }
}
