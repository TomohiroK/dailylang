import Foundation

public enum LessonGenerationSource: String, Codable, Sendable {
    case local
    case openAI

    public var japaneseName: String {
        switch self {
        case .local:
            "端末内生成"
        case .openAI:
            "OpenAI生成"
        }
    }
}

public struct VocabularyItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var jp: String

    public init(id: String, jp: String) {
        self.id = id
        self.jp = jp
    }

    public func appearsInMainSentence(_ sentence: String) -> Bool {
        Self.phraseTokens(id).isContiguousSubsequence(of: Self.phraseTokens(sentence))
    }

    public static func itemsUsedInMainSentence(
        _ sentence: String,
        vocabulary: [VocabularyItem]
    ) -> [VocabularyItem] {
        var seen = Set<[String]>()
        return vocabulary.compactMap { item in
            let trimmedID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedJP = item.jp.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = phraseTokens(trimmedID)
            guard !tokens.isEmpty,
                  !trimmedJP.isEmpty,
                  tokens.isContiguousSubsequence(of: phraseTokens(sentence)),
                  seen.insert(tokens).inserted
            else {
                return nil
            }

            return VocabularyItem(id: trimmedID, jp: trimmedJP)
        }
    }

    private static func phraseTokens(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "id_ID"))
            .lowercased()
        var tokens: [String] = []
        var current = ""

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}

public struct ConversationLine: Codable, Equatable, Sendable {
    public var speaker: String
    public var id: String
    public var jp: String

    public init(speaker: String, id: String, jp: String) {
        self.speaker = speaker
        self.id = id
        self.jp = jp
    }
}

public struct SimilarExpression: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var jp: String

    public init(id: String, jp: String) {
        self.id = id
        self.jp = jp
    }
}

public struct Lesson: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var mainSentenceID: String
    public var mainSentenceJP: String
    public var vocabulary: [VocabularyItem]
    public var grammarNote: String
    public var conversation: [ConversationLine]
    public var similarExpressions: [SimilarExpression]
    public var source: LessonGenerationSource

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mainSentenceID: String,
        mainSentenceJP: String,
        vocabulary: [VocabularyItem],
        grammarNote: String,
        conversation: [ConversationLine],
        similarExpressions: [SimilarExpression],
        source: LessonGenerationSource
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mainSentenceID = mainSentenceID
        self.mainSentenceJP = mainSentenceJP
        self.vocabulary = vocabulary
        self.grammarNote = grammarNote
        self.conversation = conversation
        self.similarExpressions = similarExpressions
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case mainSentenceID = "main_sentence_id"
        case mainSentenceJP = "main_sentence_jp"
        case vocabulary
        case grammarNote = "grammar_note"
        case conversation
        case similarExpressions = "similar_expressions"
        case source
    }
}

public enum GeneratedLessonPayloadError: Error, Equatable {
    case invalidContent
}

public enum LessonTextValidation {
    public static func hasJapaneseText(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x309F, // Hiragana
                 0x30A0...0x30FF, // Katakana
                 0x3400...0x4DBF, // CJK Extension A
                 0x4E00...0x9FFF, // CJK Unified Ideographs
                 0xFF66...0xFF9D: // Half-width Katakana
                true
            default:
                false
            }
        }
    }
}

public enum StoredJSONDecodeState<Value>: Sendable where Value: Sendable {
    case decoded(Value)
    case unreadable

    public var value: Value? {
        switch self {
        case .decoded(let value):
            value
        case .unreadable:
            nil
        }
    }

    public var isUnreadable: Bool {
        switch self {
        case .decoded:
            false
        case .unreadable:
            true
        }
    }
}

public enum StoredJSONCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let data = Data(string.utf8)
        return try JSONDecoder().decode(type, from: data)
    }

    public static func decodeState<T: Decodable & Sendable>(
        _ type: T.Type,
        from string: String
    ) -> StoredJSONDecodeState<T> {
        do {
            return .decoded(try decode(type, from: string))
        } catch {
            return .unreadable
        }
    }
}

public struct GeneratedLessonPayload: Codable, Equatable, Sendable {
    private static let minimumVocabularyCount = 4

    public var mainSentenceID: String
    public var mainSentenceJP: String
    public var vocabulary: [VocabularyItem]
    public var grammarNote: String
    public var conversation: [ConversationLine]
    public var similarExpressions: [SimilarExpression]

    public init(
        mainSentenceID: String,
        mainSentenceJP: String,
        vocabulary: [VocabularyItem],
        grammarNote: String,
        conversation: [ConversationLine],
        similarExpressions: [SimilarExpression]
    ) {
        self.mainSentenceID = mainSentenceID
        self.mainSentenceJP = mainSentenceJP
        self.vocabulary = vocabulary
        self.grammarNote = grammarNote
        self.conversation = conversation
        self.similarExpressions = similarExpressions
    }

    enum CodingKeys: String, CodingKey {
        case mainSentenceID = "main_sentence_id"
        case mainSentenceJP = "main_sentence_jp"
        case vocabulary
        case grammarNote = "grammar_note"
        case conversation
        case similarExpressions = "similar_expressions"
    }

    public func lesson(source: LessonGenerationSource) throws -> Lesson {
        let vocabularyUsedInMainSentence = VocabularyItem.itemsUsedInMainSentence(
            mainSentenceID,
            vocabulary: vocabulary
        )

        guard isValid(vocabularyUsedInMainSentence: vocabularyUsedInMainSentence) else {
            throw GeneratedLessonPayloadError.invalidContent
        }

        return Lesson(
            mainSentenceID: mainSentenceID,
            mainSentenceJP: mainSentenceJP,
            vocabulary: vocabularyUsedInMainSentence,
            grammarNote: grammarNote,
            conversation: conversation,
            similarExpressions: similarExpressions,
            source: source
        )
    }

    private func isValid(vocabularyUsedInMainSentence: [VocabularyItem]) -> Bool {
        mainSentenceID.isLikelyIndonesianText
            && LessonTextValidation.hasJapaneseText(mainSentenceJP)
            && vocabularyUsedInMainSentence.count >= Self.minimumVocabularyCount
            && vocabularyUsedInMainSentence.allSatisfy { $0.id.isLikelyIndonesianText }
            && !grammarNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && conversation.count >= 2
            && conversation.allSatisfy { $0.id.isLikelyIndonesianText && !$0.jp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && similarExpressions.count >= 3
            && similarExpressions.allSatisfy { $0.id.isLikelyIndonesianText && !$0.jp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private extension Array where Element == String {
    func isContiguousSubsequence(of sentenceTokens: [String]) -> Bool {
        guard !isEmpty, count <= sentenceTokens.count else {
            return false
        }

        if count == 1 {
            return sentenceTokens.contains(self[0])
        }

        for startIndex in 0...(sentenceTokens.count - count) {
            let endIndex = startIndex + count
            if Array(sentenceTokens[startIndex..<endIndex]) == self {
                return true
            }
        }

        return false
    }
}

private extension String {
    var isLikelyIndonesianText: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return false
        }

        return trimmed.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) && scalar.isASCII
        }
    }
}
