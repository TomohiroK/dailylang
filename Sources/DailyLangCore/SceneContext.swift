import Foundation

public enum KeywordRole: String, Codable, Sendable {
    case foreground
    case surface
    case context
}

public enum KeywordSource: String, Codable, Sendable {
    case vision
    case manual
}

public struct ImageKeyword: Codable, Equatable, Identifiable, Sendable {
    public var label: String
    public var confidence: Double
    public var count: Int
    public var role: KeywordRole
    public var source: KeywordSource

    public var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label
        case confidence
        case count
        case role
        case source
    }

    public init(
        label: String,
        confidence: Double,
        count: Int = 1,
        role: KeywordRole = .foreground,
        source: KeywordSource = .vision
    ) {
        self.label = label
        self.confidence = confidence
        self.count = count
        self.role = role
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        confidence = try container.decode(Double.self, forKey: .confidence)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        role = try container.decodeIfPresent(KeywordRole.self, forKey: .role) ?? .foreground
        source = try container.decodeIfPresent(KeywordSource.self, forKey: .source) ?? .vision
    }
}

public struct SceneContext: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var timeText: String
    public var dayText: String
    public var locationLabel: LocationLabel
    public var imageKeywords: [ImageKeyword]
    public var imageRelations: [String]
    public var userNote: String
    public var languageLevel: LanguageLevel
    public var lessonLanguage: LessonLanguage
    public var lessonSituation: LessonSituation
    public var lessonGrammarFocus: LessonGrammarFocus
    public var recentlyRepeatedExpressions: [String]

    public init(
        capturedAt: Date = Date(),
        timeText: String,
        dayText: String,
        locationLabel: LocationLabel,
        imageKeywords: [ImageKeyword],
        imageRelations: [String] = [],
        userNote: String = "",
        languageLevel: LanguageLevel,
        lessonLanguage: LessonLanguage = .indonesian,
        lessonSituation: LessonSituation = .random,
        lessonGrammarFocus: LessonGrammarFocus = .simpleStatement,
        recentlyRepeatedExpressions: [String] = []
    ) {
        self.capturedAt = capturedAt
        self.timeText = timeText
        self.dayText = dayText
        self.locationLabel = locationLabel
        self.imageKeywords = imageKeywords
        self.imageRelations = imageRelations
        self.userNote = userNote
        self.languageLevel = languageLevel
        self.lessonLanguage = lessonLanguage
        self.lessonSituation = lessonSituation
        self.lessonGrammarFocus = lessonGrammarFocus
        self.recentlyRepeatedExpressions = recentlyRepeatedExpressions
    }

    enum CodingKeys: String, CodingKey {
        case capturedAt
        case timeText
        case dayText
        case locationLabel
        case imageKeywords
        case imageRelations
        case userNote
        case languageLevel
        case lessonLanguage
        case lessonSituation
        case lessonGrammarFocus
        case recentlyRepeatedExpressions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        timeText = try container.decode(String.self, forKey: .timeText)
        dayText = try container.decode(String.self, forKey: .dayText)
        locationLabel = try container.decode(LocationLabel.self, forKey: .locationLabel)
        imageKeywords = try container.decode([ImageKeyword].self, forKey: .imageKeywords)
        imageRelations = try container.decodeIfPresent([String].self, forKey: .imageRelations) ?? []
        userNote = try container.decodeIfPresent(String.self, forKey: .userNote) ?? ""
        languageLevel = try container.decode(LanguageLevel.self, forKey: .languageLevel)
        lessonLanguage = try container.decodeIfPresent(LessonLanguage.self, forKey: .lessonLanguage)
            ?? .indonesian
        lessonSituation = try container.decodeIfPresent(LessonSituation.self, forKey: .lessonSituation)
            ?? .random
        lessonGrammarFocus = try container.decodeIfPresent(LessonGrammarFocus.self, forKey: .lessonGrammarFocus)
            ?? .simpleStatement
        recentlyRepeatedExpressions = try container.decodeIfPresent([String].self, forKey: .recentlyRepeatedExpressions)
            ?? []
    }

    public var keywordLabels: [String] {
        imageKeywords.map(\.label)
    }
}
