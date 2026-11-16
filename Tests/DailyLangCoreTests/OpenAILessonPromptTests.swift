import Foundation
import Testing
@testable import DailyLangCore

@Suite("OpenAI lesson prompt")
struct OpenAILessonPromptTests {
    @Test("Recent vocabulary reaches generation without becoming photo evidence")
    func recentVocabularyRoundTrip() throws {
        for language in LessonLanguage.allCases {
            let context = SceneContext(timeText: "17:31", dayText: "Monday", locationLabel: .unknown,
                imageKeywords: [ImageKeyword(label: "laptop", confidence: 0.9)],
                languageLevel: .advanced, lessonLanguage: language, lessonSituation: .office,
                recentVocabularyTerms: ["botol", "cangkir", "memeriksa"])
            let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)
            let payload = try JSONDecoder().decode(OpenAIScenePayload.self, from: Data(prompt.sceneJSON.utf8))
            #expect(payload.recentVocabularyTerms == context.recentVocabularyTerms)
            #expect(payload.imageKeywords == context.imageKeywords)
            #expect(prompt.instructions.contains("Treat these as familiar, not new teaching targets"))
            #expect(prompt.instructions.contains("Audit the Japanese translation clause by clause"))
            let encoded = try JSONEncoder().encode(context)
            #expect(try JSONDecoder().decode(SceneContext.self, from: encoded) == context)
            var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            old.removeValue(forKey: "recentVocabularyTerms")
            let legacy = try JSONDecoder().decode(SceneContext.self, from: JSONSerialization.data(withJSONObject: old))
            #expect(legacy.recentVocabularyTerms.isEmpty)
        }
    }

    @Test("Situation associations enrich both languages without changing photo evidence",
          arguments: LessonLanguage.allCases, LanguageLevel.allCases)
    func situationAssociations(language: LessonLanguage, level: LanguageLevel) throws {
        for situation in LessonSituation.selectableCases {
            let context = SceneContext(
                timeText: "12:00", dayText: "Monday", locationLabel: .unknown,
                imageKeywords: [ImageKeyword(label: "notebook", confidence: 0.9)],
                languageLevel: level, lessonLanguage: language, lessonSituation: situation
            )
            let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)
            let payload = try JSONDecoder().decode(OpenAIScenePayload.self, from: Data(prompt.sceneJSON.utf8))
            #expect(payload.imageKeywords == context.imageKeywords)
            #expect(payload.situation == situation.promptValue)
            #expect(prompt.instructions.contains("Associated action candidates for the selected situation:"))
            #expect(prompt.instructions.contains("not mandatory keywords or claims about the image"))
            #expect(prompt.instructions.contains("never describe it as happening or completed without evidence"))
            switch situation {
            case .office: #expect(prompt.instructions.contains("work, attend a meeting"))
            case .shop: #expect(prompt.instructions.contains("buy, browse, look around"))
            case .restaurantCafe: #expect(prompt.instructions.contains("eat, drink, order"))
            case .school: #expect(prompt.instructions.contains("study, take notes"))
            default: break
            }
        }
    }

    @Test("Every vocabulary perspective preserves language, level, grounding and privacy",
          arguments: LessonLanguage.allCases, LanguageLevel.allCases)
    func vocabularyPerspectivesRespectContracts(language: LessonLanguage, level: LanguageLevel) throws {
        for focus in LessonVocabularyFocus.allCases {
            let context = SceneContext(
                timeText: "12:00", dayText: "Monday", locationLabel: .unknown,
                imageKeywords: [ImageKeyword(label: "cup", confidence: 0.9)],
                languageLevel: level, lessonLanguage: language,
                lessonSituation: .shop, lessonVocabularyFocus: focus
            )
            let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)
            let data = Data(prompt.sceneJSON.utf8)
            let payload = try JSONDecoder().decode(OpenAIScenePayload.self, from: data)
            #expect(payload.vocabularyFocus == focus.rawValue)
            #expect(payload.lessonLanguage == language.rawValue)
            #expect(payload.languageLevel == level.rawValue)
            #expect(payload.imageKeywords == context.imageKeywords)
            #expect(prompt.instructions.contains(focus.promptInstruction))
            #expect(prompt.instructions.contains("Rank them by current-scene grounding, learner-level fit, everyday usefulness, then diversity"))
            #expect(prompt.instructions.contains("never claim they happened in the photo"))
            #expect(prompt.instructions.contains("Keep the Japanese translation faithful to that modality"))
            #expect(prompt.instructions.contains("Every vocabulary `id` must be an exact word or contiguous phrase"))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(json.keys) == Set([
                "time", "day", "image_keywords", "relations", "user_note", "language_level",
                "lesson_language", "situation", "lesson_pattern", "vocabulary_focus",
                "recently_repeated_expressions", "recent_vocabulary_terms",
            ]))
        }
    }

    @Test("Old scene contexts decode and new perspectives round trip")
    func vocabularyPerspectiveCompatibility() throws {
        let original = SceneContext(
            timeText: "12:00", dayText: "Monday", locationLabel: .unknown,
            imageKeywords: [], languageLevel: .beginner, lessonVocabularyFocus: .choice
        )
        let encoded = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SceneContext.self, from: encoded) == original)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "lessonVocabularyFocus")
        let decoded = try JSONDecoder().decode(SceneContext.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.lessonVocabularyFocus == .objectDetails)
        #expect(decoded.lessonLanguage == .indonesian)
    }

    @Test("Sparse and unfamiliar evidence does not force a visual category")
    func vocabularyPerspectiveHandlesSparseEvidence() throws {
        for keywords in [[], [ImageKeyword(label: "unfamiliar object", confidence: 0.3)]] {
            let context = SceneContext(
                timeText: "12:00", dayText: "Monday", locationLabel: .unknown,
                imageKeywords: keywords, languageLevel: .beginner,
                lessonVocabularyFocus: .spatialRelations
            )
            let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)
            #expect(prompt.instructions.contains("If no relation is supplied, use another supported perspective"))
            #expect(prompt.instructions.contains("If image_keywords are empty or vague, use a general daily-life sentence"))
            #expect(prompt.instructions.contains("For an unfamiliar object"))
        }
    }

    @Test("All levels permit natural keyword selection without quotas")
    func keywordSelectionRemainsFlexible() throws {
        for language in LessonLanguage.allCases {
            for level in LanguageLevel.allCases {
                let context = SceneContext(timeText: "12:00", dayText: "Monday", locationLabel: .unknown,
                    imageKeywords: [ImageKeyword(label: "banana", confidence: 0.9)],
                    languageLevel: level, lessonLanguage: language)
                let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)
                #expect(prompt.instructions.contains("there is no minimum object count and unused keywords are acceptable"))
                #expect(!prompt.instructions.contains("aiming for the upper end"))
                #expect(prompt.instructions.contains("Multiple actions or related topics are welcome"))
                #expect(prompt.instructions.contains("A natural, otherwise valid sentence outside the target is acceptable"))
                #expect(prompt.instructions.contains("Choose useful nouns, verbs, expressions and grammar chunks"))
            }
        }
    }

    @Test("Overlapping object labels are not separate objects")
    func overlappingLabelsUseSpecificObjectNames() throws {
        for language in LessonLanguage.allCases {
            let context = SceneContext(timeText: "12:00", dayText: "Monday", locationLabel: .unknown,
                imageKeywords: ["laptop", "computer", "phone"].map { ImageKeyword(label: $0, confidence: 0.9) },
                languageLevel: .advanced, lessonLanguage: language)
            let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)
            #expect(prompt.instructions.contains("Prefer the most specific supported name"))
            #expect(prompt.instructions.contains("Sharing a category alone does not merge genuinely distinct objects"))
            #expect(prompt.instructions.contains("main sentence, conversation, similar expressions, and vocabulary"))
            let payload = try JSONDecoder().decode(OpenAIScenePayload.self, from: Data(prompt.sceneJSON.utf8))
            #expect(payload.imageKeywords.count == 3)
        }
    }

    @Test("OpenAI prompt uses image keywords without image payloads")
    func promptContainsStructuredImageKeywordsOnly() throws {
        let context = SceneContext(
            timeText: "09:15",
            dayText: "Tuesday",
            locationLabel: .restaurant,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.91, role: .foreground),
                ImageKeyword(label: "dining table", confidence: 0.93, role: .surface),
                ImageKeyword(label: "milk", confidence: 0.83, role: .foreground),
                ImageKeyword(label: "cup", confidence: 0.72),
                ImageKeyword(label: "basket", confidence: 0.69),
                ImageKeyword(label: "bananna", confidence: 0.5, role: .foreground, source: .manual),
            ],
            imageRelations: ["banana on dining table", "cup on dining table"],
            userNote: "quick breakfast",
            languageLevel: .intermediate
        )

        let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)

        #expect(prompt.instructions.contains("Do not mention uncertain visual details as facts."))
        #expect(prompt.instructions.contains("image_keywords"))
        #expect(prompt.instructions.contains("The photo itself is not provided."))
        #expect(prompt.instructions.contains("must be a Japanese translation"))
        #expect(prompt.instructions.contains("Do not use Thai, Lao, Khmer, or Myanmar script"))
        #expect(prompt.instructions.contains("Never copy or romanize the Indonesian vocabulary `id`"))
        #expect(prompt.instructions.contains("main_sentence_id` must be one complete Indonesian sentence"))
        #expect(prompt.instructions.contains("Every vocabulary `id` must be an exact word or contiguous phrase copied from `main_sentence_id`"))
        #expect(prompt.instructions.contains("there is no minimum object count"))
        #expect(prompt.instructions.contains("surface"))
        #expect(prompt.instructions.contains("source \"manual\""))
        #expect(prompt.instructions.contains("used_keywords"))
        #expect(prompt.instructions.contains("Generic sentences such as \"Saya sedang belajar.\""))
        #expect(prompt.instructions.contains("Do not force object keywords into location phrases"))
        #expect(prompt.instructions.contains("For each foreground keyword, consider multiple distinct, natural action, relation, or social patterns"))
        #expect(prompt.instructions.contains("food: makan, memilih, membawa, menyiapkan, menyajikan, atau menaruh"))
        #expect(prompt.instructions.contains("drinks and vessels: minum, menuang, mengisi, membawa, menyajikan, atau menaruh"))
        #expect(prompt.instructions.contains("5 to 7 vocabulary items"))
        #expect(prompt.instructions.contains("not numeric identifiers"))
        #expect(prompt.sceneJSON.contains("\"time\":\"09:15\""))
        #expect(prompt.sceneJSON.contains("\"day\":\"Tuesday\""))
        #expect(prompt.sceneJSON.contains("\"image_keywords\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"banana\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"milk\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"cup\""))
        #expect(prompt.sceneJSON.contains("\"label\":\"basket\""))
        #expect(prompt.sceneJSON.contains("\"count\":1"))
        #expect(prompt.sceneJSON.contains("\"role\":\"foreground\""))
        #expect(prompt.sceneJSON.contains("\"role\":\"surface\""))
        #expect(prompt.sceneJSON.contains("\"source\":\"manual\""))
        #expect(prompt.sceneJSON.contains("\"relations\":[\"banana on dining table\",\"cup on dining table\"]"))
        #expect(prompt.sceneJSON.contains("\"lesson_pattern\":\"simple_statement\""))
        #expect(!prompt.sceneJSON.contains("\"location_label\""))
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
        #expect(beginnerPrompt.instructions.contains("7 Indonesian words or fewer"))
        #expect(beginnerPrompt.instructions.contains("3 to 5 vocabulary items"))
        #expect(beginnerPrompt.instructions.contains("Use a direct present statement"))
        #expect(advancedPrompt.instructions.contains("Current learner level: advanced"))
        #expect(advancedPrompt.instructions.contains("20 to 40 Indonesian words"))
        #expect(advancedPrompt.instructions.contains("Twenty or more words are welcome"))
        #expect(advancedPrompt.instructions.contains("without rewriting just to reach a target"))
        #expect(advancedPrompt.instructions.contains("7 to 10 vocabulary items"))
        #expect(advancedPrompt.instructions.contains("Selected lesson_pattern instruction"))
        #expect(beginnerPrompt.instructions != advancedPrompt.instructions)
    }

    @Test("Prompt grammar focus prevents sambil and sepertinya from becoming defaults")
    func promptCarriesGrammarFocusWithTargetedConnectorRules() throws {
        let additionContext = SceneContext(
            timeText: "12:00",
            dayText: "Friday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.96),
                ImageKeyword(label: "milk", confidence: 0.93),
            ],
            languageLevel: .intermediate,
            lessonGrammarFocus: .addition
        )
        let parallelContext = SceneContext(
            timeText: "12:00",
            dayText: "Friday",
            locationLabel: .unknown,
            imageKeywords: [ImageKeyword(label: "banana", confidence: 0.96)],
            languageLevel: .intermediate,
            lessonGrammarFocus: .parallelAction
        )

        let additionPrompt = try OpenAILessonPromptBuilder().buildPrompt(from: additionContext)
        let parallelPrompt = try OpenAILessonPromptBuilder().buildPrompt(from: parallelContext)

        #expect(additionPrompt.sceneJSON.contains("\"lesson_pattern\":\"addition\""))
        #expect(additionPrompt.instructions.contains("bukan hanya ... tetapi juga"))
        #expect(additionPrompt.instructions.contains("allowed only for the `parallel_action`"))
        #expect(parallelPrompt.sceneJSON.contains("\"lesson_pattern\":\"parallel_action\""))
        #expect(parallelPrompt.instructions.contains("Use sambil for two genuinely compatible actions"))
        #expect(!parallelPrompt.instructions.contains("Use sepertinya only to soften"))
    }

    @Test("Home situations use repeated expressions as a soft diversity preference")
    func homeSituationsCarrySoftExpressionDiversityGuidance() throws {
        let homeContext = SceneContext(
            timeText: "18:30",
            dayText: "Wednesday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "bottle", confidence: 0.94, role: .foreground),
                ImageKeyword(label: "cup", confidence: 0.89, role: .foreground),
                ImageKeyword(label: "table", confidence: 0.76, role: .surface),
            ],
            languageLevel: .intermediate,
            lessonSituation: .home,
            recentlyRepeatedExpressions: ["merapikan", "menata"]
        )
        let friendsHomeContext = SceneContext(
            timeText: "18:30",
            dayText: "Wednesday",
            locationLabel: .unknown,
            imageKeywords: homeContext.imageKeywords,
            languageLevel: .intermediate,
            lessonSituation: .friendsHome,
            recentlyRepeatedExpressions: ["merapikan", "menata"]
        )

        let homePrompt = try OpenAILessonPromptBuilder().buildPrompt(from: homeContext)
        let friendsHomePrompt = try OpenAILessonPromptBuilder().buildPrompt(from: friendsHomeContext)

        for prompt in [homePrompt, friendsHomePrompt] {
            #expect(prompt.instructions.contains("background context, not an action instruction"))
            #expect(prompt.instructions.contains("Use a broad daily-life vocabulary repertoire"))
            #expect(prompt.instructions.contains("eating, drinking, serving"))
            #expect(prompt.instructions.contains("resting, talking, visiting"))
            #expect(prompt.instructions.contains("Household maintenance is one equally valid option, not the default"))
            #expect(prompt.instructions.contains("This is a soft diversity preference, not a ban"))
            #expect(prompt.instructions.contains("merapikan"))
            #expect(prompt.instructions.contains("menata"))
            #expect(prompt.instructions.contains("You may still use one of these expressions when it is the clearest description"))
        }
        #expect(homePrompt.sceneJSON.contains("\"situation\":\"at home\""))
        #expect(friendsHomePrompt.sceneJSON.contains("\"situation\":\"at a friend's home\""))
        #expect(homePrompt.sceneJSON.contains("\"recently_repeated_expressions\":[\"merapikan\",\"menata\"]"))
    }

    @Test("Grammar focus choices include non-progressive time and connector patterns")
    func grammarFocusChoicesCoverRequestedPatterns() {
        let intermediate = LessonGrammarFocus.choices(for: .intermediate)
        let advanced = LessonGrammarFocus.choices(for: .advanced)

        #expect(intermediate.contains(.completedAction))
        #expect(intermediate.contains(.futurePlan))
        #expect(intermediate.contains(.addition))
        #expect(intermediate.contains(.alternative))
        #expect(intermediate.contains(.contrast))
        #expect(intermediate.contains(.condition))
        #expect(intermediate.contains(.parallelAction))
        #expect(!intermediate.contains(.uncertainty))
        #expect(advanced.contains(.uncertainty))
    }

    @Test("Indonesian word count uses level ranges")
    func indonesianWordCountUsesLevelRanges() {
        #expect(LessonTextValidation.indonesianWordCount("Saya makan pisang dengan susu.") == 5)
        #expect(LessonTextValidation.indonesianWordCount("Saya melihat motor-motor lewat di luar rumah.") == 8)
        #expect(LanguageLevel.beginner.mainSentenceWordRange.contains(7))
        #expect(!LanguageLevel.beginner.mainSentenceWordRange.contains(8))
        #expect(LanguageLevel.intermediate.mainSentenceWordRange == 10...15)
        #expect(LanguageLevel.advanced.mainSentenceWordRange == 20...40)
        #expect(LanguageLevel.advanced.preferredMainSentenceWordCountGuidance == "24 to 30 Indonesian words")
        #expect(LanguageLevel.beginner.vocabularyCountRange == 3...5)
        #expect(LanguageLevel.intermediate.vocabularyCountRange == 5...7)
        #expect(LanguageLevel.advanced.vocabularyCountRange == 7...10)
    }

    @Test("OpenAI payload completes sparse advanced vocabulary from the main sentence")
    func generatedPayloadCompletesSparseAdvancedVocabularyItems() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Pada Jumat pagi pukul delapan lewat lima puluh delapan, saya membuka laptop dan komputer sambil mengecek cord, lalu mulai bekerja dengan agak terburu-buru.",
            mainSentenceJP: "金曜日の朝8時58分、私はノートパソコンとパソコンを開き、コードを確認しながら少し急いで作業を始めました。",
            vocabulary: [
                .init(id: "laptop", jp: "ノートパソコン"),
                .init(id: "komputer", jp: "パソコン"),
                .init(id: "cord", jp: "コード"),
            ],
            grammarNote: "sambil は同時進行を表します。",
            conversation: [
                .init(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか？"),
                .init(speaker: "B", id: "Saya sedang mengecek cord.", jp: "私はコードを確認しています。"),
            ],
            similarExpressions: [
                .init(id: "Saya mulai bekerja.", jp: "私は仕事を始めます。"),
                .init(id: "Saya membuka laptop.", jp: "私はノートパソコンを開きます。"),
                .init(id: "Saya mengecek komputer.", jp: "私はパソコンを確認します。"),
            ]
        )

        let lesson = try payload.lesson(source: .openAI, languageLevel: .advanced)

        #expect(lesson.vocabulary.count >= LanguageLevel.advanced.minimumVocabularyCount)
        #expect(lesson.vocabulary.allSatisfy { $0.appearsInMainSentence(lesson.mainSentenceID) })
        #expect(lesson.vocabulary.map(\.id).contains("sambil"))
        #expect(lesson.vocabulary.map(\.id).contains("mulai"))
    }

    @Test("OpenAI payload still rejects advanced lessons when vocabulary cannot be completed")
    func generatedPayloadRejectsAdvancedVocabularyThatCannotBeCompleted() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Dengan perlahan mereka menyusun beberapa benda asing yang tidak dikenal oleh kamus kecil aplikasi sebelum melanjutkan percakapan panjang sore ini.",
            mainSentenceJP: "彼らは今日の夕方、長い会話を続ける前に、アプリの小さな辞書では分からないいくつかの見慣れない物をゆっくり整えました。",
            vocabulary: [
                .init(id: "dengan", jp: "〜で"),
                .init(id: "sebelum", jp: "〜する前に"),
                .init(id: "sore", jp: "夕方"),
            ],
            grammarNote: "sebelum は時間の前後関係を表します。",
            conversation: [
                .init(speaker: "A", id: "Apa yang mereka susun?", jp: "彼らは何を整えていますか？"),
                .init(speaker: "B", id: "Mereka menyusun beberapa benda.", jp: "彼らはいくつかの物を整えています。"),
            ],
            similarExpressions: [
                .init(id: "Mereka melanjutkan percakapan.", jp: "彼らは会話を続けます。"),
                .init(id: "Benda itu tidak dikenal.", jp: "その物は知られていません。"),
                .init(id: "Percakapan ini panjang.", jp: "この会話は長いです。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.insufficientVocabulary(
            validCount: 4,
            minimumCount: 7,
            rejectedItems: []
        )) {
            try payload.lesson(source: .openAI, languageLevel: .advanced)
        }
    }

    @Test("OpenAI payload accepts sparse concrete one-object lessons")
    func generatedPayloadAcceptsSparseConcreteOneObjectLesson() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya melihat skuter merah.",
            mainSentenceJP: "私は赤いスクーターを見ています。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "melihat", jp: "見る"),
                .init(id: "skuter", jp: "スクーター"),
                .init(id: "merah", jp: "赤い"),
            ],
            grammarNote: "Saya + 動詞 = 私は〜します。",
            conversation: [
                .init(speaker: "A", id: "Kamu melihat apa?", jp: "何を見ていますか？"),
                .init(speaker: "B", id: "Saya melihat skuter.", jp: "私はスクーターを見ています。"),
            ],
            similarExpressions: [
                .init(id: "Ini skuter merah.", jp: "これは赤いスクーターです。"),
                .init(id: "Saya naik skuter.", jp: "私はスクーターに乗ります。"),
                .init(id: "Skuter itu baru.", jp: "そのスクーターは新しいです。"),
            ],
            usedKeywords: ["motor scooter"]
        )

        let lesson = try payload.lesson(source: .openAI, languageLevel: .beginner)

        #expect(lesson.vocabulary.map(\.id) == ["saya", "melihat", "skuter", "merah"])
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

        #expect(throws: GeneratedLessonPayloadError.invalidMainSentence) {
            try payload.lesson(source: .openAI)
        }
    }

    @Test("OpenAI payload limits vocabulary by learner level")
    func generatedPayloadLimitsVocabularyByLearnerLevel() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya makan pisang dengan susu di rumah sambil membaca buku kecil.",
            mainSentenceJP: "私は家で小さな本を読みながら、牛乳と一緒にバナナを食べます。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "makan", jp: "食べる"),
                .init(id: "pisang", jp: "バナナ"),
                .init(id: "dengan", jp: "〜と一緒に"),
                .init(id: "susu", jp: "牛乳"),
                .init(id: "rumah", jp: "家"),
                .init(id: "sambil", jp: "〜しながら"),
                .init(id: "membaca", jp: "読む"),
                .init(id: "buku", jp: "本"),
                .init(id: "kecil", jp: "小さい"),
            ],
            grammarNote: "sambil + 動詞 = 〜しながら。",
            conversation: [
                .init(speaker: "A", id: "Kamu makan apa?", jp: "何を食べますか？"),
                .init(speaker: "B", id: "Saya makan pisang.", jp: "私はバナナを食べます。"),
            ],
            similarExpressions: [
                .init(id: "Saya minum susu.", jp: "私は牛乳を飲みます。"),
                .init(id: "Saya makan di rumah.", jp: "私は家で食べます。"),
                .init(id: "Pisang ini enak.", jp: "このバナナはおいしいです。"),
            ]
        )

        let beginnerLesson = try payload.lesson(source: .openAI, languageLevel: .beginner)
        let advancedLesson = try payload.lesson(source: .openAI, languageLevel: .advanced)

        #expect(beginnerLesson.vocabulary.map(\.id) == ["saya", "makan", "pisang", "dengan", "susu"])
        #expect(advancedLesson.vocabulary.map(\.id) == [
            "saya",
            "makan",
            "pisang",
            "dengan",
            "susu",
            "rumah",
            "sambil",
            "membaca",
            "buku",
            "kecil",
        ])
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

        #expect(throws: GeneratedLessonPayloadError.invalidMainSentenceTranslation) {
            try payload.lesson(source: .openAI)
        }
    }

    @Test("OpenAI payload rejects Japanese fields with Thai or Lao script")
    func generatedPayloadRejectsDisallowedTranslationScript() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya menggunakan laptop sambil mengetik.",
            mainSentenceJP: "私はノートパソコンを使いながら ກຳ ピングしています。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "menggunakan", jp: "使う"),
                .init(id: "laptop", jp: "ノートパソコン"),
                .init(id: "sambil", jp: "〜しながら"),
                .init(id: "mengetik", jp: "タイピングする"),
            ],
            grammarNote: "sambil + 動詞 = 〜しながら。",
            conversation: [
                .init(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか？"),
                .init(speaker: "B", id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
            ],
            similarExpressions: [
                .init(id: "Saya memakai laptop.", jp: "私はノートパソコンを使っています。"),
                .init(id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
                .init(id: "Saya bekerja dengan laptop.", jp: "私はノートパソコンで作業しています。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.invalidMainSentenceTranslation) {
            try payload.lesson(source: .openAI)
        }
    }

    @Test("OpenAI payload drops one invalid conversation translation when two valid lines remain")
    func generatedPayloadDropsOneInvalidConversationTranslation() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya melihat gedung dari jendela.",
            mainSentenceJP: "私は窓から建物を見ています。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "melihat", jp: "見る"),
                .init(id: "gedung", jp: "建物"),
                .init(id: "jendela", jp: "窓"),
            ],
            grammarNote: "dari + 場所 は「〜から」を表します。",
            conversation: [
                .init(speaker: "A", id: "Apa yang kamu lihat?", jp: "何を見ていますか？"),
                .init(speaker: "B", id: "Saya melihat gedung.", jp: "建物を見ています。"),
                .init(speaker: "A", id: "Dari mana?", jp: "Dari mana?"),
            ],
            similarExpressions: [
                .init(id: "Saya berdiri dekat jendela.", jp: "私は窓の近くに立っています。"),
                .init(id: "Gedung itu tinggi.", jp: "その建物は高いです。"),
                .init(id: "Saya melihat ke luar.", jp: "私は外を見ています。"),
            ]
        )

        let lesson = try payload.lesson(source: .openAI, languageLevel: .beginner)

        #expect(lesson.conversation.count == 2)
        #expect(lesson.conversation.map(\.speaker) == ["A", "B"])
        #expect(lesson.conversation.allSatisfy {
            LessonTextValidation.isValidJapaneseTranslation($0.jp, sourceText: $0.id)
        })
    }

    @Test("OpenAI payload rejects vocabulary meanings copied from Indonesian")
    func generatedPayloadRejectsCopiedVocabularyMeanings() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya menggunakan laptop sambil mengetik.",
            mainSentenceJP: "私はノートパソコンを使いながらタイピングしています。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "menggunakan", jp: "menggunakan"),
                .init(id: "laptop", jp: "ノートパソコン"),
                .init(id: "sambil", jp: "sambil"),
                .init(id: "mengetik", jp: "mengetik"),
            ],
            grammarNote: "sambil + 動詞 = 〜しながら。",
            conversation: [
                .init(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか？"),
                .init(speaker: "B", id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
            ],
            similarExpressions: [
                .init(id: "Saya memakai laptop.", jp: "私はノートパソコンを使っています。"),
                .init(id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
                .init(id: "Saya bekerja dengan laptop.", jp: "私はノートパソコンで作業しています。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.insufficientVocabulary(
            validCount: 2,
            minimumCount: 3,
            rejectedItems: [
                "menggunakan (invalid Japanese meaning)",
                "sambil (invalid Japanese meaning)",
                "mengetik (invalid Japanese meaning)",
            ]
        )) {
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

    @Test("OpenAI payload ignores invalid vocabulary that is not in the main sentence")
    func generatedPayloadIgnoresInvalidUnusedVocabulary() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Saya menaruh teko air kuning dan botol kecil di atas meja.",
            mainSentenceJP: "私は黄色い水差しと小さなボトルを机の上に置きます。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "menaruh", jp: "置く"),
                .init(id: "teko air", jp: "水差し"),
                .init(id: "botol", jp: "ボトル"),
                .init(id: "meja", jp: "机"),
                .init(id: "consumer electronics", jp: "consumer electronics"),
                .init(id: "water jug", jp: "water jug"),
            ],
            grammarNote: "di atas + 名詞 は「〜の上に」という意味です。",
            conversation: [
                .init(speaker: "A", id: "Kamu menaruh apa?", jp: "何を置きますか？"),
                .init(speaker: "B", id: "Saya menaruh teko air.", jp: "私は水差しを置きます。"),
            ],
            similarExpressions: [
                .init(id: "Botol ada di atas meja.", jp: "ボトルは机の上にあります。"),
                .init(id: "Teko air itu kuning.", jp: "その水差しは黄色です。"),
                .init(id: "Saya menaruh botol kecil.", jp: "私は小さなボトルを置きます。"),
            ]
        )

        let lesson = try payload.lesson(source: .openAI, languageLevel: .intermediate)

        #expect(lesson.vocabulary.map(\.id) == ["saya", "menaruh", "teko air", "botol", "meja"])
    }

    @Test("OpenAI payload drops one invalid used vocabulary item when advanced count remains valid")
    func generatedPayloadDropsInvalidUsedVocabularyWhenEnoughRemain() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "Pada siang ini saya melihat gedung tinggi dari jendela sambil menikmati langit biru yang cerah dan pemandangan kota yang tampak sangat tenang.",
            mainSentenceJP: "今日の昼、私は窓から高い建物を眺めながら、澄んだ青空ととても穏やかに見える街の景色を楽しんでいます。",
            vocabulary: [
                .init(id: "saya", jp: "私"),
                .init(id: "melihat", jp: "見る"),
                .init(id: "gedung", jp: "gedung"),
                .init(id: "dari", jp: "〜から"),
                .init(id: "jendela", jp: "窓"),
                .init(id: "sambil", jp: "〜しながら"),
                .init(id: "menikmati", jp: "楽しむ"),
                .init(id: "langit biru", jp: "青空"),
            ],
            grammarNote: "sambil + 動詞 は、二つの動作を同時に行うことを表します。",
            conversation: [
                .init(speaker: "A", id: "Apa yang kamu lihat?", jp: "何を見ていますか？"),
                .init(speaker: "B", id: "Saya melihat pemandangan kota.", jp: "街の景色を見ています。"),
            ],
            similarExpressions: [
                .init(id: "Langit hari ini cerah.", jp: "今日の空は晴れています。"),
                .init(id: "Saya berdiri dekat jendela.", jp: "私は窓の近くに立っています。"),
                .init(id: "Pemandangan kota terlihat tenang.", jp: "街の景色は穏やかに見えます。"),
            ]
        )

        let lesson = try payload.lesson(source: .openAI, languageLevel: .advanced)

        #expect(lesson.vocabulary.count == 7)
        #expect(!lesson.vocabulary.map(\.id).contains("gedung"))
        #expect(lesson.vocabulary.allSatisfy { $0.appearsInMainSentence(lesson.mainSentenceID) })
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

        #expect(throws: GeneratedLessonPayloadError.overlyGenericMainSentence) {
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

        #expect(throws: GeneratedLessonPayloadError.insufficientVocabulary(
            validCount: 0,
            minimumCount: 3,
            rejectedItems: [
                "motorbike (not in main sentence)",
                "langit biru (not in main sentence)",
                "gerbang lengkung (not in main sentence)",
            ]
        )) {
            try payload.lesson(source: .openAI)
        }
    }

    @Test("English prompt carries language and selected situation")
    func englishPromptCarriesLanguageAndSituation() throws {
        let context = SceneContext(
            timeText: "14:30",
            dayText: "Sunday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "bottle", confidence: 0.94, role: .foreground),
                ImageKeyword(label: "bench", confidence: 0.78, role: .surface),
            ],
            languageLevel: .intermediate,
            lessonLanguage: .english,
            lessonSituation: .park
        )

        let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)

        #expect(prompt.instructions.contains("You are an expert English tutor"))
        #expect(prompt.instructions.contains("Use natural English"))
        #expect(prompt.instructions.contains("10 to 15 English words"))
        #expect(prompt.instructions.contains("Current target language: english"))
        #expect(prompt.instructions.contains("I am studying."))
        #expect(prompt.instructions.contains("drinks and vessels: drink, pour, fill, carry, serve, or place"))
        #expect(!prompt.instructions.contains("Use natural Indonesian"))
        #expect(prompt.sceneJSON.contains("\"lesson_language\":\"english\""))
        #expect(prompt.sceneJSON.contains("\"situation\":\"in a park\""))
        #expect(!prompt.sceneJSON.contains("\"location_label\""))
    }

    @Test("Retired places remain readable but cannot be selected randomly")
    func retiredPlacesRemainCompatible() throws {
        for situation in [LessonSituation.publicTransport, .date, .outAndAbout, .airportOrPort] {
            let data = try JSONEncoder().encode(situation.rawValue)
            #expect(try JSONDecoder().decode(LessonSituation.self, from: data) == situation)
            #expect(!LessonSituation.selectableCases.contains(situation))
            #expect(!LessonSituation.concreteCases.contains(situation))
        }
    }

    @Test("New places reach scene payload in either lesson language")
    func newPlacesReachPayload() throws {
        let places: [(LessonSituation, String)] = [
            (.hospitalOrVet, "at a hospital or veterinary clinic"),
            (.supermarketOrConvenienceStore, "at a supermarket or convenience store"),
            (.departmentStoreOrMall, "at a department store or shopping mall"),
            (.station, "at a train station or airport"),
            (.vehicleOrAircraft, "inside a vehicle or aircraft"),
        ]
        for (place, expected) in places {
            #expect(LessonSituation.concreteCases.contains(place))
            for language in LessonLanguage.allCases {
                let context = SceneContext(timeText: "12:00", dayText: "Monday", locationLabel: .unknown,
                    imageKeywords: [], languageLevel: .beginner, lessonLanguage: language, lessonSituation: place)
                let prompt = try OpenAILessonPromptBuilder().buildPrompt(from: context)
                let payload = try JSONDecoder().decode(OpenAIScenePayload.self, from: Data(prompt.sceneJSON.utf8))
                #expect(payload.situation == expected)
                #expect(place.resolved() == place)
            }
        }
    }

    @Test("Random situation resolves to one concrete option")
    func randomSituationResolvesToConcreteOption() {
        let resolved = LessonSituation.random.resolved()

        #expect(resolved != .random)
        #expect(LessonSituation.concreteCases.contains(resolved))
        #expect(LessonSituation.concreteCases.count == LessonSituation.selectableCases.count - 1)
    }

    @Test("Lesson language and location options match the generation contract")
    func lessonOptionsMatchGenerationContract() {
        #expect(LessonLanguage.allCases.map(\.japaneseName) == ["インドネシア語", "英語"])
        #expect(LessonLanguage.indonesian.supertonicLanguageCode == "id")
        #expect(LessonLanguage.english.supertonicLanguageCode == "en")
        #expect(LessonSituation.selectableCases.map(\.japaneseName) == [
            "ランダム",
            "自宅",
            "友人宅",
            "会社",
            "学校",
            "病院・動物病院",
            "スーパー・コンビニ",
            "デパート・モール",
            "駅・空港",
            "車内・機内",
            "公園",
            "お店",
            "レストラン・カフェ",
            "自然の中",
        ])
        #expect(LessonSituation.shop.promptValue == "at a shop")
        #expect(LessonSituation.airportOrPort.promptValue == "at an airport or port")
        #expect(LessonSituation.outAndAbout.promptValue == "out and about")
    }

    @Test("English payload creates an English lesson")
    func englishPayloadCreatesLesson() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "I carry a bottle while walking through the park with friends.",
            mainSentenceJP: "私は友人たちと公園を歩きながらボトルを持ち運びます。",
            mainSentenceWordCount: 11,
            vocabulary: [
                .init(id: "carry", jp: "持ち運ぶ"),
                .init(id: "bottle", jp: "ボトル"),
                .init(id: "while", jp: "〜しながら"),
                .init(id: "walking", jp: "歩いている"),
                .init(id: "park", jp: "公園"),
            ],
            grammarNote: "while + 動名詞で、二つの動作が同時に進むことを表します。",
            conversation: [
                .init(speaker: "A", id: "Where are you going?", jp: "どこへ行くのですか。"),
                .init(speaker: "B", id: "I am walking through the park.", jp: "公園を歩いています。"),
            ],
            similarExpressions: [
                .init(id: "I am carrying a water bottle.", jp: "水筒を持っています。"),
                .init(id: "We are walking in the park.", jp: "私たちは公園を歩いています。"),
                .init(id: "I brought a drink for my walk.", jp: "散歩用の飲み物を持ってきました。"),
            ],
            usedKeywords: ["bottle"]
        )

        let lesson = try payload.lesson(
            source: .openAI,
            languageLevel: .intermediate,
            lessonLanguage: .english
        )

        #expect(LessonTextValidation.wordCount(lesson.mainSentenceID) == 11)
        #expect(lesson.vocabulary.count == 5)
        #expect(lesson.vocabulary.allSatisfy { $0.appearsInMainSentence(lesson.mainSentenceID) })
    }

    @Test("English generic lesson is rejected")
    func englishGenericLessonIsRejected() throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "I am working.",
            mainSentenceJP: "私は働いています。",
            vocabulary: [
                .init(id: "I", jp: "私"),
                .init(id: "am", jp: "〜です"),
                .init(id: "working", jp: "働いている"),
            ],
            grammarNote: "be動詞 + 動詞のing形で、進行中の動作を表します。",
            conversation: [
                .init(speaker: "A", id: "What are you doing?", jp: "何をしていますか。"),
                .init(speaker: "B", id: "I am working.", jp: "働いています。"),
            ],
            similarExpressions: [
                .init(id: "I work here.", jp: "私はここで働きます。"),
                .init(id: "I am busy.", jp: "私は忙しいです。"),
                .init(id: "I have some work.", jp: "仕事があります。"),
            ]
        )

        #expect(throws: GeneratedLessonPayloadError.overlyGenericMainSentence) {
            try payload.lesson(
                source: .openAI,
                languageLevel: .beginner,
                lessonLanguage: .english
            )
        }
    }
}
