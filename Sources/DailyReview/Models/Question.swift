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
    var eli5Answer: String? = nil       // cached ELI5 explanation (generated on demand)
    var eli5IsPreferred: Bool = false   // true when user rated AGAIN/HARD while in ELI5 mode
    // SM-2 spaced repetition scheduling
    var interval: Int = 0              // days until next review (0 = new card)
    var easeFactor: Double = 2.5       // SM-2 ease multiplier (min 1.3)
    var nextReviewDate: String? = nil  // YYYY-MM-DD; nil = new card, due immediately

    // Custom decoder so sessions generated before any given field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,         forKey: .id)
        text            = try c.decode(String.self,       forKey: .text)
        answer          = try c.decode(String.self,       forKey: .answer)
        type            = try c.decode(QuestionType.self, forKey: .type)
        topic           = try c.decodeIfPresent(String.self,    forKey: .topic)           ?? ""
        isRevealed      = try c.decodeIfPresent(Bool.self,      forKey: .isRevealed)      ?? false
        isAddedToWiki   = try c.decodeIfPresent(Bool.self,      forKey: .isAddedToWiki)   ?? false
        srsRating       = try c.decodeIfPresent(SRSRating.self, forKey: .srsRating)
        eli5Answer      = try c.decodeIfPresent(String.self,    forKey: .eli5Answer)
        eli5IsPreferred = try c.decodeIfPresent(Bool.self,      forKey: .eli5IsPreferred) ?? false
        interval        = try c.decodeIfPresent(Int.self,       forKey: .interval)        ?? 0
        easeFactor      = try c.decodeIfPresent(Double.self,    forKey: .easeFactor)      ?? 2.5
        nextReviewDate  = try c.decodeIfPresent(String.self,    forKey: .nextReviewDate)
    }
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
