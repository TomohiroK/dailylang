import Foundation

public struct ImageKeyword: Codable, Equatable, Identifiable, Sendable {
    public var label: String
    public var confidence: Double
    public var count: Int

    public var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label
        case confidence
        case count
    }

    public init(label: String, confidence: Double, count: Int = 1) {
        self.label = label
        self.confidence = confidence
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        confidence = try container.decode(Double.self, forKey: .confidence)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
    }
}

public struct SceneContext: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var timeText: String
    public var dayText: String
    public var locationLabel: LocationLabel
    public var imageKeywords: [ImageKeyword]
    public var userNote: String
    public var languageLevel: LanguageLevel

    public init(
        capturedAt: Date = Date(),
        timeText: String,
        dayText: String,
        locationLabel: LocationLabel,
        imageKeywords: [ImageKeyword],
        userNote: String = "",
        languageLevel: LanguageLevel
    ) {
        self.capturedAt = capturedAt
        self.timeText = timeText
        self.dayText = dayText
        self.locationLabel = locationLabel
        self.imageKeywords = imageKeywords
        self.userNote = userNote
        self.languageLevel = languageLevel
    }

    public var keywordLabels: [String] {
        imageKeywords.map(\.label)
    }
}
