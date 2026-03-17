# Local AI Assistant for iPhone

A fully on-device AI assistant that runs entirely on your iPhone using Apple's Core ML and Neural Engine. No cloud, no API keys, no data ever leaves your device.

## Features

- **100% Local & Private** — All inference runs on-device using Core ML and the Apple Neural Engine
- **Multiple Model Support** — Choose from SmolLM-135M, Phi-2, Gemma-2B, Mistral-7B, or Llama-3-8B
- **Streaming Responses** — Token-by-token generation with real-time UI updates
- **Web & Video Search** — Ask the assistant to search for videos or web content and get clickable links
- **Conversation Management** — Multiple conversations with auto-titling and persistence
- **No Content Restrictions** — The assistant answers any question openly
- **Customizable** — Adjust temperature, max tokens, system prompt, and font size
- **Offline Capable** — Works without any internet connection after model download
- **Native SwiftUI** — Clean, modern iOS interface with dark mode support

## Requirements

- iPhone with iOS 17.0+
- Xcode 15.4+
- For larger models (7B+): iPhone 15 Pro or later (6GB+ RAM)

## Project Structure

```
LocalAIAssistant/
├── LocalAIAssistantApp.swift     # App entry point
├── ContentView.swift             # Main view with onboarding
├── Models/
│   ├── Message.swift             # Message data model
│   ├── Conversation.swift        # Conversation data model
│   └── ChatViewModel.swift       # Main view model
├── Views/
│   ├── ChatView.swift            # Chat interface
│   ├── MessageBubbleView.swift   # Message bubble with markdown
│   ├── TypingIndicatorView.swift # Animated typing indicator
│   ├── ConversationListView.swift# Conversation history
│   ├── SettingsView.swift        # App settings
│   └── ModelDownloadView.swift   # Model management
├── Services/
│   ├── LocalModelManager.swift   # Core ML model loading & inference
│   ├── TokenizerService.swift    # BPE tokenizer for model I/O
│   └── PersistenceManager.swift  # Local storage for chats & settings
└── Resources/
    └── Assets.xcassets           # App icons and colors
```

## Getting Started

1. Open `LocalAIAssistant.xcodeproj` in Xcode
2. Select your iPhone as the build target
3. Build and run (Cmd+R)
4. On first launch, tap **"Try Demo Mode"** for instant access, or download a model for full on-device inference

## Integrating a Real Core ML Model

The app includes a demo mode with simulated responses. To use a real on-device model:

1. **Get a Core ML model** — Convert a model from HuggingFace using `coremltools`:
   ```python
   import coremltools as ct
   # Convert your model to Core ML format
   # See: https://apple.github.io/coremltools/docs-guides/
   ```

2. **Add to the project** — Place the `.mlmodelc` compiled model in the app's Documents/Models directory

3. **Update LocalModelManager.swift** — Replace the `simulateGeneration()` method with actual MLModel inference:
   ```swift
   let prediction = try mlModel.prediction(from: inputFeatures)
   ```

4. **Update TokenizerService.swift** — Load the model's actual `tokenizer.json` vocabulary

## Supported Models

| Model | Parameters | Download | RAM | Best For |
|-------|-----------|----------|-----|----------|
| SmolLM-135M | 135M | 0.3 GB | 0.5 GB | Quick responses, any iPhone |
| Phi-2 | 2.7B | 1.6 GB | 3.0 GB | Good balance of speed/quality |
| Gemma-2B | 2B | 1.4 GB | 2.5 GB | Google's efficient model |
| Mistral-7B | 7B | 4.1 GB | 5.0 GB | High quality (Pro models) |
| Llama-3-8B | 8B | 4.7 GB | 6.0 GB | Best quality (Pro models) |

## Architecture

- **SwiftUI** for the entire UI layer
- **Core ML** for on-device neural network inference
- **Apple Neural Engine** (ANE) for hardware-accelerated inference
- **BPE Tokenizer** for text-to-token conversion
- **JSON persistence** for conversations and settings (no external dependencies)

## License

MIT
