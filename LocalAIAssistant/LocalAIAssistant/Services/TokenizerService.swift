import Foundation

class TokenizerService {
    // BPE (Byte Pair Encoding) tokenizer for on-device language models.
    // This handles converting text to token IDs and back for CoreML model input/output.

    private var vocabulary: [String: Int] = [:]
    private var reverseVocabulary: [Int: String] = [:]
    private var merges: [(String, String)] = []

    // Special tokens
    let bosToken: Int = 1     // Beginning of sequence
    let eosToken: Int = 2     // End of sequence
    let padToken: Int = 0     // Padding
    let unknownToken: Int = 3 // Unknown token

    init() {
        buildBaseVocabulary()
    }

    private func buildBaseVocabulary() {
        // Build a basic byte-level vocabulary
        // In production, this loads the model's actual vocabulary file (tokenizer.json)
        var id = 4 // Start after special tokens

        // Single characters
        for char in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?;:'\"-()[]{}@#$%^&*+=/<>\\|~`\n\t" {
            let token = String(char)
            vocabulary[token] = id
            reverseVocabulary[id] = token
            id += 1
        }

        // Common English subwords
        let commonSubwords = [
            "the", "ing", "tion", "er", "ed", "es", "en", "al", "re", "on",
            "an", "or", "is", "it", "at", "in", "to", "of", "and", "for",
            "that", "with", "this", "from", "not", "are", "but", "was", "have",
            "you", "can", "they", "all", "would", "there", "their", "what",
            "about", "which", "when", "one", "your", "out", "them", "then",
            "she", "many", "some", "her", "him", "could", "into", "has",
            "more", "two", "way", "who", "did", "get", "been", "will",
            "how", "its", "may", "than", "now", "each", "any", "our",
            " the", " a", " is", " of", " and", " to", " in", " it",
            " that", " for", " was", " on", " are", " with", " as",
        ]

        for subword in commonSubwords {
            vocabulary[subword] = id
            reverseVocabulary[id] = subword
            id += 1
        }
    }

    func encode(_ text: String) -> [Int] {
        var tokens: [Int] = [bosToken]

        // Simple greedy tokenization — scan for longest matching subword
        var remaining = text
        while !remaining.isEmpty {
            var matched = false

            // Try decreasing lengths
            let maxLen = min(remaining.count, 10)
            for length in stride(from: maxLen, through: 1, by: -1) {
                let endIndex = remaining.index(remaining.startIndex, offsetBy: length)
                let candidate = String(remaining[remaining.startIndex..<endIndex])

                if let tokenId = vocabulary[candidate] {
                    tokens.append(tokenId)
                    remaining = String(remaining[endIndex...])
                    matched = true
                    break
                }
            }

            if !matched {
                // Fall back to single character or unknown token
                let char = String(remaining.prefix(1))
                tokens.append(vocabulary[char] ?? unknownToken)
                remaining = String(remaining.dropFirst())
            }
        }

        return tokens
    }

    func decode(_ tokenIds: [Int]) -> String {
        var result = ""

        for id in tokenIds {
            if id == bosToken || id == eosToken || id == padToken {
                continue
            }
            if let token = reverseVocabulary[id] {
                result += token
            }
        }

        return result
    }

    func tokenCount(_ text: String) -> Int {
        encode(text).count
    }

    func buildPrompt(messages: [Message], systemPrompt: String, maxContextTokens: Int) -> String {
        var prompt = "<|system|>\n\(systemPrompt)</s>\n"

        // Build conversation history, truncating from the beginning if needed
        var conversationParts: [String] = []
        for message in messages {
            switch message.role {
            case .user:
                conversationParts.append("<|user|>\n\(message.content)</s>\n")
            case .assistant:
                conversationParts.append("<|assistant|>\n\(message.content)</s>\n")
            case .system:
                break
            }
        }

        // Truncate oldest messages if needed to stay within context
        var conversation = conversationParts.joined()
        let systemTokens = tokenCount(prompt)
        let availableTokens = maxContextTokens - systemTokens - 100 // reserve for generation

        while tokenCount(conversation) > availableTokens && !conversationParts.isEmpty {
            conversationParts.removeFirst()
            conversation = conversationParts.joined()
        }

        prompt += conversation
        prompt += "<|assistant|>\n"

        return prompt
    }
}
