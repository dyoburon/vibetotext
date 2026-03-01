import SwiftUI
import AppKit

/// Greppy code search settings card — codebase path configuration.
struct GreppySettingsView: View {
    @StateObject private var config = ConfigStore.shared
    @State private var pathText: String = ""
    @State private var statusMessage: String = ""
    @State private var greppyInstalled: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Greppy Code Search")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            Text("Set the codebase directory for semantic code search. Hold cmd+alt+shift to search.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)

            HStack(spacing: 8) {
                TextField("Codebase path", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { savePath() }

                Button("Browse...") { browseFolder() }
            }

            HStack(spacing: 12) {
                Button("Save") { savePath() }
                    .buttonStyle(.borderedProminent)

                if let installed = greppyInstalled {
                    HStack(spacing: 4) {
                        Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(installed ? "greppy CLI found" : "greppy CLI not found")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(installed ? Theme.green : Theme.orange)
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
        .padding(20)
        .onAppear {
            pathText = config.codebasePath ?? ""
            checkGreppyInstalled()
        }
    }

    private func savePath() {
        let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        config.codebasePath = trimmed.isEmpty ? nil : trimmed
        config.save()
        statusMessage = trimmed.isEmpty ? "Codebase path cleared" : "Saved: \(trimmed)"
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select codebase directory for Greppy search"

        if panel.runModal() == .OK, let url = panel.url {
            pathText = url.path
            savePath()
        }
    }

    private func checkGreppyInstalled() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "greppy"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            greppyInstalled = process.terminationStatus == 0
        } catch {
            greppyInstalled = false
        }
    }
}
