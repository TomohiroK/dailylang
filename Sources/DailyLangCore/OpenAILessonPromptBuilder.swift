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
        let levelInstructions = Self.levelInstructions(for: context.languageLevel)

        return OpenAILessonPrompt(
            instructions: """
            You are an Indonesian language tutor for a Japanese learner.
            Generate a compact DUO-style Indonesian lesson based on the user's real-life scene.

            Requirements:
            - Use natural Indonesian.
            - Keep the main sentence practical.
            - `main_sentence_jp` must be a Japanese translation, not Indonesian text and not a copy of `main_sentence_id`.
            - Extract 4 to 8 useful vocabulary items.
            - Every vocabulary `id` must be an exact word or contiguous phrase copied from `main_sentence_id`.
            - Do not put image keyword labels, inferred objects, or related words in vocabulary unless the same Indonesian text appears in `main_sentence_id`.
            - Explain grammar briefly in Japanese.
            - Create a 2 to 4 line short conversation that could happen in this scene.
            - Create exactly 3 similar expressions.
            - Do not mention uncertain visual details as facts.
            - The photo itself is not provided.
            - Use only the supplied image_keywords, time, location label, and user note as evidence.
            - image_keywords are on-device Vision/Core ML object-detection and image-classification labels with confidence scores and counts.
            - If image_keywords contain concrete labels, the main sentence must include at least one concrete object or action naturally based on those labels.
            - Translate image keyword evidence into natural Indonesian when needed, for example document -> dokumen, digital clock -> jam, cup -> cangkir, banana -> pisang.
            - Do not force object keywords into location phrases. Do not write phrases like "di keyboard" or "di laptop" unless the keyword is truly a place.
            - Prefer natural object actions, for example membaca dokumen, menggunakan keyboard, melihat jam, makan pisang, minum susu.
            - Generic sentences such as "Saya sedang belajar." or "Saya sedang bekerja." are invalid when concrete image_keywords are available.
            - Do not invent objects, places, foods, reports, meetings, or actions unless those details appear in image_keywords or user note.
            - If image_keywords are empty or vague, use a general daily-life sentence.
            - In this schema, fields named `main_sentence_id` or `id` must contain Indonesian text, not numeric identifiers.
            - `main_sentence_id` must be one complete Indonesian sentence.
            - `main_sentence_id` must support at least 4 vocabulary items copied from that sentence.
            - Vocabulary `id`, conversation `id`, and similar expression `id` must also be Indonesian words or sentences.
            - Return only JSON that matches the requested schema.

            Current learner level: \(context.languageLevel.rawValue)
            Level contract:
            \(levelInstructions)
            """,
            sceneJSON: sceneJSON
        )
    }

    private static func levelInstructions(for level: LanguageLevel) -> String {
        switch level {
        case .beginner:
            """
            - Make the main sentence beginner-only: 6 to 10 Indonesian words, one clause, no comma.
            - Prefer basic patterns such as "Saya sedang ...", "Ini ...", "Saya makan ...", or "Saya melihat ...".
            - Do not use connectors such as karena, sebelum, setelah, supaya, sementara, walaupun, agar, or kalau.
            - Vocabulary should focus on 4 to 5 basic words from the main sentence.
            - Grammar note must be longer and very easy Japanese, explaining one basic pattern only.
            - Conversation must be 2 short lines.
            """
        case .intermediate:
            """
            - Make the main sentence intermediate: 10 to 16 Indonesian words.
            - Include one natural connector if it fits the scene: sambil, karena, sebelum, setelah, or untuk.
            - Vocabulary should include 5 to 7 items, including the connector if used.
            - Grammar note should explain the connector or phrase pattern in concise Japanese.
            - Conversation should be 3 to 4 lines and sound like a simple real exchange.
            """
        case .advanced:
            """
            - Make the main sentence advanced but still compact: 14 to 22 Indonesian words.
            - Use a natural adult expression, not a textbook translation.
            - Include one pragmatic or nuanced expression if it fits: sepertinya, dulu, nanti, sekalian, supaya, sementara, or kalau sempat.
            - Vocabulary should include 6 to 8 useful words or chunks, including at least one phrase-level item.
            - Grammar note should explain nuance, register, or natural usage in Japanese.
            - Conversation should be 3 to 4 lines with a more natural tone than beginner level.
            """
        }
    }
}

public struct OpenAIScenePayload: Codable, Equatable, Sendable {
    public var time: String
    public var day: String
    public var locationLabel: String
    public var imageKeywords: [ImageKeyword]
    public var userNote: String
    public var languageLevel: String

    public init(context: SceneContext) {
        time = context.timeText
        day = context.dayText
        locationLabel = context.locationLabel.rawValue
        imageKeywords = context.imageKeywords
        userNote = context.userNote
        languageLevel = context.languageLevel.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case time
        case day
        case locationLabel = "location_label"
        case imageKeywords = "image_keywords"
        case userNote = "user_note"
        case languageLevel = "language_level"
    }
}
