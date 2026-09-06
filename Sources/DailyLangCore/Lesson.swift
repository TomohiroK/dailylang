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
                  LessonTextValidation.isValidVocabularyMeaning(trimmedJP, for: trimmedID),
                  tokens.isContiguousSubsequence(of: phraseTokens(sentence)),
                  seen.insert(tokens).inserted
            else {
                return nil
            }

            return VocabularyItem(id: trimmedID, jp: trimmedJP)
        }
    }

    public static func itemsUsedInMainSentence(
        _ sentence: String,
        vocabulary: [VocabularyItem],
        minimumCount: Int,
        lessonLanguage: LessonLanguage = .indonesian
    ) -> [VocabularyItem] {
        var items = itemsUsedInMainSentence(sentence, vocabulary: vocabulary)
        guard items.count < minimumCount else {
            return items
        }

        var seen = Set(items.map { phraseTokens($0.id) })
        for item in supplementalVocabulary(for: lessonLanguage) where item.appearsInMainSentence(sentence) {
            let tokens = phraseTokens(item.id)
            guard seen.insert(tokens).inserted else {
                continue
            }

            items.append(item)
            if items.count >= minimumCount {
                break
            }
        }

        return items
    }

    private static func supplementalVocabulary(for language: LessonLanguage) -> [VocabularyItem] {
        switch language {
        case .indonesian:
            indonesianSupplementalVocabulary
        case .english:
            englishSupplementalVocabulary
        }
    }

    private static let indonesianSupplementalVocabulary: [VocabularyItem] = [
        VocabularyItem(id: "sambil", jp: "〜しながら"),
        VocabularyItem(id: "sebelum", jp: "〜する前に"),
        VocabularyItem(id: "setelah", jp: "〜した後で"),
        VocabularyItem(id: "karena", jp: "なぜなら"),
        VocabularyItem(id: "untuk", jp: "〜するために"),
        VocabularyItem(id: "sepertinya", jp: "どうやら、〜のようだ"),
        VocabularyItem(id: "mulai", jp: "始める"),
        VocabularyItem(id: "saya", jp: "私"),
        VocabularyItem(id: "ini", jp: "これ、この"),
        VocabularyItem(id: "itu", jp: "それ、その"),
        VocabularyItem(id: "ada", jp: "ある、いる"),
        VocabularyItem(id: "melihat", jp: "見る"),
        VocabularyItem(id: "memakai", jp: "使う"),
        VocabularyItem(id: "menggunakan", jp: "使う"),
        VocabularyItem(id: "mengecek", jp: "確認する"),
        VocabularyItem(id: "membuka", jp: "開く"),
        VocabularyItem(id: "menaruh", jp: "置く"),
        VocabularyItem(id: "meletakkan", jp: "置く"),
        VocabularyItem(id: "menyimpan", jp: "しまう、保管する"),
        VocabularyItem(id: "bekerja", jp: "働く、作業する"),
        VocabularyItem(id: "dan", jp: "そして"),
        VocabularyItem(id: "dengan", jp: "〜と、〜で"),
        VocabularyItem(id: "di", jp: "〜で、〜に"),
        VocabularyItem(id: "di atas", jp: "〜の上に"),
        VocabularyItem(id: "dekat", jp: "〜の近くに"),
        VocabularyItem(id: "dalam", jp: "〜の中に"),
        VocabularyItem(id: "agak", jp: "少し、やや"),
        VocabularyItem(id: "terburu-buru", jp: "急いでいる"),
        VocabularyItem(id: "lebih", jp: "より、もっと"),
        VocabularyItem(id: "rapi", jp: "整った、きちんとした"),
        VocabularyItem(id: "pagi", jp: "朝"),
        VocabularyItem(id: "siang", jp: "昼"),
        VocabularyItem(id: "sore", jp: "夕方"),
        VocabularyItem(id: "malam", jp: "夜"),
        VocabularyItem(id: "pukul", jp: "〜時"),
        VocabularyItem(id: "Jumat", jp: "金曜日"),
        VocabularyItem(id: "laptop", jp: "ノートパソコン"),
        VocabularyItem(id: "komputer", jp: "パソコン"),
        VocabularyItem(id: "keyboard", jp: "キーボード"),
        VocabularyItem(id: "dokumen", jp: "書類"),
        VocabularyItem(id: "screenshot", jp: "スクリーンショット"),
        VocabularyItem(id: "jam", jp: "時計、時刻"),
        VocabularyItem(id: "jam digital", jp: "デジタル時計"),
        VocabularyItem(id: "pisang", jp: "バナナ"),
        VocabularyItem(id: "susu", jp: "牛乳"),
        VocabularyItem(id: "cangkir", jp: "カップ"),
        VocabularyItem(id: "gelas", jp: "コップ、グラス"),
        VocabularyItem(id: "keranjang", jp: "かご"),
        VocabularyItem(id: "botol", jp: "ボトル"),
        VocabularyItem(id: "kabel", jp: "ケーブル、コード"),
        VocabularyItem(id: "tali", jp: "ひも、ストラップ"),
        VocabularyItem(id: "teko air", jp: "水差し"),
        VocabularyItem(id: "kendi", jp: "水差し、つぼ"),
        VocabularyItem(id: "toples", jp: "瓶、保存容器"),
        VocabularyItem(id: "stoples", jp: "瓶、保存容器"),
        VocabularyItem(id: "wadah", jp: "容器"),
        VocabularyItem(id: "vas", jp: "花瓶"),
        VocabularyItem(id: "kursi", jp: "椅子"),
        VocabularyItem(id: "jendela", jp: "窓"),
        VocabularyItem(id: "tirai", jp: "カーテン"),
        VocabularyItem(id: "gorden", jp: "カーテン"),
        VocabularyItem(id: "perabot", jp: "家具"),
        VocabularyItem(id: "meja", jp: "机、テーブル"),
        VocabularyItem(id: "pintu", jp: "ドア"),
        VocabularyItem(id: "gerbang", jp: "門、ゲート"),
        VocabularyItem(id: "skuter", jp: "スクーター"),
        VocabularyItem(id: "sepeda motor", jp: "バイク、オートバイ"),
        VocabularyItem(id: "mobil", jp: "車"),
        VocabularyItem(id: "orang", jp: "人"),
    ]

    private static let englishSupplementalVocabulary: [VocabularyItem] = [
        VocabularyItem(id: "while", jp: "〜している間に、〜しながら"),
        VocabularyItem(id: "before", jp: "〜する前に"),
        VocabularyItem(id: "after", jp: "〜した後で"),
        VocabularyItem(id: "because", jp: "なぜなら、〜なので"),
        VocabularyItem(id: "although", jp: "〜だけれども"),
        VocabularyItem(id: "when", jp: "〜するとき"),
        VocabularyItem(id: "with", jp: "〜と一緒に、〜を使って"),
        VocabularyItem(id: "near", jp: "〜の近くに"),
        VocabularyItem(id: "inside", jp: "〜の中に、屋内で"),
        VocabularyItem(id: "outside", jp: "外で"),
        VocabularyItem(id: "start", jp: "始める"),
        VocabularyItem(id: "check", jp: "確認する"),
        VocabularyItem(id: "open", jp: "開ける、開く"),
        VocabularyItem(id: "use", jp: "使う"),
        VocabularyItem(id: "using", jp: "使っている"),
        VocabularyItem(id: "look", jp: "見る"),
        VocabularyItem(id: "read", jp: "読む"),
        VocabularyItem(id: "work", jp: "働く、作業する"),
        VocabularyItem(id: "study", jp: "勉強する"),
        VocabularyItem(id: "wait", jp: "待つ"),
        VocabularyItem(id: "carry", jp: "持ち運ぶ"),
        VocabularyItem(id: "drink", jp: "飲む"),
        VocabularyItem(id: "eat", jp: "食べる"),
        VocabularyItem(id: "home", jp: "自宅、家"),
        VocabularyItem(id: "office", jp: "会社、オフィス"),
        VocabularyItem(id: "school", jp: "学校"),
        VocabularyItem(id: "park", jp: "公園"),
        VocabularyItem(id: "restaurant", jp: "レストラン"),
        VocabularyItem(id: "cafe", jp: "カフェ"),
        VocabularyItem(id: "train", jp: "電車"),
        VocabularyItem(id: "bus", jp: "バス"),
        VocabularyItem(id: "friend", jp: "友人"),
        VocabularyItem(id: "laptop", jp: "ノートパソコン"),
        VocabularyItem(id: "document", jp: "書類"),
        VocabularyItem(id: "book", jp: "本"),
        VocabularyItem(id: "bottle", jp: "ボトル"),
        VocabularyItem(id: "cup", jp: "カップ"),
        VocabularyItem(id: "basket", jp: "かご"),
        VocabularyItem(id: "table", jp: "机、テーブル"),
        VocabularyItem(id: "window", jp: "窓"),
    ]

    private static func phraseTokens(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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

public enum GeneratedLessonPayloadError: Error, Equatable, LocalizedError {
    case invalidMainSentence
    case overlyGenericMainSentence
    case invalidMainSentenceTranslation
    case insufficientVocabulary(validCount: Int, minimumCount: Int, rejectedItems: [String])
    case invalidGrammarNote
    case insufficientConversation(actualCount: Int)
    case invalidConversationLine(index: Int)
    case invalidConversationTranslation(index: Int)
    case insufficientSimilarExpressions(actualCount: Int)
    case invalidSimilarExpression(index: Int)
    case invalidSimilarExpressionTranslation(index: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidMainSentence:
            return "main_sentence_id is not valid target-language text"
        case .overlyGenericMainSentence:
            return "main_sentence_id is overly generic"
        case .invalidMainSentenceTranslation:
            return "main_sentence_jp is not a valid Japanese translation"
        case .insufficientVocabulary(let validCount, let minimumCount, let rejectedItems):
            let rejected = rejectedItems.isEmpty
                ? "none"
                : rejectedItems.joined(separator: ", ")
            return "vocabulary has \(validCount) valid in-sentence items; requires \(minimumCount); rejected: \(rejected)"
        case .invalidGrammarNote:
            return "grammar_note is not valid Japanese"
        case .insufficientConversation(let actualCount):
            return "conversation has \(actualCount) lines; requires at least 2"
        case .invalidConversationLine(let index):
            return "conversation[\(index)].id is not valid target-language text"
        case .invalidConversationTranslation(let index):
            return "conversation[\(index)].jp is not a valid Japanese translation"
        case .insufficientSimilarExpressions(let actualCount):
            return "similar_expressions has \(actualCount) items; requires at least 3"
        case .invalidSimilarExpression(let index):
            return "similar_expressions[\(index)].id is not valid target-language text"
        case .invalidSimilarExpressionTranslation(let index):
            return "similar_expressions[\(index)].jp is not a valid Japanese translation"
        }
    }
}

