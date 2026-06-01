import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var wikiQuestions: [Question] = []
    @Published var nonWikiQuestions: [Question] = []
    @Published var topics: [Topic] = []

    // true when today's questions haven't been generated yet by the nightly agent
    @Published var awaitingAgent: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var sessionError: String? = nil

    // Suppresses saveSession() during loadSession() so the count-sync
    // doesn't overwrite a future-dated session the nightly script just wrote.
    private var isLoadingSession = false

    @Published var wikiQuestionCount: Int {
        didSet {
            UserDefaults.standard.set(wikiQuestionCount, forKey: "wikiQuestionCount")
            if !isLoadingSession { saveSession() }
        }
    }
    @Published var nonWikiQuestionCount: Int {
        didSet {
            UserDefaults.standard.set(nonWikiQuestionCount, forKey: "nonWikiQuestionCount")
            if !isLoadingSession { saveSession() }
        }
    }

    var allRated: Bool {
        let all = wikiQuestions + nonWikiQuestions
        return !all.isEmpty && all.allSatisfy { $0.srsRating != nil }
    }

    private let wikiService = WikiService()
    private var refreshTimer: Timer?

    static let sessionFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dailyreview")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }()

    static let topicsFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dailyreview")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("topics.json")
    }()

    init() {
        let storedWiki = UserDefaults.standard.integer(forKey: "wikiQuestionCount")
        wikiQuestionCount = storedWiki > 0 ? storedWiki : 5
        let storedNon = UserDefaults.standard.integer(forKey: "nonWikiQuestionCount")
        nonWikiQuestionCount = storedNon > 0 ? storedNon : 2

        loadTopics()
        loadSession()
        startRefreshTimer()
    }

    // MARK: - Session loading

    func loadSession() {
        sessionError = nil

        guard let data = try? Data(contentsOf: AppStore.sessionFileURL) else {
            awaitingAgent = true
            return
        }

        let session: DaySession
        do {
            session = try JSONDecoder().decode(DaySession.self, from: data)
        } catch {
            sessionError = "Could not read session file: \(error.localizedDescription)"
            awaitingAgent = true
            return
        }

        let today = DaySession.todayString

        if session.dateString == today {
            applySession(session)
            awaitingAgent = false
        } else {
            wikiQuestions    = session.wikiQuestions.filter    { $0.srsRating == nil }
            nonWikiQuestions = session.nonWikiQuestions.filter { $0.srsRating == nil }
            awaitingAgent = true
        }

        isLoadingSession = true
        wikiQuestionCount    = session.wikiQuestionCount    > 0 ? session.wikiQuestionCount    : wikiQuestionCount
        nonWikiQuestionCount = session.nonWikiQuestionCount > 0 ? session.nonWikiQuestionCount : nonWikiQuestionCount
        isLoadingSession = false
    }

    private func applySession(_ session: DaySession) {
        wikiQuestions    = session.wikiQuestions
        nonWikiQuestions = session.nonWikiQuestions
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.loadSession() }
        }
    }

    // MARK: - Topics

    func loadTopics() {
        guard let data = try? Data(contentsOf: AppStore.topicsFileURL) else { return }
        topics = (try? JSONDecoder().decode([Topic].self, from: data)) ?? []
    }

    func saveTopics() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(topics) else { return }
        try? data.write(to: AppStore.topicsFileURL, options: .atomic)
    }

    func addTopic(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !topics.contains(where: { $0.text.lowercased() == trimmed.lowercased() }) else { return }
        topics.append(Topic(text: trimmed))
        saveTopics()
    }

    func togglePause(id: UUID) {
        guard let i = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[i].isPaused.toggle()
        saveTopics()
    }

    func deleteTopic(id: UUID) {
        topics.removeAll { $0.id == id }
        saveTopics()
    }

    // MARK: - User actions

    func revealAnswer(for id: UUID) {
        if let i = wikiQuestions.firstIndex(where: { $0.id == id }) {
            wikiQuestions[i].isRevealed = true
        } else if let i = nonWikiQuestions.firstIndex(where: { $0.id == id }) {
            nonWikiQuestions[i].isRevealed = true
        }
        saveSession()
    }

    func rateQuestion(id: UUID, rating: SRSRating) async {
        if let i = wikiQuestions.firstIndex(where: { $0.id == id }) {
            wikiQuestions[i].srsRating = rating
            saveSession()
        } else if let i = nonWikiQuestions.firstIndex(where: { $0.id == id }) {
            nonWikiQuestions[i].srsRating = rating
            saveSession()
            if rating == .solid {
                await addToWiki(question: nonWikiQuestions[i])
            }
        }
    }

    func addToWiki(question: Question) async {
        let content = "**Q:** \(question.text)\n\n**A:** \(question.answer)"
        let topic = question.topic.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try wikiService.appendToWikiFile(
                topic: topic.isEmpty ? "general" : topic,
                content: content
            )
            if let i = nonWikiQuestions.firstIndex(where: { $0.id == question.id }) {
                nonWikiQuestions[i].isAddedToWiki = true
                saveSession()
            }
        } catch {
            sessionError = "Failed to save to wiki: \(error.localizedDescription)"
        }
    }

    func askFollowUp(question: Question, followUp: String) async -> String {
        let prompt = """
        Spaced repetition flashcard context:
        Q: \(question.text)
        A: \(question.answer)

        Follow-up question: \(followUp)

        Answer the follow-up directly and concisely (2-4 sentences). No preamble.
        """

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-l", "-c", "claude -p \"$DR_PROMPT\" --allowedTools WebSearch"]

            var env = ProcessInfo.processInfo.environment
            env["DR_PROMPT"] = prompt
            process.environment = env

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: result.isEmpty ? "No response received." : result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: "Could not start Claude: \(error.localizedDescription)")
            }
        }
    }

    func runGenerateScript() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        sessionError = nil

        let scriptURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dailyreview/generate.sh")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path, DaySession.todayString, "--fresh"]
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }

        loadSession()
        isRefreshing = false
    }

    // MARK: - Persistence

    func saveSession() {
        let session = DaySession(
            dateString: DaySession.todayString,
            wikiQuestions: wikiQuestions,
            nonWikiQuestions: nonWikiQuestions,
            wikiQuestionCount: wikiQuestionCount,
            nonWikiQuestionCount: nonWikiQuestionCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: AppStore.sessionFileURL, options: .atomic)
    }
}
