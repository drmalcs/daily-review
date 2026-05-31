import Foundation

enum QuestionType: String, Codable, Sendable {
    case wiki
    case nonWiki
}

enum SRSRating: String, Codable, Sendable {
    case miss, hazy, solid
}

struct Question: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var text: String
    var answer: String
    var type: QuestionType
    var isRevealed: Bool = false
    var isAddedToWiki: Bool = false
    var srsRating: SRSRating? = nil
}

struct DaySession: Codable, Sendable {
    var dateString: String
    var wikiQuestions: [Question]
    var nonWikiQuestions: [Question]
    var topicForTomorrow: String
    var currentNonWikiTopic: String
    // Included so the scheduled agent knows the targets without needing UserDefaults
    var wikiQuestionCount: Int
    var nonWikiQuestionCount: Int

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    static var todayString: String {
        dateFormatter.string(from: Date())
    }

    var allQuestions: [Question] { wikiQuestions + nonWikiQuestions }
    var allRated: Bool { !allQuestions.isEmpty && allQuestions.allSatisfy { $0.srsRating != nil } }
}
