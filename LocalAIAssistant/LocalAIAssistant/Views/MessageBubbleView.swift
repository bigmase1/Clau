import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 48)
            } else {
                // Assistant avatar
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .padding(.top, 4)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Message content
                if message.isUser {
                    Text(message.content)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.blue.gradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    // Render markdown for assistant messages (supports links, bold, etc.)
                    MarkdownTextView(text: message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Streaming indicator
                if message.isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                            .opacity(0.8)
                        Text("generating...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !message.isUser {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        if #available(iOS 17.0, *) {
            // Use built-in Markdown rendering
            Text(markdownAttributed)
                .font(.body)
                .tint(.blue)
        } else {
            Text(text)
                .font(.body)
        }
    }

    private var markdownAttributed: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
