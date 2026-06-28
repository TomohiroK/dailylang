import Testing
@testable import DailyLangCore

@Suite("OpenAI lesson prompt")
struct OpenAILessonPromptTests {
    @Test("OpenAI prompt uses image keywords without image payloads")
    func promptContainsStructuredImageKeywordsOnly() throws {
        let context = SceneContext(
            timeText: "09:15",
            dayText: "Tuesday",
            locationLabel: .restaurant,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.91),
                ImageKeyword(label: "milk", confidence: 0.83),
                ImageKeyword(label: "cup", confidence: 0.72),
                ImageKeyword(label: "basket", confidence: 0.69),
            ],
            userNote: "quick breakfast",
            languageLevel: .intermediate
        )

        let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)

        #expect(prompt.instructions.contains("Do not mention uncertain visual details as facts."))
        #expect(prompt.instructions.contains("image_keywords"))
        #expect(prompt.instructions.contains("The photo itself is not provided."))
        #expect(prompt.instructions.contains("main_sentence_id` must be one complete Indonesian sentence"))
        #expect(prompt.instructions.contains("not numeric identifiers"))
        #expect(prompt.sceneJSON.contains("\"location_label\":\"restaurant\""))
        #expect(prompt.sceneJSON.contains("\"image_keywords\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"banana\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"milk\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"cup\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"basket\""))
        #expect(prompt.sceneJSON.contains("\"count\":1"))
        #expect(!prompt.sceneJSON.localizedCaseInsensitiveContains("\"tags\""))
        #expect(!prompt.instructions.localizedCaseInsensitiveContains("Saya sedang mengecek laporan"))
        #expect(!prompt.sceneJSON.localizedCaseInsensitiveContains("base64"))
        #expect(!prompt.sceneJSON.localizedCaseInsensitiveContains("image_url"))
    }

    @Test("OpenAI prompt has different contracts for beginner and advanced")
    func promptContainsLevelSpecificContracts() throws {
        let beginnerContext = SceneContext(
            timeText: "10:00",
            dayText: "Monday",
            locationLabel: .unknown,
            imageKeywords: [ImageKeyword(label: "MacBook", confidence: 0.91)],
            languageLevel: .beginner
        )
        let advancedContext = SceneContext(
            timeText: "10:00",
            dayText: "Monday",
            locationLabel: .unknown,
            imageKeywords: [ImageKeyword(label: "MacBook", confidence: 0.91)],
            languageLevel: .advanced
        )

        let beginnerPrompt = try OpenAILessonPromptBuilder().buildPrompt(from: beginnerContext)
        let advancedPrompt = try OpenAILessonPromptBuilder().buildPrompt(from: advancedContext)

        #expect(beginnerPrompt.instructions.contains("Current learner level: beginner"))
        #expect(beginnerPrompt.instructions.contains("6 to 10 Indonesian words"))
        #expect(beginnerPrompt.instructions.contains("Do not use connectors"))
        #expect(advancedPrompt.instructions.contains("Current learner level: advanced"))
        #expect(advancedPrompt.instructions.contains("14 to 22 Indonesian words"))
        #expect(advancedPrompt.instructions.contains("pragmatic or nuanced expression"))
        #expect(beginnerPrompt.instructions != advancedPrompt.instructions)
    }

    @Test("OpenAI payload rejects numeric ids from schema misunderstanding")
    func generatedPayloadRejectsNumericIdentifiers() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "1",
            mainSentenceJP: "私は会社でコーヒーを飲んでいます。",
            vocabulary: [
                .init(id: "1", jp: "私"),
                .init(id: "2", jp: "会社"),
                .init(id: "3", jp: "コーヒー"),
            ],
            grammarNote: "sedang は進行中の動作を表します。",
            conversation: [
                .init(speaker: "A", id: "1", jp: "何をしていますか？"),
                .init(speaker: "B", id: "2", jp: "仕事をしています。"),
            ],
            similarExpressions: [
                .init(id: "1", jp: "仕事をしています。"),
                .init(id: "2", jp: "コーヒーを飲んでいます。"),
                .init(id: "3", jp: "会社にいます。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.invalidContent) {
            try payload.lesson(source: .openAI)
        }
    }

    @Test("OpenAI payload accepts Indonesian lesson text")
    func generatedPayloadCreatesOpenAILesson() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya sedang minum kopi sambil bekerja di kantor.",
            mainSentenceJP: "私は会社で働きながらコーヒーを飲んでいます。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "sedang", jp: "〜している"),
                .init(id: "kopi", jp: "コーヒー"),
                .init(id: "bekerja", jp: "働く"),
                .init(id: "kantor", jp: "会社"),
            ],
            grammarNote: "sedang + 動詞 = 今〜している。sambil + 動詞 = 〜しながら。",
            conversation: [
                .init(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか？"),
                .init(speaker: "B", id: "Saya sedang bekerja.", jp: "仕事をしています。"),
            ],
            similarExpressions: [
                .init(id: "Saya sedang bekerja.", jp: "私は仕事をしています。"),
                .init(id: "Saya minum kopi.", jp: "私はコーヒーを飲んでいます。"),
                .init(id: "Saya ada di kantor.", jp: "私は会社にいます。"),
            ]
        )

        let lesson = try payload.lesson(source: .openAI)

        #expect(lesson.source == .openAI)
        #expect(lesson.mainSentenceID.contains("kopi"))
        #expect(lesson.vocabulary.count == 5)
    }
}
