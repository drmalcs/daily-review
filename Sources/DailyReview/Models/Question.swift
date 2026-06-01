import Foundation

enum QuestionType: String, Codable, Sendable {
    case wiki
    case nonWiki
}

enum SRSRating: String, Codable, Sendable {
    case miss, hazy, solid, boring
}

struct Question: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var text: String
    var answer: String
    var type: QuestionType
    var topic: String = ""         // set for nonWiki questions; used when adding to wiki
    var isRevealed: Bool = false
    var isAddedToWiki: Bool = false
    var srsRating: SRSRating? = nil
}

struct Topic: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var text: String
    var isPaused: Bool = false
}

struct DaySession: Codable, Sendable {
    var dateString: String
    var wikiQuestions: [Question]
    var nonWikiQuestions: [Question]
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

    // Decode gracefully — old sessions may have topicForTomorrow/currentNonWikiTopic
    enum CodingKeys: String, CodingKey {
        case dateString, wikiQuestions, nonWikiQuestions
        case wikiQuestionCount, nonWikiQuestionCount
        // ignored legacy keys: topicForTomorrow, currentNonWikiTopic
    }
}
