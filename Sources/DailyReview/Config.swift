import Foundation

enum Config {
    static func loadDotEnv() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.dailyreview/.env",
            FileManager.default.currentDirectoryPath + "/.env",
            (Bundle.main.bundlePath as NSString).deletingLastPathComponent + "/.env",
        ]
        for path in candidates {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            content.components(separatedBy: .newlines).forEach { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, !t.hasPrefix("#") else { return }
                let parts = t.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                setenv(key, value, 1)
            }
            return
        }
    }

    static var wikiPath: String {
        if let path = UserDefaults.standard.string(forKey: "wikiPath"), !path.isEmpty {
            return path
        }
        if let ptr = getenv("WIKI_PATH"), let path = String(validatingCString: ptr), !path.isEmpty {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Documents/wiki/topics"
    }

    static func setWikiPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: "wikiPath")
    }
}
