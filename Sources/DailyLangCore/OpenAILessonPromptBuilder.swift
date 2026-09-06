import Foundation

public struct OpenAILessonPrompt: Equatable, Sendable {
    public var instructions: String
    public var sceneJSON: String

    public init(instructions: String, sceneJSON: String) {
        self.instructions = instructions
        self.sceneJSON = sceneJSON
    }
}

public struct OpenAILessonPromptBuilder: Sendable {
    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func buildPrompt(from context: SceneContext) throws -> OpenAILessonPrompt {
        let payload = OpenAIScenePayload(context: context)
        let data = try encoder.encode(payload)
        let sceneJSON = String(decoding: data, as: UTF8.self)
        let language = context.lessonLanguage
        let targetLanguage = language.englishName
        let levelInstructions = Self.levelInstructions(
            for: context.languageLevel,
            language: language
        )
        let keywordGuidance = Self.keywordGuidance(for: language)
        let actionGuidance = Self.actionGuidance(for: language)
        let keywordActionPatternGuidance = Self.keywordActionPatternGuidance(
            for: context.imageKeywords,
            language: language
        )
        let genericSentenceGuidance = Self.genericSentenceGuidance(for: language)
        let situationGuidance = Self.situationGuidance(for: context.lessonSituation)
        let expressionVariationGuidance = Self.expressionVariationGuidance(
            for: context.recentlyRepeatedExpressions
        )
        let grammarFocusGuidance = context.lessonGrammarFocus.promptInstruction(for: language)

        return OpenAILessonPrompt(
            instructions: """
            You are an expert \(targetLanguage) tutor for a Japanese learner.
            Generate a DUO-style \(targetLanguage) lesson based on the user's real-life scene, selected situation, and learner level.

            Requirements:
            - Use natural \(targetLanguage).
            - Keep the main sentence practical.
            - `main_sentence_jp` must be a Japanese translation that exactly matches `main_sentence_id`, not \(targetLanguage) text and not a copy of `main_sentence_id`. Do not add a place, object, or action that is absent from `main_sentence_id`.
            - All `jp` fields must be Japanese. Do not use Thai, Lao, Khmer, or Myanmar script in any `jp` field.
            - Vocabulary `jp` must be the Japanese meaning. Never copy or romanize the \(targetLanguage) vocabulary `id` as its meaning.
            - Extract \(context.languageLevel.vocabularyCountGuidance). Do not exceed the current learner level's vocabulary limit.
            - Every vocabulary `id` must be an exact word or contiguous phrase copied from `main_sentence_id`.
            - Do not put image keyword labels, inferred objects, or related words in vocabulary unless the same \(targetLanguage) text appears in `main_sentence_id`.
            - Explain grammar briefly in Japanese.
            - Create a 2 to 4 line short conversation that could happen in this scene.
            - Create exactly 3 similar expressions.
            - Do not mention uncertain visual details as facts.
            - The photo itself is not provided.
            - Use only the supplied image_keywords, relations, time, day, situation, and user note as evidence.
            - `lesson_pattern` is a rotating grammar focus for this one lesson, not an additional visual fact. Use its requested pattern in `main_sentence_id` whenever it is natural and grounded.
            - If the requested pattern would require inventing a fact, use the closest natural expression from the same pattern family. Do not fall back to sambil, sepertinya, sedang, while, apparently, or a progressive form merely because it is familiar.
            - `sambil` / `while` are allowed only for the `parallel_action` lesson_pattern. `sepertinya` / `apparently` are allowed only for the `uncertainty` lesson_pattern. `sedang` / a progressive form are allowed only for the `current_action` lesson_pattern.
            - Selected lesson_pattern instruction: \(grammarFocusGuidance)
            - `situation` is a user-selected generation setting, not a location inferred from the device. Reflect it naturally in `main_sentence_id` through a place phrase, activity, or social context whenever it does not contradict concrete image_keywords or the user note.
            - \(situationGuidance)
            - \(expressionVariationGuidance)
            - image_keywords are on-device Vision/Core ML object-detection and image-classification labels with confidence scores, counts, roles, and sources.
            - Keywords with source "manual" are user-entered unverified hints. Correct obvious spelling before using them, and ignore them if they look nonexistent or inconsistent with stronger Vision keywords.
            - Keywords with role "surface" or "context" are background. They must not be the topic of the main sentence. Use them only as supporting location phrases if needed.
            - When one foreground keyword exists, the main sentence must mention that foreground object naturally. When two or more foreground keywords exist, mention at least two foreground objects, or one foreground object together with its relation from `relations`.
            - Prefer distinctive foreground objects such as food, flowers, tools, cups, and bottles over generic electronics when both are present.
            - \(keywordGuidance)
            - Do not force object keywords into location phrases. A keyboard or laptop is not a place.
            - \(actionGuidance)
            - \(keywordActionPatternGuidance)
            - Do not make wiping, cleaning, or working at furniture the main topic merely because a surface or furniture keyword is present. Use those actions when direct current-scene evidence or the user note supports them.
            - \(genericSentenceGuidance)
            - Do not invent objects, foods, reports, meetings, or actions unless those details appear in image_keywords or user note. A place may come from the selected situation.
            - If image_keywords are empty or vague, use a general daily-life sentence.
            - `used_keywords` must echo the original image keyword labels that are actually grounded in `main_sentence_id`.
            - In this schema, fields named `main_sentence_id` or `id` must contain \(targetLanguage) text, not numeric identifiers.
            - `main_sentence_id` must be one complete \(targetLanguage) sentence.
            - Match the current learner level's style and aim for its word-count target: beginner <= 7 words, intermediate 10-15 words, advanced 20-40 words. A natural, otherwise valid sentence outside the target is acceptable.
            - `main_sentence_word_count` must be the actual \(targetLanguage) word-token count of `main_sentence_id`.
            - Before returning JSON, count the \(targetLanguage) word tokens in `main_sentence_id`. Aim for \(context.languageLevel.preferredMainSentenceWordCountGuidance(for: language)). Do not include the count in the sentence.
            - `main_sentence_id` must support \(context.languageLevel.vocabularyCountGuidance) copied from that sentence.
            - Vocabulary `id`, conversation `id`, and similar expression `id` must also be \(targetLanguage) words or sentences.
            - Return only JSON that matches the requested schema.

            Current target language: \(language.rawValue)
            Current learner level: \(context.languageLevel.rawValue)
            Level contract:
            \(levelInstructions)
            """,
            sceneJSON: sceneJSON
        )
    }