public enum LessonTextValidation {
    private static let overlyGenericLessonTexts: Set<String> = [
        "saya sedang belajar",
        "saya belajar",
        "saya sedang bekerja",
        "saya bekerja",
        "i am studying",
        "i m studying",
        "i study",
        "i am working",
        "i m working",
        "i work",
    ]

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

    public static func containsDisallowedTranslationScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0E00...0x0E7F, // Thai
                 0x0E80...0x0EFF, // Lao
                 0x1000...0x109F, // Myanmar
                 0x1780...0x17FF: // Khmer
                true
            default:
                false
            }
        }
    }

    public static func isValidJapaneseTranslation(_ text: String, sourceText: String? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasJapaneseText(trimmed),
              !containsDisallowedTranslationScript(trimmed)
        else {
            return false
        }

        if let sourceText,
           normalizedLatinText(trimmed) == normalizedLatinText(sourceText) {
            return false
        }

        return true
    }

    public static func isValidVocabularyMeaning(_ text: String, for sourceText: String) -> Bool {
        isValidJapaneseTranslation(text, sourceText: sourceText)
    }

    public static func indonesianWordCount(_ text: String) -> Int {
        wordCount(text)
    }

    public static func wordCount(_ text: String) -> Int {
        wordTokens(text).count
    }

    public static func isOverlyGenericLessonText(_ text: String) -> Bool {
        overlyGenericLessonTexts.contains(normalizedPhrase(text))
    }

    private static func wordTokens(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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

    private static func normalizedLatinText(_ text: String) -> String {
        text.unicodeScalars.reduce(into: "") { result, scalar in
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                guard let lowercasedScalar = String(scalar).lowercased().unicodeScalars.first else {
                    return
                }
                result.unicodeScalars.append(lowercasedScalar)
            }
        }
    }

    private static func normalizedPhrase(_ text: String) -> String {
        wordTokens(text).joined(separator: " ")
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
    private static let defaultMinimumVocabularyCount = 3

    public var mainSentenceID: String
    public var mainSentenceJP: String
    public var mainSentenceWordCount: Int?
    public var vocabulary: [VocabularyItem]
    public var grammarNote: String
    public var conversation: [ConversationLine]
    public var similarExpressions: [SimilarExpression]
    public var usedKeywords: [String]

    public init(
        mainSentenceID: String,
        mainSentenceJP: String,
        mainSentenceWordCount: Int? = nil,
        vocabulary: [VocabularyItem],
        grammarNote: String,
        conversation: [ConversationLine],
        similarExpressions: [SimilarExpression],
        usedKeywords: [String] = []
    ) {
        self.mainSentenceID = mainSentenceID
        self.mainSentenceJP = mainSentenceJP
        self.mainSentenceWordCount = mainSentenceWordCount
        self.vocabulary = vocabulary
        self.grammarNote = grammarNote
        self.conversation = conversation
        self.similarExpressions = similarExpressions
        self.usedKeywords = usedKeywords
    }

    enum CodingKeys: String, CodingKey {
        case mainSentenceID = "main_sentence_id"
        case mainSentenceJP = "main_sentence_jp"
        case mainSentenceWordCount = "main_sentence_word_count"
        case vocabulary
        case grammarNote = "grammar_note"
        case conversation
        case similarExpressions = "similar_expressions"
        case usedKeywords = "used_keywords"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainSentenceID = try container.decode(String.self, forKey: .mainSentenceID)
        mainSentenceJP = try container.decode(String.self, forKey: .mainSentenceJP)
        mainSentenceWordCount = try container.decodeIfPresent(Int.self, forKey: .mainSentenceWordCount)
        vocabulary = try container.decode([VocabularyItem].self, forKey: .vocabulary)
        grammarNote = try container.decode(String.self, forKey: .grammarNote)
        conversation = try container.decode([ConversationLine].self, forKey: .conversation)
        similarExpressions = try container.decode([SimilarExpression].self, forKey: .similarExpressions)
        usedKeywords = try container.decodeIfPresent([String].self, forKey: .usedKeywords) ?? []
    }

    public func lesson(
        source: LessonGenerationSource,
        languageLevel: LanguageLevel? = nil,
        lessonLanguage: LessonLanguage = .indonesian
    ) throws -> Lesson {
        let minimumVocabularyCount = languageLevel?.minimumVocabularyCount
            ?? Self.defaultMinimumVocabularyCount
        let providedVocabularyUsedInMainSentence = VocabularyItem.itemsUsedInMainSentence(
            mainSentenceID,
            vocabulary: vocabulary
        )
        if providedVocabularyUsedInMainSentence.count < minimumVocabularyCount,
           hasInvalidInSentenceVocabularyMeaning {
            throw GeneratedLessonPayloadError.insufficientVocabulary(
                validCount: providedVocabularyUsedInMainSentence.count,
                minimumCount: minimumVocabularyCount,
                rejectedItems: rejectedVocabularyItems()
            )
        }

        let vocabularyUsedInMainSentence: [VocabularyItem]
        if languageLevel == nil {
            vocabularyUsedInMainSentence = providedVocabularyUsedInMainSentence
        } else {
            vocabularyUsedInMainSentence = VocabularyItem.itemsUsedInMainSentence(
                mainSentenceID,
                vocabulary: vocabulary,
                minimumCount: minimumVocabularyCount,
                lessonLanguage: lessonLanguage
            )
        }
        let validConversation = conversation.filter { line in
            line.id.isLikelyTargetLanguageText
                && LessonTextValidation.isValidJapaneseTranslation(line.jp, sourceText: line.id)
        }
        let lessonConversation = isCoherentConversation(validConversation)
            ? validConversation
            : conversation
        let validSimilarExpressions = similarExpressions.filter { expression in
            expression.id.isLikelyTargetLanguageText
                && LessonTextValidation.isValidJapaneseTranslation(
                    expression.jp,
                    sourceText: expression.id
                )
        }
        let lessonSimilarExpressions = validSimilarExpressions.count >= 3
            ? validSimilarExpressions
            : similarExpressions

        try validate(
            vocabularyUsedInMainSentence: vocabularyUsedInMainSentence,
            minimumVocabularyCount: minimumVocabularyCount,
            conversation: lessonConversation,
            similarExpressions: lessonSimilarExpressions
        )
        let finalVocabulary: [VocabularyItem]
        if let languageLevel {
            finalVocabulary = Array(vocabularyUsedInMainSentence.prefix(languageLevel.maximumVocabularyCount))
        } else {
            finalVocabulary = vocabularyUsedInMainSentence
        }

        return Lesson(
            mainSentenceID: mainSentenceID,
            mainSentenceJP: mainSentenceJP,
            vocabulary: finalVocabulary,
            grammarNote: grammarNote,
            conversation: lessonConversation,
            similarExpressions: lessonSimilarExpressions,
            source: source
        )
    }

    private func validate(
        vocabularyUsedInMainSentence: [VocabularyItem],
        minimumVocabularyCount: Int,
        conversation: [ConversationLine],
        similarExpressions: [SimilarExpression]
    ) throws {
        guard mainSentenceID.isLikelyTargetLanguageText else {
            throw GeneratedLessonPayloadError.invalidMainSentence
        }
        guard !LessonTextValidation.isOverlyGenericLessonText(mainSentenceID) else {
            throw GeneratedLessonPayloadError.overlyGenericMainSentence
        }
        guard LessonTextValidation.isValidJapaneseTranslation(
            mainSentenceJP,
            sourceText: mainSentenceID
        ) else {
            throw GeneratedLessonPayloadError.invalidMainSentenceTranslation
        }
        guard vocabularyUsedInMainSentence.count >= minimumVocabularyCount else {
            throw GeneratedLessonPayloadError.insufficientVocabulary(
                validCount: vocabularyUsedInMainSentence.count,
                minimumCount: minimumVocabularyCount,
                rejectedItems: rejectedVocabularyItems()
            )
        }
        guard LessonTextValidation.isValidJapaneseTranslation(grammarNote) else {
            throw GeneratedLessonPayloadError.invalidGrammarNote
        }
        guard conversation.count >= 2 else {
            throw GeneratedLessonPayloadError.insufficientConversation(actualCount: conversation.count)
        }
        for (index, line) in conversation.enumerated() {
            guard line.id.isLikelyTargetLanguageText else {
                throw GeneratedLessonPayloadError.invalidConversationLine(index: index)
            }
            guard LessonTextValidation.isValidJapaneseTranslation(line.jp, sourceText: line.id) else {
                throw GeneratedLessonPayloadError.invalidConversationTranslation(index: index)
            }
        }
        guard similarExpressions.count >= 3 else {
            throw GeneratedLessonPayloadError.insufficientSimilarExpressions(
                actualCount: similarExpressions.count
            )
        }
        for (index, expression) in similarExpressions.enumerated() {
            guard expression.id.isLikelyTargetLanguageText else {
                throw GeneratedLessonPayloadError.invalidSimilarExpression(index: index)
            }
            guard LessonTextValidation.isValidJapaneseTranslation(
                expression.jp,
                sourceText: expression.id
            ) else {
                throw GeneratedLessonPayloadError.invalidSimilarExpressionTranslation(index: index)
            }
        }
    }

    private func rejectedVocabularyItems() -> [String] {
        vocabulary.compactMap { item in
            let trimmedID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.appearsInMainSentence(mainSentenceID) else {
                return "\(trimmedID) (not in main sentence)"
            }
            guard LessonTextValidation.isValidVocabularyMeaning(
                item.jp.trimmingCharacters(in: .whitespacesAndNewlines),
                for: trimmedID
            ) else {
                return "\(trimmedID) (invalid Japanese meaning)"
            }
            return nil
        }
    }

    private var hasInvalidInSentenceVocabularyMeaning: Bool {
        vocabulary.contains { item in
            let trimmedID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            return item.appearsInMainSentence(mainSentenceID)
                && !LessonTextValidation.isValidVocabularyMeaning(
                    item.jp.trimmingCharacters(in: .whitespacesAndNewlines),
                    for: trimmedID
                )
        }
    }

    private func isCoherentConversation(_ lines: [ConversationLine]) -> Bool {
        guard lines.count >= 2,
              lines.first?.speaker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "A"
        else {
            return false
        }

        for (previous, current) in zip(lines, lines.dropFirst()) {
            if previous.speaker.caseInsensitiveCompare(current.speaker) == .orderedSame {
                return false
            }
        }
        return true
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
    var isLikelyTargetLanguageText: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return false
        }

        return trimmed.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) && scalar.isASCII
        }
    }
}
