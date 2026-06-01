import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var wikiQuestions: [Question] = []
    @Published var nonWikiQuestions: [Question] = []
    @Published var topicForTomorrow: String = ""
    @Published var currentNonWikiTopic: String = ""

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

    // ~/.dailyreview/session.json — shared with the nightly Claude Code agent
    static let sessionFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dailyreview")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }()

    init() {
        let storedWiki = UserDefaults.standard.integer(forKey: "wikiQuestionCount")
        wikiQuestionCount = storedWiki > 0 ? storedWiki : 5
        let storedNon = UserDefaults.standard.integer(forKey: "nonWikiQuestionCount")
        nonWikiQuestionCount = storedNon > 0 ? storedNon : 2

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
            // Agent hasn't run for today yet — show unrated carryovers as a placeholder
            wikiQuestions    = session.wikiQuestions.filter    { $0.srsRating == nil }
            nonWikiQuestions = session.nonWikiQuestions.filter { $0.srsRating == nil }
            topicForTomorrow    = session.topicForTomorrow
            currentNonWikiTopic = session.currentNonWikiTopic
            awaitingAgent = true
        }

        // Sync counts from file if they've changed elsewhere.
        // isLoadingSession prevents didSet from triggering saveSession() here.
        isLoadingSession = true
        wikiQuestionCount    = session.wikiQuestionCount    > 0 ? session.wikiQuestionCount    : wikiQuestionCount
        nonWikiQuestionCount = session.nonWikiQuestionCount > 0 ? session.nonWikiQuestionCount : nonWikiQuestionCount
        isLoadingSession = false
    }

    private func applySession(_ session: DaySession) {
        wikiQuestions       = session.wikiQuestions
        nonWikiQuestions    = session.nonWikiQuestions
        topicForTomorrow    = session.topicForTomorrow
        currentNonWikiTopic = session.currentNonWikiTopic
    }

    // Polls every 5 min so the app picks up the agent's new file while it's open overnight
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.loadSession() }
        }
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
        let topic = currentNonWikiTopic.trimmingCharacters(in: .whitespacesAndNewlines)

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

    func updateTopicForTomorrow(_ raw: String) {
        topicForTomorrow = sanitiseTopic(raw)
        saveSession()
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
            // --fresh ignores existing answers; today's date shows results immediately
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
            topicForTomorrow: topicForTomorrow,
            currentNonWikiTopic: currentNonWikiTopic,
            wikiQuestionCount: wikiQuestionCount,
            nonWikiQuestionCount: nonWikiQuestionCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: AppStore.sessionFileURL, options: .atomic)
    }

    // MARK: - Input validation

    private func sanitiseTopic(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(stripped))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 200 ? String(cleaned.prefix(200)) : cleaned
    }
}