    private static func keywordGuidance(for language: LessonLanguage) -> String {
        switch language {
        case .indonesian:
            "Translate image keyword evidence into natural Indonesian when needed, for example document -> dokumen, digital clock -> jam, cup -> cangkir, banana -> pisang, cord -> kabel or tali, water jug -> teko air, jar -> toples, vase -> vas, curtain -> tirai or gorden, motor scooter -> skuter or sepeda motor."
        case .english:
            "Turn image keyword evidence into natural English. Correct singular/plural and awkward classifier labels; for example consumer electronics -> device or electronics, motor scooter -> scooter, and water jug -> water bottle or jug according to context. Do not copy category jargon blindly."
        }
    }

    private static func actionGuidance(for language: LessonLanguage) -> String {
        switch language {
        case .indonesian:
            "Prefer natural object actions, for example membaca dokumen, menggunakan keyboard, melihat jam, makan pisang, or minum susu."
        case .english:
            "Prefer natural object actions, for example reading a document, using a keyboard, checking the time, eating a banana, or drinking milk."
        }
    }

    private static func keywordActionPatternGuidance(
        for keywords: [ImageKeyword],
        language: LessonLanguage
    ) -> String {
        let foregroundLabels = Set(
            keywords
                .filter { $0.role == .foreground }
                .map { normalizedKeywordLabel($0.label) }
        )
        let matchedPatterns = keywordActionPatterns.filter { pattern in
            pattern.matches(foregroundLabels)
        }

        let baseline = "For each foreground keyword, consider multiple distinct, natural action, relation, or social patterns before writing the sentence. These are candidate language choices, not visual claims: retain only the option grounded by the current image_keywords, relations, or user note."
        guard !matchedPatterns.isEmpty else {
            return baseline + " For an unfamiliar object, consider its use, observation, carrying, placement, preparation, exchange, or a simple relation before choosing the most natural grounded expression."
        }

        let descriptions = matchedPatterns.prefix(4).map { pattern in
            switch language {
            case .indonesian:
                pattern.indonesianDescription
            case .english:
                pattern.englishDescription
            }
        }
        return baseline + " Relevant daily-life action palettes: " + descriptions.joined(separator: "; ") + "."
    }

