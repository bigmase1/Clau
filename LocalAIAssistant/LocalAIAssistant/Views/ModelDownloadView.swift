import SwiftUI

struct ModelDownloadView: View {
    @EnvironmentObject var modelManager: LocalModelManager
    @EnvironmentObject var chatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a model to run locally on your iPhone. Larger models are smarter but need more memory and storage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                ForEach(ModelType.allCases) { model in
                    modelRow(model)
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: ModelType) -> some View {
        let state = modelManager.availableModels[model] ?? .notDownloaded

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.displayName)
                            .font(.headline)

                        if model == modelManager.currentModelType && state == .ready {
                            Text("ACTIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text(model.recommendedFor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(model.parameterCount)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 16) {
                Label(String(format: "%.1f GB", model.downloadSizeGB), systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(String(format: "%.1f GB RAM", model.ramRequirementGB), systemImage: "memorychip")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(model.contextLength) ctx", systemImage: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Action button / progress
            switch state {
            case .notDownloaded:
                Button {
                    Task {
                        await modelManager.downloadModel(model)
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

            case .downloading(let progress):
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .tint(.blue)
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .downloaded:
                Button {
                    Task {
                        await modelManager.loadModel(model)
                        chatViewModel.createNewConversation()
                        dismiss()
                    }
                } label: {
                    Label("Load Model", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .loading:
                HStack {
                    ProgressView()
                    Text("Loading into memory...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .ready:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready")
                        .foregroundStyle(.green)
                        .fontWeight(.medium)

                    Spacer()

                    Button(role: .destructive) {
                        modelManager.deleteModel(model)
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

            case .error(let message):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
