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
        #expect(prompt.instructions.contains("must be a Japanese translation"))
        #expect(prompt.instructions.contains("main_sentence_id` must be one complete Indonesian sentence"))
        #expect(prompt.instructions.contains("Every vocabulary `id` must be an exact word or contiguous phrase copied from `main_sentence_id`"))
        #expect(prompt.instructions.contains("main sentence must include at least one concrete object or action"))
        #expect(prompt.instructions.contains("Generic sentences such as \"Saya sedang belajar.\""))
        #expect(prompt.instructions.contains("Do not force object keywords into location phrases"))
        #expect(prompt.instructions.contains("menggunakan keyboard"))
        #expect(prompt.instructions.contains("support at least 4 vocabulary items"))
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

    @Test("OpenAI payload rejects missing Japanese translation")
    func generatedPayloadRejectsNonJapaneseTranslation() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Sepertinya kucing itu santai di rumah dekat meja dan botol.",
            mainSentenceJP: "Sepertinya kucing itu santai di rumah dekat meja dan botol.",
            vocabulary: [
                .init(id: "sepertinya", jp: "どうやら"),
                .init(id: "kucing", jp: "猫"),
                .init(id: "rumah", jp: "家"),
                .init(id: "meja", jp: "机"),
                .init(id: "botol", jp: "ボトル"),
            ],
            grammarNote: "dekat + 名詞 = 〜の近く。",
            conversation: [
                .init(speaker: "A", id: "Kucing itu di mana?", jp: "その猫はどこにいますか？"),
                .init(speaker: "B", id: "Kucing itu di rumah.", jp: "その猫は家にいます。"),
            ],
            similarExpressions: [
                .init(id: "Kucing itu santai.", jp: "その猫はくつろいでいます。"),
                .init(id: "Kucing itu dekat meja.", jp: "その猫は机の近くにいます。"),
                .init(id: "Ada botol di meja.", jp: "机にボトルがあります。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.invalidContent) {
            try payload.lesson(source: .openAI)
        }
    }

    @Test("OpenAI payload removes vocabulary not used in the main sentence")
    func generatedPayloadKeepsOnlyVocabularyUsedInMainSentence() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Sepertinya sore ini masih enak buat santai di luar rumah sambil lihat motor-motor lewat.",
            mainSentenceJP: "どうやら夕方は外でのんびりしながらバイクを見るのにまだよさそうです。",
            vocabulary: [
                .init(id: "motorbike", jp: "バイク、オートバイ"),
                .init(id: "luar rumah", jp: "外、屋外"),
                .init(id: "langit biru", jp: "青空"),
                .init(id: "gerbang lengkung", jp: "門、アーチ状の入口"),
                .init(id: "depan bangunan", jp: "建物の前面、店先"),
                .init(id: "sepertinya", jp: "たぶん、どうやら"),
                .init(id: "sambil", jp: "〜しながら"),
                .init(id: "lihat", jp: "見る"),
                .init(id: "sekalian", jp: "ついでに、合わせて"),
            ],
            grammarNote: "「Sepertinya」は推量を表し、「sambil」は同時進行を表します。",
            conversation: [
                .init(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか？"),
                .init(speaker: "B", id: "Saya sedang santai di luar rumah.", jp: "外でのんびりしています。"),
            ],
            similarExpressions: [
                .init(id: "Saya sedang santai di luar rumah.", jp: "私は外でのんびりしています。"),
                .init(id: "Saya melihat motor-motor lewat.", jp: "私はバイクが通るのを見ています。"),
                .init(id: "Sore ini enak untuk santai.", jp: "今日の夕方はのんびりするのにいいです。"),
            ]
        )

        let lesson = try payload.lesson(source: .openAI)

        #expect(lesson.vocabulary.map(\.id) == ["luar rumah", "sepertinya", "sambil", "lihat"])
    }

    @Test("OpenAI payload rejects overly generic sparse lessons")
    func generatedPayloadRejectsSparseGenericLesson() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya sedang belajar.",
            mainSentenceJP: "私は勉強しています。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "sedang", jp: "〜している"),
                .init(id: "belajar", jp: "勉強する"),
                .init(id: "dokumen", jp: "書類"),
            ],
            grammarNote: "sedang + 動詞 = 今〜している。",
            conversation: [
                .init(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか？"),
                .init(speaker: "B", id: "Saya sedang belajar.", jp: "勉強しています。"),
            ],
            similarExpressions: [
                .init(id: "Saya belajar di rumah.", jp: "私は家で勉強します。"),
                .init(id: "Saya sedang membaca.", jp: "私は読んでいます。"),
                .init(id: "Saya mau belajar.", jp: "私は勉強したいです。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.invalidContent) {
            try payload.lesson(source: .openAI)
        }
    }

    @Test("OpenAI payload rejects vocabulary that is entirely outside the main sentence")
    func generatedPayloadRejectsVocabularyWhenNoItemsAreUsedInMainSentence() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya sedang makan pisang di rumah.",
            mainSentenceJP: "私は家でバナナを食べています。",
            vocabulary: [
                .init(id: "motorbike", jp: "バイク"),
                .init(id: "langit biru", jp: "青空"),
                .init(id: "gerbang lengkung", jp: "門"),
            ],
            grammarNote: "sedang + 動詞 = 今〜している。",
            conversation: [
                .init(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか？"),
                .init(speaker: "B", id: "Saya sedang makan.", jp: "食べています。"),
            ],
            similarExpressions: [
                .init(id: "Saya makan pisang.", jp: "私はバナナを食べます。"),
                .init(id: "Saya ada di rumah.", jp: "私は家にいます。"),
                .init(id: "Pisang ini enak.", jp: "このバナナはおいしいです。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.invalidContent) {
            try payload.lesson(source: .openAI)
        }
    }
}
