import Foundation

/// Greppy semantic code search integration (Rust CLI wrapper).
/// Spawns the `greppy` CLI tool to search a codebase, then formats results as markdown.
final class GreppyService {

    struct SearchResult {
        let filePath: String
        let startLine: Int
    }

    /// Search for relevant files using `greppy search`.
    func searchFiles(query: String, limit: Int = 10, codebase: String) async -> [SearchResult] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["greppy", "search", query, "-n", "\(limit)", "-p", codebase, "--json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("[Greppy] Failed to launch greppy: \(error)")
            return []
        }

        // 30-second timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            if process.isRunning {
                process.terminate()
                print("[Greppy] Search timed out after 30s")
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        guard process.terminationStatus == 0 else {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [SearchResult] = []
        var seenFiles = Set<String>()

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let filePath = json["file_path"] as? String,
                  !filePath.isEmpty,
                  !seenFiles.contains(filePath)
            else { continue }

            seenFiles.insert(filePath)
            let startLine = json["start_line"] as? Int ?? 1
            results.append(SearchResult(filePath: filePath, startLine: startLine))
        }

        return Array(results.prefix(limit))
    }

    /// Read file content, truncating at maxLines.
    func readFileContent(path: String, maxLines: Int = 200) -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)
        else { return "" }

        let lines = content.components(separatedBy: "\n")
        if lines.count > maxLines {
            let truncated = lines.prefix(maxLines).joined(separator: "\n")
            return truncated + "\n... (truncated at \(maxLines) lines)"
        }
        return content
    }

    /// Search and format results as markdown code blocks.
    func search(query: String) async -> String {
        guard let codebase = ConfigStore.shared.codebasePath, !codebase.isEmpty else {
            print("[Greppy] No codebase path configured")
            return ""
        }

        let results = await searchFiles(query: query, codebase: codebase)
        guard !results.isEmpty else { return "" }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var parts: [String] = []

        for result in results {
            let content = readFileContent(path: result.filePath)
            guard !content.isEmpty else { continue }

            // Use ~/relative path if possible
            let displayPath: String
            if result.filePath.hasPrefix(home) {
                displayPath = "~" + result.filePath.dropFirst(home.count)
            } else {
                displayPath = result.filePath
            }

            // Detect language from extension
            let ext = (result.filePath as NSString).pathExtension.lowercased()
            let lang = extensionToLanguage(ext)

            parts.append("### \(displayPath)\n```\(lang)\n\(content)\n```")
        }

        guard !parts.isEmpty else { return "" }
        return "\n\n" + parts.joined(separator: "\n\n")
    }

    private func extensionToLanguage(_ ext: String) -> String {
        switch ext {
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "tsx"
        case "jsx": return "jsx"
        case "rs": return "rust"
        case "go": return "go"
        case "rb": return "ruby"
        case "swift": return "swift"
        case "kt": return "kotlin"
        case "java": return "java"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "cs": return "csharp"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        case "md": return "markdown"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "html": return "html"
        case "css": return "css"
        default: return ext
        }
    }
}