    private static func normalizedKeywordLabel(_ label: String) -> String {
        label
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func genericSentenceGuidance(for language: LessonLanguage) -> String {
        switch language {
        case .indonesian:
            "Generic sentences such as \"Saya sedang belajar.\" or \"Saya sedang bekerja.\" are invalid when concrete image_keywords are available."
        case .english:
            "Generic sentences such as \"I am studying.\" or \"I am working.\" are invalid when concrete image_keywords are available."
        }
    }

    private static let keywordActionPatterns: [KeywordActionPattern] = [
        KeywordActionPattern(
            labels: ["banana", "fruit", "apple", "orange", "bread", "rice", "snack", "food", "meal"],
            indonesianDescription: "food: makan, memilih, membawa, menyiapkan, menyajikan, atau menaruh",
            englishDescription: "food: eat, choose, carry, prepare, serve, or place"
        ),
        KeywordActionPattern(
            labels: ["milk", "coffee", "tea", "water", "juice", "drink", "bottle", "cup", "mug", "glass", "water jug", "jar", "kettle"],
            indonesianDescription: "drinks and vessels: minum, menuang, mengisi, membawa, menyajikan, atau menaruh",
            englishDescription: "drinks and vessels: drink, pour, fill, carry, serve, or place"
        ),
        KeywordActionPattern(
            labels: ["book", "document", "notebook", "paper", "magazine", "pen", "pencil", "folder"],
            indonesianDescription: "reading and writing materials: membaca, membuka, menulis, memeriksa, membawa, atau meletakkan",
            englishDescription: "reading and writing materials: read, open, write, check, carry, or place"
        ),
        KeywordActionPattern(
            labels: ["laptop", "computer", "keyboard", "monitor", "phone", "tablet", "device", "consumer electronics", "cord", "charger"],
            indonesianDescription: "devices and accessories: menggunakan, menyalakan, mengisi daya, mengetik, memeriksa, membawa, atau menyambungkan",
            englishDescription: "devices and accessories: use, turn on, charge, type, check, carry, or connect"
        ),
        KeywordActionPattern(
            labels: ["bag", "backpack", "wallet", "key", "clothing", "shoe", "hat", "umbrella"],
            indonesianDescription: "personal items: memakai, membawa, membuka, memasukkan, mengambil, memilih, atau menaruh",
            englishDescription: "personal items: wear, carry, open, pack, take out, choose, or place"
        ),
        KeywordActionPattern(
            labels: ["cat", "dog", "animal", "bird", "pet"],
            indonesianDescription: "pets: melihat, merawat, memberi makan, bermain, memanggil, atau duduk dekat",
            englishDescription: "pets: watch, care for, feed, play with, call, or sit near"
        ),
        KeywordActionPattern(
            labels: ["plant", "flower", "tree", "vase"],
            indonesianDescription: "plants and flowers: melihat, merawat, menyiram, membawa, menaruh, atau memindahkan",
            englishDescription: "plants and flowers: look at, care for, water, carry, place, or move"
        ),
        KeywordActionPattern(
            labels: ["car", "motor scooter", "motorcycle", "bicycle", "bike", "vehicle", "bus", "train"],
            indonesianDescription: "transport: naik, mengendarai, parkir, menunggu, berangkat, tiba, atau memeriksa",
            englishDescription: "transport: ride, drive, park, wait, leave, arrive, or check"
        ),
        KeywordActionPattern(
            labels: ["person", "people", "man", "woman", "child"],
            indonesianDescription: "people: berbicara, bertemu, membantu, memberi, menerima, berjalan, atau menunggu",
            englishDescription: "people: talk, meet, help, give, receive, walk, or wait"
        ),
        KeywordActionPattern(
            labels: ["tableware", "utensil", "container", "box", "carton", "basket", "furniture", "chair", "table", "desk"],
            indonesianDescription: "household objects: memakai, mengambil, menaruh, memindahkan, membagikan, menyimpan, atau merapikan",
            englishDescription: "household objects: use, take, place, move, share, store, or tidy"
        ),
    ]

    private struct KeywordActionPattern {
        let labels: Set<String>
        let indonesianDescription: String
        let englishDescription: String

        init(labels: [String], indonesianDescription: String, englishDescription: String) {
            self.labels = Set(labels)
            self.indonesianDescription = indonesianDescription
            self.englishDescription = englishDescription
        }

        func matches(_ foregroundLabels: Set<String>) -> Bool {
            !labels.isDisjoint(with: foregroundLabels)
        }
    }

    private static func situationGuidance(for situation: LessonSituation) -> String {
        switch situation {
        case .home, .friendsHome:
            "The selected home situation is background context, not an action instruction. Use a broad daily-life vocabulary repertoire when current-scene evidence supports it: eating, drinking, serving, using or carrying personal items and tools, reading, watching, listening, resting, talking, visiting, caring for pets or plants, arriving or leaving, giving or receiving, looking for, placing, or moving objects. Household maintenance is one equally valid option, not the default. Select only a perspective grounded in the current image_keywords, relations, or user note."
        default:
            "The selected situation is background context, not an action instruction. Do not invent an activity merely from the place; choose the main action or observation from image_keywords, relations, or the user note."
        }
    }

    private static func expressionVariationGuidance(for expressions: [String]) -> String {
        let normalizedExpressions = expressions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedExpressions.isEmpty else {
            return "Current-scene evidence takes priority over artificial variety. Do not avoid a natural expression solely to make the lesson different."
        }

        let terms = normalizedExpressions.map { "`\($0)`" }.joined(separator: ", ")
        return "Recent comparable lessons repeatedly used these target-language expressions: \(terms). This is a soft diversity preference, not a ban: prefer a different, equally natural action or observation when current-scene evidence supports it. You may still use one of these expressions when it is the clearest description of this scene."
    }

    private static func levelInstructions(
        for level: LanguageLevel,
        language: LessonLanguage
    ) -> String {
        switch (language, level) {
        case (.indonesian, .beginner):
            """
            - Make the main sentence beginner-oriented: aim for 7 Indonesian words or fewer, one clause, and no comma.
            - Follow the selected lesson_pattern with a basic, practical Indonesian pattern. Prefer direct forms such as "Saya ...", "Ini ...", "Saya makan ...", or "Saya melihat ..."; use "Saya sedang ..." only for current_action.
            - Do not add an extra connector or a second clause merely to make the sentence sound advanced.
            - Vocabulary must be 3 to 5 basic words from the main sentence.
            - Grammar note must be longer and very easy Japanese, explaining one basic pattern only.
            - Conversation must be 2 short lines.
            """
        case (.indonesian, .intermediate):
            """
            - Make the main sentence intermediate-oriented: aim for 10 to 15 Indonesian words.
            - Follow the selected lesson_pattern instead of defaulting to a familiar connector. Use only one primary connector, time expression, or tense pattern unless short coordination is required by the selected pattern.
            - Vocabulary must be 5 to 7 items, including the selected pattern when it appears in the sentence.
            - Grammar note should explain the selected connector, tense, or phrase pattern in concise Japanese.
            - Conversation should be 3 to 4 lines and sound like a simple real exchange.
            """
        case (.indonesian, .advanced):
            """
            - Make the main sentence advanced-oriented: aim for 20 to 40 Indonesian words.
            - Aim for 24 to 30 words, and count them before returning the JSON.
            - Follow the selected lesson_pattern. Use multiple clauses only when that pattern and the scene support them; do not add a familiar connector as filler.
            - Use a natural adult expression, not a textbook translation.
            - Vary time, intent, condition, contrast, addition, and discourse choices across lessons rather than repeatedly using the same sentence opening.
            - Vocabulary must be 7 to 10 useful words or chunks, including at least one phrase-level item.
            - Include scene nouns, actions, connectors, and natural chunks from the main sentence; do not return only object nouns.
            - Grammar note should explain nuance, register, or natural usage in Japanese.
            - Conversation should be 3 to 4 lines with a more natural tone than beginner level.
            """
        case (.english, .beginner):
            """
            - Make the main sentence beginner-oriented: aim for 7 English words or fewer, one clause, and no comma.
            - Follow the selected lesson_pattern with a basic, practical English pattern. Prefer direct forms such as "I ...", "This is ...", "I use ...", or "I see ..."; use a progressive form only for current_action.
            - Do not add an extra connector or a second clause merely to make the sentence sound advanced.
            - Vocabulary must be 3 to 5 basic words from the main sentence.
            - Grammar note must be longer and very easy Japanese, explaining one basic pattern only.
            - Conversation must be 2 short lines.
            """
        case (.english, .intermediate):
            """
            - Make the main sentence intermediate-oriented: aim for 10 to 15 English words.
            - Follow the selected lesson_pattern instead of defaulting to a familiar connector. Use only one primary connector, time expression, or tense pattern unless short coordination is required by the selected pattern.
            - Vocabulary must be 5 to 7 items, including the selected pattern when it appears in the sentence.
            - Grammar note should explain the selected connector, tense, or phrase pattern in concise Japanese.
            - Conversation should be 3 to 4 lines and sound like a simple real exchange.
            """
        case (.english, .advanced):
            """
            - Make the main sentence advanced-oriented: aim for 20 to 40 English words.
            - Aim for 24 to 30 words, and count them before returning the JSON.
            - Follow the selected lesson_pattern. Use multiple clauses only when that pattern and the scene support them; do not add a familiar connector as filler.
            - Use a natural adult expression, not a textbook translation.
            - Vary time, intent, condition, contrast, addition, and discourse choices across lessons rather than repeatedly using the same sentence opening.
            - Vocabulary must be 7 to 10 useful words or chunks, including at least one phrase-level item.
            - Include scene nouns, actions, connectors, and natural chunks from the main sentence; do not return only object nouns.
            - Grammar note should explain nuance, register, or natural usage in Japanese.
            - Conversation should be 3 to 4 lines with a more natural tone than beginner level.
            """
        }
    }
}

public struct OpenAIScenePayload: Codable, Equatable, Sendable {
    public var time: String
    public var day: String
    public var imageKeywords: [ImageKeyword]
    public var relations: [String]
    public var userNote: String
    public var languageLevel: String
    public var lessonLanguage: String
    public var situation: String
    public var lessonPattern: String
    public var recentlyRepeatedExpressions: [String]

