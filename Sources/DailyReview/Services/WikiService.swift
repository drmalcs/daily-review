import Foundation

struct WikiService: Sendable {
    static var wikiURL: URL { URL(fileURLWithPath: Config.wikiPath) }

    func appendToWikiFile(topic: String, content: String) throws {
        let fm = FileManager.default
        let baseURL = WikiService.wikiURL

        guard fm.fileExists(atPath: baseURL.path) else {
            throw WikiServiceError.directoryNotFound(baseURL.path)
        }

        let files = (try? fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let mdFiles = files.filter { $0.pathExtension.lowercased() == "md" }

        let topicNorm = topic.lowercased().replacingOccurrences(of: "-", with: " ")
        let matchedFile = mdFiles.first { url in
            let nameNorm = url.deletingPathExtension().lastPathComponent
                .lowercased()
                .replacingOccurrences(of: "-", with: " ")
            let minLen = min(nameNorm.count, topicNorm.count)
            guard minLen >= 4 else { return false }
            return nameNorm.contains(topicNorm) || topicNorm.contains(nameNorm)
        }

        let targetURL: URL
        if let match = matchedFile {
            targetURL = match
        } else {
            let newURL = baseURL.appendingPathComponent("\(makeSafeFilename(from: topic)).md")
            fm.createFile(atPath: newURL.path, contents: Data())
            targetURL = newURL
        }

        let appendText = "\n\n---\n\n\(content)"
        if let existing = try? String(contentsOf: targetURL, encoding: .utf8), !existing.isEmpty {
            try (existing + appendText).write(to: targetURL, atomically: true, encoding: .utf8)
        } else {
            try appendText.trimmingCharacters(in: .newlines).write(to: targetURL, atomically: true, encoding: .utf8)
        }
    }

    private func makeSafeFilename(from topic: String) -> String {
        let joined = topic.prefix(80).unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : Character("-") }
        let result = String(joined).lowercased()
            .components(separatedBy: "-").filter { !$0.isEmpty }.joined(separator: "-")
        return result.isEmpty ? "new-topic" : result
    }
}

enum WikiServiceError: Error, LocalizedError {
    case directoryNotFound(String)
    var errorDescription: String? {
        if case .directoryNotFound(let p) = self { return "Wiki folder not found: \(p)" }
        return nil
    }
}
