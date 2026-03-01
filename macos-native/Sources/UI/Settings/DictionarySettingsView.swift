import SwiftUI

/// Custom dictionary management panel
struct DictionarySettingsView: View {
    @StateObject private var config = ConfigStore.shared
    @State private var newWord: String = ""
    @State private var statusMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Custom Dictionary")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    Text("Add words you use frequently to improve transcription accuracy. These words will be included in the Whisper prompt.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(3)

                    // Input row
                    HStack(spacing: 8) {
                        TextField("Enter a word or phrase...", text: $newWord)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textPrimary)
                            .padding(12)
                            .background(Theme.bgTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                            .onSubmit { addWord() }

                        Button("Add") { addWord() }
                            .buttonStyle(.plain)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.bgPrimary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Theme.dictionaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Word chips
                    if config.customDictionary.isEmpty {
                        Text("No custom words added yet")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                            .italic()
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(config.customDictionary, id: \.self) { word in
                                wordChip(word)
                            }
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.green)
                    }
                }
                .padding(24)
                .background(Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func wordChip(_ word: String) -> some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)

            Button {
                config.removeWord(word)
                showStatus("Removed \"\(word)\"")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if config.customDictionary.contains(trimmed) {
            showStatus("\"\(trimmed)\" is already in your dictionary")
            return
        }
        config.addWord(trimmed)
        newWord = ""
        showStatus("Added \"\(trimmed)\"")
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message {
                statusMessage = ""
            }
        }
    }
}