    public init(context: SceneContext) {
        time = context.timeText
        day = context.dayText
        imageKeywords = context.imageKeywords.sortedForPrompt()
        relations = context.imageRelations
        userNote = context.userNote
        languageLevel = context.languageLevel.rawValue
        lessonLanguage = context.lessonLanguage.rawValue
        situation = context.lessonSituation.promptValue
        lessonPattern = context.lessonGrammarFocus.rawValue
        recentlyRepeatedExpressions = context.recentlyRepeatedExpressions
    }

    enum CodingKeys: String, CodingKey {
        case time
        case day
        case imageKeywords = "image_keywords"
        case relations
        case userNote = "user_note"
        case languageLevel = "language_level"
        case lessonLanguage = "lesson_language"
        case situation
        case lessonPattern = "lesson_pattern"
        case recentlyRepeatedExpressions = "recently_repeated_expressions"
    }
}

private extension Array where Element == ImageKeyword {
    func sortedForPrompt() -> [ImageKeyword] {
        sorted { lhs, rhs in
            let lhsRank = roleRank(lhs.role)
            let rhsRank = roleRank(rhs.role)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.label < rhs.label
        }
    }

    private func roleRank(_ role: KeywordRole) -> Int {
        switch role {
        case .foreground:
            0
        case .surface:
            1
        case .context:
            2
        }
    }
}
