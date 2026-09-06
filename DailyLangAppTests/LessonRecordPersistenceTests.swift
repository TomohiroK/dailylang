import SwiftData
import UserNotifications
import XCTest
@testable import DailyLang

final class LessonRecordPersistenceTests: XCTestCase {
    @MainActor
    func testInsertAndSaveReadsLessonBackByID() throws {
        let modelContext = try makeInMemoryModelContext()
        let record = try makeRecord()

        try LessonRecordPersistence.insertAndSave(record, in: modelContext)

        let savedRecord = try LessonRecordPersistence.fetchSavedRecord(id: record.id, in: modelContext)
        XCTAssertEqual(savedRecord?.mainSentenceID, "Saya sedang makan pisang.")
        XCTAssertEqual(savedRecord?.mainSentenceJP, "私はバナナを食べているところです。")

        let savedRecords = try LessonRecordPersistence.fetchSavedRecords(in: modelContext)
        XCTAssertTrue(savedRecords.contains { $0.id == record.id })
    }

    @MainActor
    func testLessonRecordPersistsEnglishLanguageAndSituation() throws {
        let modelContext = try makeInMemoryModelContext()
        let context = SceneContext(
            timeText: "15:20",
            dayText: "Saturday",
            locationLabel: .unknown,
            imageKeywords: [ImageKeyword(label: "bottle", confidence: 0.93)],
            languageLevel: .beginner,
            lessonLanguage: .english,
            lessonSituation: .park
        )
        let lesson = Lesson(
            mainSentenceID: "I carry a bottle in the park.",
            mainSentenceJP: "私は公園でボトルを持ち歩きます。",
            vocabulary: [
                VocabularyItem(id: "I", jp: "私"),
                VocabularyItem(id: "carry", jp: "持ち運ぶ"),
                VocabularyItem(id: "bottle", jp: "ボトル"),
                VocabularyItem(id: "park", jp: "公園"),
            ],
            grammarNote: "in + 場所で「〜で」という意味になります。",
            conversation: [
                ConversationLine(speaker: "A", id: "Where are you?", jp: "どこにいますか。"),
                ConversationLine(speaker: "B", id: "I am in the park.", jp: "公園にいます。"),
            ],
            similarExpressions: [
                SimilarExpression(id: "I brought a bottle.", jp: "ボトルを持ってきました。"),
                SimilarExpression(id: "I am walking in the park.", jp: "公園を歩いています。"),
                SimilarExpression(id: "This bottle is mine.", jp: "このボトルは私のものです。"),
            ],
            source: .openAI
        )
        let record = try LessonRecord(context: context, lesson: lesson, photoLocalPath: nil)

        try LessonRecordPersistence.insertAndSave(record, in: modelContext)

        let savedRecord = try XCTUnwrap(
            LessonRecordPersistence.fetchSavedRecord(id: record.id, in: modelContext)
        )
        XCTAssertEqual(savedRecord.lessonLanguage, .english)
        XCTAssertEqual(savedRecord.lessonSituation, .park)
    }

    @MainActor
    func testLegacyLessonRecordDefaultsToIndonesianAndRandomSituation() throws {
        let modelContext = try makeInMemoryModelContext()
        let record = try makeRecord()
        record.lessonLanguageRawValue = nil
        record.lessonSituationRawValue = nil

        try LessonRecordPersistence.insertAndSave(record, in: modelContext)

        let savedRecord = try XCTUnwrap(
            LessonRecordPersistence.fetchSavedRecord(id: record.id, in: modelContext)
        )
        XCTAssertEqual(savedRecord.lessonLanguage, .indonesian)
        XCTAssertEqual(savedRecord.lessonSituation, .random)
    }

    @MainActor
    func testInsertAndSaveReadsLessonBackFromPersistentStore() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
        }

        let container = try ModelContainer(
            for: LessonRecord.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let modelContext = ModelContext(container)
        let record = try makeRecord()

        try LessonRecordPersistence.insertAndSave(record, in: modelContext)

        let savedRecord = try LessonRecordPersistence.fetchSavedRecord(id: record.id, in: modelContext)
        XCTAssertEqual(savedRecord?.mainSentenceID, "Saya sedang makan pisang.")

        let secondContext = ModelContext(container)
        let savedRecordFromSecondContext = try LessonRecordPersistence.fetchSavedRecord(id: record.id, in: secondContext)
        XCTAssertEqual(savedRecordFromSecondContext?.mainSentenceJP, "私はバナナを食べているところです。")
    }

    @MainActor
    func testAppModelContainerReadsLessonBackFromPersistentStore() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            removeStoreFiles(at: storeURL)
        }

        let container = DailyLangModelContainer.make(storeURL: storeURL)
        let modelContext = ModelContext(container)
        let record = try makeRecord()

        try LessonRecordPersistence.insertAndSave(record, in: modelContext)

        let savedRecord = try LessonRecordPersistence.fetchSavedRecord(id: record.id, in: ModelContext(container))
        XCTAssertEqual(savedRecord?.mainSentenceID, "Saya sedang makan pisang.")
    }

    @MainActor
    func testInsertAndSaveRejectsEmptyLessonText() throws {
        let modelContext = try makeInMemoryModelContext()
        let record = try makeRecord(mainSentenceID: "", mainSentenceJP: "")

        XCTAssertThrowsError(try LessonRecordPersistence.insertAndSave(record, in: modelContext)) { error in
            XCTAssertEqual(error as? LessonRecordPersistenceError, .emptyLessonText)
        }

        let savedRecords = try LessonRecordPersistence.fetchSavedRecords(in: modelContext)
        XCTAssertTrue(savedRecords.isEmpty)
    }

    @MainActor
    func testInsertAndSaveRejectsNonJapaneseTranslation() throws {
        let modelContext = try makeInMemoryModelContext()
        let record = try makeRecord(
            mainSentenceID: "Sepertinya kucing itu santai di rumah dekat meja dan botol.",
            mainSentenceJP: "Sepertinya kucing itu santai di rumah dekat meja dan botol."
        )

        XCTAssertThrowsError(try LessonRecordPersistence.insertAndSave(record, in: modelContext)) { error in
            XCTAssertEqual(error as? LessonRecordPersistenceError, .missingJapaneseTranslation)
        }

        let savedRecords = try LessonRecordPersistence.fetchSavedRecords(in: modelContext)
        XCTAssertTrue(savedRecords.isEmpty)
    }

    @MainActor
    func testInsertAndSaveRejectsInvalidVocabularyMeaning() throws {
        let modelContext = try makeInMemoryModelContext()
        let record = try makeRecord()
        record.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "saya", jp: "私"),
            VocabularyItem(id: "sedang", jp: "sedang"),
            VocabularyItem(id: "makan", jp: "makan"),
            VocabularyItem(id: "pisang", jp: "バナナ"),
        ])

        XCTAssertThrowsError(try LessonRecordPersistence.insertAndSave(record, in: modelContext)) { error in
            XCTAssertEqual(error as? LessonRecordPersistenceError, .invalidLessonContent)
        }

        let savedRecords = try LessonRecordPersistence.fetchSavedRecords(in: modelContext)
        XCTAssertTrue(savedRecords.isEmpty)
    }

    @MainActor
    func testLearnerVisibleRecordsHideLegacyNonJapaneseTranslation() throws {
        let modelContext = try makeInMemoryModelContext()
        let validRecord = try makeRecord()
        let invalidLegacyRecord = try makeRecord(
            mainSentenceID: "Sepertinya kucing itu santai di rumah dekat meja dan botol.",
            mainSentenceJP: "Sepertinya kucing itu santai di rumah dekat meja dan botol."
        )

        try LessonRecordPersistence.insertAndSave(validRecord, in: modelContext)
        modelContext.insert(invalidLegacyRecord)
        try modelContext.save()

        let allRecords = try LessonRecordPersistence.fetchSavedRecords(in: modelContext)
        let visibleRecords = try LessonRecordPersistence.fetchLearnerVisibleRecords(in: modelContext)

        XCTAssertEqual(allRecords.count, 2)
        XCTAssertEqual(visibleRecords.map(\.id), [validRecord.id])
    }

    func testNotificationDiagnosticLaunchArgumentsAreDefined() {
        XCTAssertEqual(AppStorageKey.showNotificationTimes, "showNotificationTimes")
        XCTAssertEqual(AppStorageKey.lessonLanguage, "lessonLanguage")
        XCTAssertEqual(AppLaunchArgument.scheduleRandomNotifications, "-DailyLangScheduleRandomNotifications")
        XCTAssertEqual(AppLaunchArgument.scheduleTestNotification, "-DailyLangScheduleTestNotification")
        XCTAssertEqual(AppLaunchArgument.showNotificationTimes, "-DailyLangShowNotificationTimes")
        XCTAssertEqual(AppLaunchArgument.hideNotificationTimes, "-DailyLangHideNotificationTimes")
        XCTAssertEqual(AppLaunchArgument.exportDiagnostics, "-DailyLangExportDiagnostics")
    }

    @MainActor
    func testVocabularyFrequencyUsesOnlyVisibleInSentenceVocabulary() throws {
        let firstRecord = try makeRecord()
        let secondRecord = try makeRecord(
            mainSentenceID: "Saya makan pisang dengan susu.",
            mainSentenceJP: "私は牛乳と一緒にバナナを食べます。"
        )
        secondRecord.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "saya", jp: "私"),
            VocabularyItem(id: "makan", jp: "食べる"),
            VocabularyItem(id: "pisang", jp: "バナナ"),
            VocabularyItem(id: "pisang", jp: "バナナ"),
            VocabularyItem(id: "susu", jp: "牛乳"),
        ])

        let hiddenRecord = try makeRecord(
            mainSentenceID: "Saya minum teh.",
            mainSentenceJP: "Saya minum teh."
        )
        hiddenRecord.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "saya", jp: "私"),
            VocabularyItem(id: "minum", jp: "飲む"),
            VocabularyItem(id: "teh", jp: "お茶"),
        ])

        let vocabulary = VocabularyFrequencyIndex.make(from: [firstRecord, secondRecord, hiddenRecord])
        let pisang = try XCTUnwrap(vocabulary.first { $0.term == "pisang" })

        XCTAssertEqual(pisang.language, .indonesian)
        XCTAssertEqual(pisang.japaneseMeaning, "バナナ")
        XCTAssertEqual(pisang.occurrenceCount, 2)
        XCTAssertFalse(vocabulary.contains { $0.term == "teh" })
        XCTAssertEqual(vocabulary.map(\.term), ["makan", "pisang", "saya", "sedang", "susu"])
    }

    @MainActor
    func testVocabularyFrequencySeparatesLanguagesAndNormalizesTermCase() throws {
        let indonesianRecord = try makeRecord()
        let englishContext = SceneContext(
            timeText: "15:20",
            dayText: "Saturday",
            locationLabel: .unknown,
            imageKeywords: [ImageKeyword(label: "banana", confidence: 0.93)],
            languageLevel: .beginner,
            lessonLanguage: .english
        )
        let englishLesson = Lesson(
            mainSentenceID: "I eat a banana.",
            mainSentenceJP: "私はバナナを食べます。",
            vocabulary: [
                VocabularyItem(id: "I", jp: "私"),
                VocabularyItem(id: "eat", jp: "食べる"),
                VocabularyItem(id: "Banana", jp: "バナナ"),
            ],
            grammarNote: "eat は「食べる」という意味の動詞です。",
            conversation: [
                ConversationLine(speaker: "A", id: "What do you eat?", jp: "何を食べますか。"),
                ConversationLine(speaker: "B", id: "I eat a banana.", jp: "私はバナナを食べます。"),
            ],
            similarExpressions: [
                SimilarExpression(id: "I like bananas.", jp: "私はバナナが好きです。"),
                SimilarExpression(id: "This banana is sweet.", jp: "このバナナは甘いです。"),
                SimilarExpression(id: "I bought a banana.", jp: "私はバナナを買いました。"),
            ],
            source: .openAI
        )
        let englishRecord = try LessonRecord(context: englishContext, lesson: englishLesson, photoLocalPath: nil)

        let vocabulary = VocabularyFrequencyIndex.make(from: [indonesianRecord, englishRecord])

        XCTAssertEqual(vocabulary.first { $0.term == "pisang" }?.occurrenceCount, 1)
        XCTAssertEqual(vocabulary.first { $0.term == "Banana" }?.language, .english)
        XCTAssertEqual(vocabulary.first { $0.term == "Banana" }?.japaneseMeaning, "バナナ")
    }

    @MainActor
    func testHomeDailyLifeExpressionHistoryUsesRepeatedSavedExpressionsAsSoftHints() throws {
        let firstRecord = try makeRecord(
            mainSentenceID: "Saya merapikan botol dan cangkir di rumah.",
            mainSentenceJP: "私は家でボトルとカップを片づけます。"
        )
        firstRecord.lessonSituationRawValue = LessonSituation.home.rawValue
        firstRecord.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "saya", jp: "私"),
            VocabularyItem(id: "merapikan", jp: "片づける"),
            VocabularyItem(id: "botol", jp: "ボトル"),
            VocabularyItem(id: "cangkir", jp: "カップ"),
            VocabularyItem(id: "di rumah", jp: "家で"),
        ])

        let secondRecord = try makeRecord(
            mainSentenceID: "Teman saya merapikan meja di rumahnya.",
            mainSentenceJP: "友人は自宅で机を片づけます。"
        )
        secondRecord.lessonSituationRawValue = LessonSituation.friendsHome.rawValue
        secondRecord.createdAt = firstRecord.createdAt.addingTimeInterval(60)
        secondRecord.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "teman", jp: "友人"),
            VocabularyItem(id: "saya", jp: "私の"),
            VocabularyItem(id: "merapikan", jp: "片づける"),
            VocabularyItem(id: "meja", jp: "机"),
            VocabularyItem(id: "di rumahnya", jp: "彼の家で"),
        ])

        let officeRecord = try makeRecord(
            mainSentenceID: "Saya menata dokumen di kantor.",
            mainSentenceJP: "私は会社で書類を整理します。"
        )
        officeRecord.lessonSituationRawValue = LessonSituation.office.rawValue
        officeRecord.createdAt = secondRecord.createdAt.addingTimeInterval(60)
        officeRecord.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "saya", jp: "私"),
            VocabularyItem(id: "menata", jp: "整える"),
            VocabularyItem(id: "dokumen", jp: "書類"),
            VocabularyItem(id: "di kantor", jp: "会社で"),
        ])

        let homeExpressions = LessonDailyLifeExpressionHistory.recentlyRepeatedExpressions(
            from: [firstRecord, secondRecord, officeRecord],
            situation: .home,
            language: .indonesian
        )
        let officeExpressions = LessonDailyLifeExpressionHistory.recentlyRepeatedExpressions(
            from: [firstRecord, secondRecord, officeRecord],
            situation: .office,
            language: .indonesian
        )

        XCTAssertEqual(homeExpressions, ["merapikan"])
        XCTAssertTrue(officeExpressions.isEmpty)
    }

    @MainActor
    func testVocabularyStudyMemoryPersistsFrequencyAndPrioritizesNewCards() throws {
        let modelContext = try makeInMemoryModelContext()
        let firstRecord = try makeRecord()
        let secondRecord = try makeRecord(
            mainSentenceID: "Saya makan pisang dan susu.",
            mainSentenceJP: "私はバナナと牛乳を食べます。"
        )
        secondRecord.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "saya", jp: "私"),
            VocabularyItem(id: "makan", jp: "食べる"),
            VocabularyItem(id: "pisang", jp: "バナナ"),
            VocabularyItem(id: "susu", jp: "牛乳"),
        ])
        try LessonRecordPersistence.insertAndSave(firstRecord, in: modelContext)
        try LessonRecordPersistence.insertAndSave(secondRecord, in: modelContext)

        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let frequencies = VocabularyFrequencyIndex.make(
            from: try LessonRecordPersistence.fetchLearnerVisibleRecords(in: modelContext)
        )
        try VocabularyStudyPersistence.synchronize(
            frequencies: frequencies,
            existingRecords: [],
            in: modelContext,
            now: now
        )

        let studies = try modelContext.fetch(FetchDescriptor<VocabularyStudyRecord>())
        let pisang = try XCTUnwrap(studies.first { $0.uniqueKey == "indonesian|pisang" })
        XCTAssertEqual(pisang.appearanceCount, 2)
        XCTAssertTrue(pisang.isNew)

        try VocabularyStudyPersistence.synchronize(
            frequencies: [
                VocabularyFrequency(
                    language: .indonesian,
                    term: "pisang",
                    japaneseMeaning: "バナナ",
                    occurrenceCount: 1,
                    firstSeenAt: firstRecord.createdAt,
                    lastSeenAt: secondRecord.createdAt
                ),
            ],
            existingRecords: studies,
            in: modelContext,
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(pisang.appearanceCount, 2)

        try VocabularyStudyPersistence.recordReview(
            pisang,
            rating: .easy,
            in: modelContext,
            now: now.addingTimeInterval(120)
        )
        XCTAssertFalse(pisang.isNew)

        let queue = VocabularyReviewQueue.make(
            frequencies: frequencies,
            studyRecords: studies,
            now: now.addingTimeInterval(180)
        )
        XCTAssertTrue(queue.first?.studyRecord.isNew == true)

        let persistedStudies = try modelContext.fetch(FetchDescriptor<VocabularyStudyRecord>())
        XCTAssertEqual(persistedStudies.first { $0.uniqueKey == "indonesian|pisang" }?.appearanceCount, 2)
    }

    @MainActor
    func testVocabularyFSRSSchedulerUsesLearningAndRelearningSteps() throws {
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let frequency = VocabularyFrequency(
            language: .indonesian,
            term: "pisang",
            japaneseMeaning: "バナナ",
            occurrenceCount: 1,
            firstSeenAt: now,
            lastSeenAt: now
        )
        let studyRecord = VocabularyStudyRecord(frequency: frequency, registeredAt: now)

        VocabularyFSRSScheduler.schedule(studyRecord, rating: .good, at: now)
        XCTAssertEqual(studyRecord.state, .learning)
        XCTAssertEqual(studyRecord.learningStepIndex, 1)
        XCTAssertEqual(studyRecord.dueAt, now.addingTimeInterval(600))
        XCTAssertGreaterThan(studyRecord.stabilityDays, 0)
        XCTAssertGreaterThan(studyRecord.difficulty, 0)

        let secondReview = now.addingTimeInterval(600)
        VocabularyFSRSScheduler.schedule(studyRecord, rating: .good, at: secondReview)
        XCTAssertEqual(studyRecord.state, .review)
        XCTAssertEqual(studyRecord.learningStepIndex, -1)
        let scheduledDueAt = try XCTUnwrap(studyRecord.dueAt)
        XCTAssertGreaterThan(scheduledDueAt, secondReview)
        XCTAssertLessThan(
            VocabularyFSRSScheduler.retrievability(of: studyRecord, at: secondReview.addingTimeInterval(86_400)),
            1
        )

        let failedReview = scheduledDueAt.addingTimeInterval(86_400)
        VocabularyFSRSScheduler.schedule(studyRecord, rating: .again, at: failedReview)
        XCTAssertEqual(studyRecord.state, .relearning)
        XCTAssertEqual(studyRecord.learningStepIndex, 0)
        XCTAssertEqual(studyRecord.dueAt, failedReview.addingTimeInterval(600))
        XCTAssertEqual(studyRecord.lapseCount, 1)
    }

    @MainActor
    func testVocabularyStudySchemaOpensExistingLessonStore() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            removeStoreFiles(at: storeURL)
        }

        do {
            let legacyContainer = try ModelContainer(
                for: LessonRecord.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let legacyContext = ModelContext(legacyContainer)
            try LessonRecordPersistence.insertAndSave(try makeRecord(), in: legacyContext)
        }

        let upgradedContainer = DailyLangModelContainer.make(storeURL: storeURL)
        let upgradedContext = ModelContext(upgradedContainer)
        let records = try LessonRecordPersistence.fetchLearnerVisibleRecords(in: upgradedContext)
        let frequencies = VocabularyFrequencyIndex.make(from: records)
        try VocabularyStudyPersistence.synchronize(
            frequencies: frequencies,
            existingRecords: [],
            in: upgradedContext,
            now: Date(timeIntervalSinceReferenceDate: 700_000_000)
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(try upgradedContext.fetch(FetchDescriptor<VocabularyStudyRecord>()).count, 4)
    }

    func testSelectedGenerationLocationIsPassedToSceneContext() {
        let context = SceneContextFactory().makeContext(
            date: Date(timeIntervalSince1970: 0),
            imageKeywords: [ImageKeyword(label: "cat", confidence: 0.95)],
            userNote: "",
            level: .beginner,
            lessonLanguage: .indonesian,
            lessonSituation: .friendsHome
        )

        XCTAssertEqual(context.lessonSituation, .friendsHome)
        XCTAssertEqual(context.userNote, "")
        XCTAssertEqual(context.lessonGrammarFocus, .simpleStatement)
    }

    func testGrammarFocusHistoryCyclesBeforeRepeating() {
        let suiteName = "LessonGrammarFocusHistoryTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let level = LanguageLevel.beginner
        let language = LessonLanguage.indonesian
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let choices = LessonGrammarFocus.choices(for: level)
        let selected = choices.map { _ -> LessonGrammarFocus in
            let focus = LessonGrammarFocusHistory.nextFocus(
                for: level,
                language: language,
                userDefaults: userDefaults
            )
            LessonGrammarFocusHistory.record(
                focus,
                level: level,
                language: language,
                userDefaults: userDefaults
            )
            return focus
        }

        XCTAssertEqual(selected, choices)
        XCTAssertEqual(
            LessonGrammarFocusHistory.nextFocus(
                for: level,
                language: language,
                userDefaults: userDefaults
            ),
            choices.first
        )
    }

    func testDailyLangNotificationCategoryRoutesToCamera() {
        XCTAssertTrue(NotificationCategory.shouldOpenCamera(for: NotificationCategory.captureScene))
        XCTAssertFalse(NotificationCategory.shouldOpenCamera(for: "OTHER"))
    }

    func testDailyLangNotificationCategoryIncludesForegroundCameraAction() throws {
        let category = NotificationCategory.makeCaptureSceneCategory()
        let action = try XCTUnwrap(
            category.actions.first { $0.identifier == NotificationCategory.openCameraAction }
        )

        XCTAssertEqual(category.identifier, NotificationCategory.captureScene)
        XCTAssertEqual(action.title, "写真を撮る")
        XCTAssertTrue(action.options.contains(.foreground))
    }

    func testDailyLangNotificationRequestsRouteToCameraByIdentifier() {
        let randomRequest = UNNotificationRequest(
            identifier: "\(NotificationIdentifier.scheduledPromptIdentifierPrefix)-test",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let testRequest = UNNotificationRequest(
            identifier: NotificationIdentifier.testPromptIdentifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let otherRequest = UNNotificationRequest(
            identifier: "other",
            content: UNMutableNotificationContent(),
            trigger: nil
        )

        XCTAssertTrue(NotificationCategory.shouldOpenCamera(for: randomRequest))
        XCTAssertTrue(NotificationCategory.shouldOpenCamera(for: testRequest))
        XCTAssertFalse(NotificationCategory.shouldOpenCamera(for: otherRequest))
    }

    func testDailyLangNotificationTapActionsRouteToCamera() {
        let randomRequest = UNNotificationRequest(
            identifier: "\(NotificationIdentifier.scheduledPromptIdentifierPrefix)-test",
            content: UNMutableNotificationContent(),
            trigger: nil
        )

        XCTAssertTrue(NotificationCategory.shouldOpenCamera(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            request: randomRequest
        ))
        XCTAssertTrue(NotificationCategory.shouldOpenCamera(
            actionIdentifier: NotificationCategory.openCameraAction,
            request: randomRequest
        ))
        XCTAssertFalse(NotificationCategory.shouldOpenCamera(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            request: randomRequest
        ))
    }

    func testOpenAIServiceErrorsExposeStableCodes() {
        let invalidPayload = OpenAILessonServiceError.invalidLessonPayload("decode failed")
        XCTAssertEqual(invalidPayload.code, .invalidLessonPayload)
        XCTAssertEqual(
            invalidPayload.localizedDescription,
            "OpenAI APIのレッスン形式が不正でした。(Error-1029)"
        )
        XCTAssertTrue(invalidPayload.localizedDescription.contains("(Error-1029)"))
        XCTAssertTrue(invalidPayload.isRepairableByRegeneration)

        let unexpected = OpenAILessonServiceError.unexpected("new branch needed")
        XCTAssertEqual(unexpected.code, .unexpected)
        XCTAssertTrue(unexpected.localizedDescription.contains("(Error-1099)"))
        XCTAssertFalse(unexpected.isRepairableByRegeneration)

        let apiError = OpenAILessonServiceError.apiError("model error")
        XCTAssertEqual(apiError.code, .apiError)
        XCTAssertTrue(apiError.localizedDescription.contains("(Error-1005)"))
        XCTAssertFalse(apiError.isRepairableByRegeneration)

        let untranslatedKeywords = OpenAILessonServiceError.untranslatedImageKeywords([
            "book",
            "document",
        ])
        XCTAssertEqual(untranslatedKeywords.code, .untranslatedImageKeywords)
        XCTAssertTrue(untranslatedKeywords.localizedDescription.contains("(Error-1031)"))
        XCTAssertTrue(untranslatedKeywords.isRepairableByRegeneration)
    }

    @MainActor
    func testLessonGenerationFailureDiagnosticsFallsBackToFile() throws {
        let suiteName = "LessonGenerationFailureDiagnosticsTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let failureFileURL = directoryURL
            .appendingPathComponent("latest-lesson-generation-failure.txt")
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let error = OpenAILessonServiceError.invalidLessonPayload(
            "main_sentence_jp is not a valid Japanese translation"
        )
        LessonGenerationFailureDiagnostics.record(
            error,
            userDefaults: userDefaults,
            failureFileURL: failureFileURL
        )
        userDefaults.removeObject(forKey: "latestLessonGenerationFailure")

        XCTAssertEqual(
            LessonGenerationFailureDiagnostics.latest(
                userDefaults: userDefaults,
                failureFileURL: failureFileURL
            ),
            "OpenAI APIのレッスン形式が不正でした。(Error-1029) reason: main_sentence_jp is not a valid Japanese translation"
        )

        LessonGenerationFailureDiagnostics.clear(
            userDefaults: userDefaults,
            failureFileURL: failureFileURL
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: failureFileURL.path))
    }

    func testOpenAIServiceRetriesInvalidLessonJSONWithCodedErrorBranch() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try JSONSerialization.data(withJSONObject: ["output_text": #"{"main_sentence_id":1}"#]),
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya makan pisang kecil.",
                    mainSentenceJP: "私は小さいバナナを食べます。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "makan", jp: "食べる"),
                        VocabularyItem(id: "pisang", jp: "バナナ"),
                        VocabularyItem(id: "kecil", jp: "小さい"),
                    ],
                    grammarNote: "Saya + 動詞 = 私は〜します。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu makan apa?", jp: "何を食べますか。"),
                        ConversationLine(speaker: "B", id: "Saya makan pisang.", jp: "私はバナナを食べます。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Pisang ini kecil.", jp: "このバナナは小さいです。"),
                        SimilarExpression(id: "Saya melihat pisang.", jp: "私はバナナを見ます。"),
                        SimilarExpression(id: "Saya mau makan.", jp: "私は食べたいです。"),
                    ],
                    usedKeywords: ["banana"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "09:00",
            dayText: "Tuesday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.9, role: .foreground),
            ],
            userNote: "",
            languageLevel: .beginner
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya makan pisang kecil.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 2)
        let secondRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.dropFirst().first)
        let secondRequestBody = String(decoding: secondRequestData, as: UTF8.self)
        XCTAssertTrue(secondRequestBody.contains("failed validation for this exact reason"))
        XCTAssertTrue(secondRequestBody.contains("lesson JSON decode failed"))
    }

    func testOpenAIServiceForwardsGrammarFocusToPrompt() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya akan makan pisang.",
                    mainSentenceJP: "私はバナナを食べる予定です。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "akan", jp: "〜する予定だ"),
                        VocabularyItem(id: "makan", jp: "食べる"),
                        VocabularyItem(id: "pisang", jp: "バナナ"),
                    ],
                    grammarNote: "akan + 動詞で、これから行う予定を表します。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu akan makan apa?", jp: "何を食べる予定ですか。"),
                        ConversationLine(speaker: "B", id: "Saya akan makan pisang.", jp: "私はバナナを食べる予定です。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya ingin makan pisang.", jp: "私はバナナを食べたいです。"),
                        SimilarExpression(id: "Nanti saya makan pisang.", jp: "あとでバナナを食べます。"),
                        SimilarExpression(id: "Pisang ini untuk saya.", jp: "このバナナは私用です。"),
                    ],
                    usedKeywords: ["banana"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "09:00",
            dayText: "Tuesday",
            locationLabel: .unknown,
            imageKeywords: [ImageKeyword(label: "banana", confidence: 0.94)],
            languageLevel: .beginner,
            lessonGrammarFocus: .futurePlan
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya akan makan pisang.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
        let requestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.first)
        let requestBody = String(decoding: requestData, as: UTF8.self)
        XCTAssertTrue(requestBody.contains("future_plan"))
        XCTAssertTrue(requestBody.contains("Use a near-future plan or intention"))
    }

    func testOpenAIServiceRetriesInvalidSparsePayload() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya sedang belajar.",
                    mainSentenceJP: "私は勉強しています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "sedang", jp: "〜している"),
                        VocabularyItem(id: "belajar", jp: "勉強する"),
                        VocabularyItem(id: "dokumen", jp: "書類"),
                    ],
                    grammarNote: "sedang + 動詞 = 今〜している。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                        ConversationLine(speaker: "B", id: "Saya sedang belajar.", jp: "勉強しています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya belajar di rumah.", jp: "私は家で勉強します。"),
                        SimilarExpression(id: "Saya sedang membaca.", jp: "私は読んでいます。"),
                        SimilarExpression(id: "Saya mau belajar.", jp: "私は勉強したいです。"),
                    ]
                )
            ),
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya makan pisang dengan susu.",
                    mainSentenceJP: "私は牛乳と一緒にバナナを食べます。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "makan", jp: "食べる"),
                        VocabularyItem(id: "pisang", jp: "バナナ"),
                        VocabularyItem(id: "dengan", jp: "〜と一緒に"),
                        VocabularyItem(id: "susu", jp: "牛乳"),
                    ],
                    grammarNote: "dengan + 名詞 = 〜と一緒に。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                        ConversationLine(speaker: "B", id: "Saya makan pisang.", jp: "バナナを食べています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya minum susu.", jp: "私は牛乳を飲みます。"),
                        SimilarExpression(id: "Pisang ini manis.", jp: "このバナナは甘いです。"),
                        SimilarExpression(id: "Saya makan di meja.", jp: "私はテーブルで食べます。"),
                    ],
                    usedKeywords: ["banana", "milk"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "13:59",
            dayText: "Sunday",
            locationLabel: .home,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.94, count: 3),
                ImageKeyword(label: "milk", confidence: 0.72),
                ImageKeyword(label: "cup", confidence: 0.68),
            ],
            userNote: "",
            languageLevel: .beginner
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya makan pisang dengan susu.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 2)
        let secondRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.dropFirst().first)
        let secondRequestBody = String(decoding: secondRequestData, as: UTF8.self)
        XCTAssertTrue(secondRequestBody.contains("failed validation for this exact reason"))
        XCTAssertTrue(secondRequestBody.contains("main_sentence_id is overly generic"))
    }

    func testOpenAIServiceRetriesNonJapaneseTranslationPayload() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Sepertinya kucing itu santai di rumah dekat meja dan botol.",
                    mainSentenceJP: "Sepertinya kucing itu santai di rumah dekat meja dan botol.",
                    vocabulary: [
                        VocabularyItem(id: "sepertinya", jp: "どうやら"),
                        VocabularyItem(id: "kucing", jp: "猫"),
                        VocabularyItem(id: "rumah", jp: "家"),
                        VocabularyItem(id: "meja", jp: "机"),
                        VocabularyItem(id: "botol", jp: "ボトル"),
                    ],
                    grammarNote: "dekat + 名詞 = 〜の近く。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kucing itu di mana?", jp: "その猫はどこにいますか。"),
                        ConversationLine(speaker: "B", id: "Kucing itu di rumah.", jp: "その猫は家にいます。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Kucing itu santai.", jp: "その猫はくつろいでいます。"),
                        SimilarExpression(id: "Kucing itu dekat meja.", jp: "その猫は机の近くにいます。"),
                        SimilarExpression(id: "Ada botol di meja.", jp: "机にボトルがあります。"),
                    ],
                    usedKeywords: ["cat", "bottle"]
                )
            ),
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Sepertinya kucing itu santai di rumah dekat meja dan botol.",
                    mainSentenceJP: "どうやらその猫は家で、机とボトルの近くでくつろいでいます。",
                    vocabulary: [
                        VocabularyItem(id: "sepertinya", jp: "どうやら"),
                        VocabularyItem(id: "kucing", jp: "猫"),
                        VocabularyItem(id: "rumah", jp: "家"),
                        VocabularyItem(id: "meja", jp: "机"),
                        VocabularyItem(id: "botol", jp: "ボトル"),
                    ],
                    grammarNote: "dekat + 名詞 = 〜の近く。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kucing itu di mana?", jp: "その猫はどこにいますか。"),
                        ConversationLine(speaker: "B", id: "Kucing itu di rumah.", jp: "その猫は家にいます。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Kucing itu santai.", jp: "その猫はくつろいでいます。"),
                        SimilarExpression(id: "Kucing itu dekat meja.", jp: "その猫は机の近くにいます。"),
                        SimilarExpression(id: "Ada botol di meja.", jp: "机にボトルがあります。"),
                    ],
                    usedKeywords: ["cat", "bottle"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "20:04",
            dayText: "Sunday",
            locationLabel: .home,
            imageKeywords: [
                ImageKeyword(label: "cat", confidence: 0.84),
                ImageKeyword(label: "table", confidence: 0.74, role: .surface),
                ImageKeyword(label: "bottle", confidence: 0.68),
            ],
            userNote: "",
            languageLevel: .intermediate
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceJP, "どうやらその猫は家で、机とボトルの近くでくつろいでいます。")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 2)
        let secondRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.dropFirst().first)
        let secondRequestBody = String(decoding: secondRequestData, as: UTF8.self)
        XCTAssertTrue(secondRequestBody.contains("failed Japanese-field validation for this reason"))
        XCTAssertTrue(secondRequestBody.contains("main_sentence_jp is not a valid Japanese translation"))
        XCTAssertTrue(secondRequestBody.contains("Audit and rewrite every learner-facing Japanese field"))
        XCTAssertTrue(secondRequestBody.contains("Previous invalid lesson JSON"))
        XCTAssertTrue(secondRequestBody.contains("Sepertinya kucing itu santai di rumah dekat meja dan botol."))
        XCTAssertTrue(secondRequestBody.contains("Preserve every field that already satisfies the requirements"))
    }

    func testOpenAIServiceRetriesCopiedVocabularyMeanings() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya menggunakan laptop sambil mengetik.",
                    mainSentenceJP: "私はノートパソコンを使いながらタイピングしています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "menggunakan", jp: "menggunakan"),
                        VocabularyItem(id: "laptop", jp: "ノートパソコン"),
                        VocabularyItem(id: "sambil", jp: "sambil"),
                        VocabularyItem(id: "mengetik", jp: "mengetik"),
                    ],
                    grammarNote: "sambil + 動詞 = 〜しながら。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                        ConversationLine(speaker: "B", id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya memakai laptop.", jp: "私はノートパソコンを使っています。"),
                        SimilarExpression(id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
                        SimilarExpression(id: "Saya bekerja dengan laptop.", jp: "私はノートパソコンで作業しています。"),
                    ],
                    usedKeywords: ["laptop", "keyboard"]
                )
            ),
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya menggunakan laptop sambil mengetik.",
                    mainSentenceJP: "私はノートパソコンを使いながらタイピングしています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "menggunakan", jp: "使う"),
                        VocabularyItem(id: "laptop", jp: "ノートパソコン"),
                        VocabularyItem(id: "sambil", jp: "〜しながら"),
                        VocabularyItem(id: "mengetik", jp: "タイピングする"),
                    ],
                    grammarNote: "sambil + 動詞 = 〜しながら。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                        ConversationLine(speaker: "B", id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya memakai laptop.", jp: "私はノートパソコンを使っています。"),
                        SimilarExpression(id: "Saya sedang mengetik.", jp: "私はタイピングしています。"),
                        SimilarExpression(id: "Saya bekerja dengan laptop.", jp: "私はノートパソコンで作業しています。"),
                    ],
                    usedKeywords: ["laptop", "keyboard"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "14:03",
            dayText: "Monday",
            locationLabel: .home,
            imageKeywords: [
                ImageKeyword(label: "laptop", confidence: 0.91),
                ImageKeyword(label: "keyboard", confidence: 0.73),
            ],
            userNote: "",
            languageLevel: .beginner
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.vocabulary.map(\.jp), ["私", "使う", "ノートパソコン", "〜しながら", "タイピングする"])
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 2)
        let secondRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.dropFirst().first)
        let secondRequestBody = String(decoding: secondRequestData, as: UTF8.self)
        XCTAssertTrue(secondRequestBody.contains("failed Japanese-field validation for this reason"))
        XCTAssertTrue(secondRequestBody.contains("invalid Japanese meaning"))
        XCTAssertTrue(secondRequestBody.contains("Audit and rewrite every learner-facing Japanese field"))
    }

    func testOpenAIServiceRetriesWhenForegroundKeywordsAreIgnored() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya membersihkan meja sambil memakai laptop di dekat kursi ruang kerja.",
                    mainSentenceJP: "私は仕事部屋の椅子の近くで、ノートパソコンを使いながらテーブルを掃除しています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "membersihkan", jp: "掃除する"),
                        VocabularyItem(id: "meja", jp: "テーブル"),
                        VocabularyItem(id: "sambil", jp: "〜しながら"),
                        VocabularyItem(id: "memakai", jp: "使う"),
                        VocabularyItem(id: "laptop", jp: "ノートパソコン"),
                        VocabularyItem(id: "kursi", jp: "椅子"),
                    ],
                    grammarNote: "sambil + 動詞 = 〜しながら。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                        ConversationLine(speaker: "B", id: "Saya membersihkan meja.", jp: "テーブルを掃除しています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya memakai laptop.", jp: "私はノートパソコンを使っています。"),
                        SimilarExpression(id: "Saya membersihkan meja.", jp: "私はテーブルを掃除しています。"),
                        SimilarExpression(id: "Meja ini bersih.", jp: "このテーブルはきれいです。"),
                    ],
                    usedKeywords: ["dining table", "laptop"]
                )
            ),
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya makan pisang sambil melihat bunga kecil di atas meja.",
                    mainSentenceJP: "私はテーブルの上の小さな花を見ながらバナナを食べています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "makan", jp: "食べる"),
                        VocabularyItem(id: "pisang", jp: "バナナ"),
                        VocabularyItem(id: "sambil", jp: "〜しながら"),
                        VocabularyItem(id: "bunga", jp: "花"),
                        VocabularyItem(id: "kecil", jp: "小さい"),
                        VocabularyItem(id: "meja", jp: "テーブル"),
                    ],
                    grammarNote: "sambil + 動詞 = 〜しながら。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                        ConversationLine(speaker: "B", id: "Saya makan pisang.", jp: "バナナを食べています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya melihat bunga.", jp: "私は花を見ています。"),
                        SimilarExpression(id: "Saya makan pisang.", jp: "私はバナナを食べています。"),
                        SimilarExpression(id: "Ada bunga di atas meja.", jp: "テーブルの上に花があります。"),
                    ],
                    usedKeywords: ["banana", "flower"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "08:15",
            dayText: "Thursday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.48, role: .foreground),
                ImageKeyword(label: "flower", confidence: 0.42, role: .foreground),
                ImageKeyword(label: "dining table", confidence: 0.92, role: .surface),
            ],
            imageRelations: ["banana on dining table", "flower on dining table"],
            userNote: "",
            languageLevel: .intermediate
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya makan pisang sambil melihat bunga kecil di atas meja.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 2)
        let secondRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.dropFirst().first)
        let secondRequestBody = String(decoding: secondRequestData, as: UTF8.self)
        XCTAssertTrue(secondRequestBody.contains("ignored all foreground objects"))
    }

    func testOpenAIServiceAcceptsMainSentenceOutsideLevelWordCountTarget() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya makan pisang dengan susu dan cangkir kecil.",
                    mainSentenceJP: "私は牛乳と小さなカップと一緒にバナナを食べます。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "makan", jp: "食べる"),
                        VocabularyItem(id: "pisang", jp: "バナナ"),
                        VocabularyItem(id: "dengan", jp: "〜と一緒に"),
                        VocabularyItem(id: "susu", jp: "牛乳"),
                        VocabularyItem(id: "dan", jp: "そして"),
                        VocabularyItem(id: "cangkir", jp: "カップ"),
                        VocabularyItem(id: "kecil", jp: "小さい"),
                    ],
                    grammarNote: "dengan + 名詞 = 〜と一緒に。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu makan apa?", jp: "何を食べていますか。"),
                        ConversationLine(speaker: "B", id: "Saya makan pisang.", jp: "私はバナナを食べています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya minum susu.", jp: "私は牛乳を飲みます。"),
                        SimilarExpression(id: "Pisang ini manis.", jp: "このバナナは甘いです。"),
                        SimilarExpression(id: "Saya makan dengan susu.", jp: "私は牛乳と一緒に食べます。"),
                    ],
                    usedKeywords: ["banana", "milk"]
                )
            ),
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Sepertinya saya perlu menyusun pisang, susu, cangkir, dan keranjang di atas meja dengan lebih rapi sebelum mulai sarapan pagi ini.",
                    mainSentenceJP: "どうやら今朝の朝食を始める前に、テーブルの上でバナナ、牛乳、カップ、かごをもう少し整える必要がありそうです。",
                    vocabulary: [
                        VocabularyItem(id: "sepertinya", jp: "どうやら"),
                        VocabularyItem(id: "perlu", jp: "必要がある"),
                        VocabularyItem(id: "menyusun", jp: "整える"),
                        VocabularyItem(id: "pisang", jp: "バナナ"),
                        VocabularyItem(id: "susu", jp: "牛乳"),
                        VocabularyItem(id: "cangkir", jp: "カップ"),
                        VocabularyItem(id: "keranjang", jp: "かご"),
                        VocabularyItem(id: "sebelum", jp: "〜する前に"),
                    ],
                    grammarNote: "sepertinya は推量をやわらかく示し、sebelum は「〜する前に」という時間関係を表します。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu mau mulai sarapan?", jp: "朝食を始めるところですか。"),
                        ConversationLine(speaker: "B", id: "Sebentar, saya perlu menyusun meja dulu.", jp: "少し待って、先にテーブルを整える必要があります。"),
                        ConversationLine(speaker: "A", id: "Ada apa saja?", jp: "何がありますか。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya menyusun cangkir dan keranjang.", jp: "私はカップとかごを整えています。"),
                        SimilarExpression(id: "Saya mulai sarapan pagi ini.", jp: "私は今朝、朝食を始めます。"),
                        SimilarExpression(id: "Pisang dan susu ada di atas meja.", jp: "バナナと牛乳がテーブルの上にあります。"),
                    ],
                    usedKeywords: ["banana", "milk", "cup", "basket"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "08:15",
            dayText: "Thursday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.91),
                ImageKeyword(label: "milk", confidence: 0.82),
                ImageKeyword(label: "cup", confidence: 0.72),
                ImageKeyword(label: "basket", confidence: 0.66),
            ],
            userNote: "",
            languageLevel: .advanced
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(
            lesson.mainSentenceID,
            "Saya makan pisang dengan susu dan cangkir kecil."
        )
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
        let firstRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.first)
        let firstRequestBody = String(decoding: firstRequestData, as: UTF8.self)
        XCTAssertTrue(firstRequestBody.contains("One complete Indonesian sentence appropriate for the advanced level"))
        XCTAssertTrue(firstRequestBody.contains("A length outside this target is still acceptable."))
        XCTAssertTrue(firstRequestBody.contains("main_sentence_word_count"))
        XCTAssertFalse(firstRequestBody.contains("\"minimum\":20"))
        XCTAssertFalse(firstRequestBody.contains("\"maximum\":40"))
        XCTAssertTrue(firstRequestBody.contains("\"minItems\":7"))
        XCTAssertTrue(firstRequestBody.contains("\"maxItems\":10"))
    }

    func testOpenAIServiceRepairsEnglishImageLabelsInIndonesianSentence() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Pada Jumat sore, saya menata book dan document di atas furniture, lalu memindahkan bottle serta cord supaya semuanya terlihat jauh lebih rapi.",
                    mainSentenceJP: "Pada Jumat sore, saya menata book dan document di atas furniture, lalu memindahkan bottle serta cord supaya semuanya terlihat jauh lebih rapi.",
                    mainSentenceWordCount: 22,
                    vocabulary: [
                        VocabularyItem(id: "menata", jp: "整える"),
                        VocabularyItem(id: "book", jp: "本"),
                        VocabularyItem(id: "document", jp: "書類"),
                        VocabularyItem(id: "furniture", jp: "家具"),
                        VocabularyItem(id: "memindahkan", jp: "移動する"),
                        VocabularyItem(id: "bottle", jp: "ボトル"),
                        VocabularyItem(id: "cord", jp: "コード"),
                        VocabularyItem(id: "supaya", jp: "〜するように"),
                    ],
                    grammarNote: "supaya は目的を自然に示す接続表現です。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang merapikan meja?", jp: "机を片づけていますか。"),
                        ConversationLine(speaker: "B", id: "Iya, saya sedang menata barang-barang ini.", jp: "はい、これらの物を整えています。"),
                        ConversationLine(speaker: "A", id: "Perlu saya bantu?", jp: "手伝いましょうか。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya merapikan barang-barang di meja.", jp: "私は机の上の物を片づけます。"),
                        SimilarExpression(id: "Saya memindahkan beberapa barang.", jp: "私はいくつかの物を移動します。"),
                        SimilarExpression(id: "Meja ini terlihat lebih rapi.", jp: "この机はより整って見えます。"),
                    ],
                    usedKeywords: ["book", "document", "furniture", "bottle", "cord"]
                )
            ),
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Pada Jumat sore, saya menata buku dan dokumen di atas perabot, lalu memindahkan botol serta kabel supaya semuanya terlihat jauh lebih rapi.",
                    mainSentenceJP: "金曜日の午後、私は本と書類を家具の上で整え、ボトルとケーブルを移して、全体をよりきれいにしました。",
                    mainSentenceWordCount: 22,
                    vocabulary: [
                        VocabularyItem(id: "menata", jp: "整える"),
                        VocabularyItem(id: "buku", jp: "本"),
                        VocabularyItem(id: "dokumen", jp: "書類"),
                        VocabularyItem(id: "perabot", jp: "家具"),
                        VocabularyItem(id: "memindahkan", jp: "移動する"),
                        VocabularyItem(id: "botol", jp: "ボトル"),
                        VocabularyItem(id: "kabel", jp: "ケーブル"),
                        VocabularyItem(id: "supaya", jp: "〜するように"),
                    ],
                    grammarNote: "supaya は目的を自然に示す接続表現です。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang merapikan meja?", jp: "机を片づけていますか。"),
                        ConversationLine(speaker: "B", id: "Iya, saya sedang menata barang-barang ini.", jp: "はい、これらの物を整えています。"),
                        ConversationLine(speaker: "A", id: "Perlu saya bantu?", jp: "手伝いましょうか。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya merapikan barang-barang di meja.", jp: "私は机の上の物を片づけます。"),
                        SimilarExpression(id: "Saya memindahkan beberapa barang.", jp: "私はいくつかの物を移動します。"),
                        SimilarExpression(id: "Meja ini terlihat lebih rapi.", jp: "この机はより整って見えます。"),
                    ],
                    usedKeywords: ["book", "document", "furniture", "bottle", "cord"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "14:16",
            dayText: "Friday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "book", confidence: 0.84),
                ImageKeyword(label: "document", confidence: 0.66),
                ImageKeyword(label: "furniture", confidence: 0.64, role: .surface),
                ImageKeyword(label: "bottle", confidence: 0.88),
                ImageKeyword(label: "cord", confidence: 0.78),
            ],
            languageLevel: .advanced
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertTrue(lesson.mainSentenceID.contains("buku dan dokumen"))
        XCTAssertFalse(lesson.mainSentenceID.contains("book"))
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 2)
        let secondRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.dropFirst().first)
        let secondRequestBody = String(decoding: secondRequestData, as: UTF8.self)
        XCTAssertTrue(secondRequestBody.contains("book -> buku"))
        XCTAssertTrue(secondRequestBody.contains("document -> dokumen"))
        XCTAssertTrue(secondRequestBody.contains("Previous invalid lesson JSON"))
        XCTAssertFalse(secondRequestBody.contains("failed Japanese-field validation"))
    }

    func testOpenAIServiceSavesFinalMainSentenceOutsideLevelWordCountTarget() async throws {
        let shortPayload = GeneratedLessonPayload(
            mainSentenceID: "Saya makan pisang dengan susu dan cangkir kecil.",
            mainSentenceJP: "私は牛乳と小さなカップと一緒にバナナを食べます。",
            vocabulary: [
                VocabularyItem(id: "saya", jp: "私"),
                VocabularyItem(id: "makan", jp: "食べる"),
                VocabularyItem(id: "pisang", jp: "バナナ"),
                VocabularyItem(id: "dengan", jp: "〜と一緒に"),
                VocabularyItem(id: "susu", jp: "牛乳"),
                VocabularyItem(id: "dan", jp: "そして"),
                VocabularyItem(id: "cangkir", jp: "カップ"),
                VocabularyItem(id: "kecil", jp: "小さい"),
            ],
            grammarNote: "dengan + 名詞 = 〜と一緒に。",
            conversation: [
                ConversationLine(speaker: "A", id: "Kamu makan apa?", jp: "何を食べていますか。"),
                ConversationLine(speaker: "B", id: "Saya makan pisang.", jp: "私はバナナを食べています。"),
            ],
            similarExpressions: [
                SimilarExpression(id: "Saya minum susu.", jp: "私は牛乳を飲みます。"),
                SimilarExpression(id: "Pisang ini manis.", jp: "このバナナは甘いです。"),
                SimilarExpression(id: "Saya makan dengan susu.", jp: "私は牛乳と一緒に食べます。"),
            ],
            usedKeywords: ["banana", "milk"]
        )
        let responseBody = try openAIResponseBody(for: shortPayload)
        OpenAILessonServiceMockURLProtocol.responseBodies = Array(repeating: responseBody, count: 5)
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "08:15",
            dayText: "Thursday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.91),
                ImageKeyword(label: "milk", confidence: 0.82),
            ],
            userNote: "",
            languageLevel: .advanced
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya makan pisang dengan susu dan cangkir kecil.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
    }

    func testOpenAIServiceDoesNotRejectUnknownKeywordTranslationGrounding() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya mencuci piring kecil.",
                    mainSentenceJP: "私は小さい皿を洗います。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "mencuci", jp: "洗う"),
                        VocabularyItem(id: "piring", jp: "皿"),
                        VocabularyItem(id: "kecil", jp: "小さい"),
                    ],
                    grammarNote: "Saya + 動詞 = 私は〜します。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu mencuci apa?", jp: "何を洗いますか。"),
                        ConversationLine(speaker: "B", id: "Saya mencuci piring.", jp: "私は皿を洗います。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Ini piring kecil.", jp: "これは小さい皿です。"),
                        SimilarExpression(id: "Saya melihat piring.", jp: "私は皿を見ます。"),
                        SimilarExpression(id: "Piring ini kecil.", jp: "この皿は小さいです。"),
                    ],
                    usedKeywords: ["piring"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "09:00",
            dayText: "Tuesday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "plate", confidence: 1, role: .foreground),
            ],
            userNote: "",
            languageLevel: .beginner
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya mencuci piring kecil.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
    }

    func testOpenAIServiceAcceptsAnyGroundedForegroundKeywordWhenSeveralExist() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya melihat dokumen kecil.",
                    mainSentenceJP: "私は小さい書類を見ています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "melihat", jp: "見る"),
                        VocabularyItem(id: "dokumen", jp: "書類"),
                        VocabularyItem(id: "kecil", jp: "小さい"),
                    ],
                    grammarNote: "Saya + 動詞 = 私は〜します。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu melihat apa?", jp: "何を見ていますか。"),
                        ConversationLine(speaker: "B", id: "Saya melihat dokumen.", jp: "私は書類を見ています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Ini dokumen kecil.", jp: "これは小さい書類です。"),
                        SimilarExpression(id: "Saya membaca dokumen.", jp: "私は書類を読みます。"),
                        SimilarExpression(id: "Dokumen ini penting.", jp: "この書類は大事です。"),
                    ],
                    usedKeywords: ["document"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "09:00",
            dayText: "Tuesday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "keyboard", confidence: 0.9, role: .foreground),
                ImageKeyword(label: "document", confidence: 0.8, role: .foreground),
            ],
            userNote: "",
            languageLevel: .beginner
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya melihat dokumen kecil.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
    }

    func testOpenAIServiceAcceptsTranslatedContainerForegroundGrounding() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Sepertinya saya menaruh teko air kuning, toples kecil, dan botol di atas meja dekat jendela sebelum mulai merapikan kamar pagi ini.",
                    mainSentenceJP: "どうやら私は今朝、部屋を片づけ始める前に、黄色い水差し、小さな保存容器、ボトルを窓の近くの机の上に置いたようです。",
                    vocabulary: [
                        VocabularyItem(id: "sepertinya", jp: "どうやら"),
                        VocabularyItem(id: "menaruh", jp: "置く"),
                        VocabularyItem(id: "teko air", jp: "水差し"),
                        VocabularyItem(id: "toples", jp: "保存容器"),
                        VocabularyItem(id: "botol", jp: "ボトル"),
                        VocabularyItem(id: "di atas", jp: "〜の上に"),
                        VocabularyItem(id: "jendela", jp: "窓"),
                    ],
                    grammarNote: "sepertinya は断定を避ける推量表現で、sebelum は「〜する前に」を表します。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu menaruh apa di meja?", jp: "机の上に何を置いたの？"),
                        ConversationLine(speaker: "B", id: "Saya menaruh teko air dan botol.", jp: "水差しとボトルを置きました。"),
                        ConversationLine(speaker: "A", id: "Mau merapikan kamar?", jp: "部屋を片づけるの？"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Teko air ada di atas meja.", jp: "水差しは机の上にあります。"),
                        SimilarExpression(id: "Saya menaruh botol dekat jendela.", jp: "私は窓の近くにボトルを置きます。"),
                        SimilarExpression(id: "Toples kecil itu kuning.", jp: "その小さな保存容器は黄色です。"),
                    ],
                    usedKeywords: ["teko air", "toples"]
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "09:22",
            dayText: "Friday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "water jug", confidence: 0.78, role: .foreground),
                ImageKeyword(label: "jar", confidence: 0.69, role: .foreground),
                ImageKeyword(label: "bottle", confidence: 0.63, role: .foreground),
                ImageKeyword(label: "window", confidence: 0.42, role: .context),
                ImageKeyword(label: "curtain", confidence: 0.38, role: .context),
            ],
            userNote: "",
            languageLevel: .advanced
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.vocabulary.count, 7)
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
    }

    func testOpenAIServiceDoesNotForceManualMisspelledKeyword() async throws {
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(
                for: GeneratedLessonPayload(
                    mainSentenceID: "Saya melihat benda kecil.",
                    mainSentenceJP: "私は小さい物を見ています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "melihat", jp: "見る"),
                        VocabularyItem(id: "benda", jp: "物"),
                        VocabularyItem(id: "kecil", jp: "小さい"),
                    ],
                    grammarNote: "Saya + 動詞 = 私は〜します。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu melihat apa?", jp: "何を見ていますか。"),
                        ConversationLine(speaker: "B", id: "Saya melihat benda kecil.", jp: "小さい物を見ています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Ini benda kecil.", jp: "これは小さい物です。"),
                        SimilarExpression(id: "Saya melihat ini.", jp: "私はこれを見ています。"),
                        SimilarExpression(id: "Benda ini kecil.", jp: "この物は小さいです。"),
                    ],
                    usedKeywords: []
                )
            ),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "12:21",
            dayText: "Friday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "botttle", confidence: 0.5, role: .foreground, source: .manual),
            ],
            userNote: "",
            languageLevel: .beginner
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, "Saya melihat benda kecil.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
    }

    func testOpenAIServiceAcceptsEnglishTargetWithoutIndonesianRepair() async throws {
        let payload = GeneratedLessonPayload(
            mainSentenceID: "I carry a bottle while walking through the park with friends.",
            mainSentenceJP: "私は友人たちと公園を歩きながらボトルを持ち運びます。",
            mainSentenceWordCount: 11,
            vocabulary: [
                VocabularyItem(id: "carry", jp: "持ち運ぶ"),
                VocabularyItem(id: "bottle", jp: "ボトル"),
                VocabularyItem(id: "while", jp: "〜しながら"),
                VocabularyItem(id: "walking", jp: "歩いている"),
                VocabularyItem(id: "park", jp: "公園"),
            ],
            grammarNote: "while + 動名詞で、二つの動作が同時に進むことを表します。",
            conversation: [
                ConversationLine(speaker: "A", id: "Where are you going?", jp: "どこへ行くのですか。"),
                ConversationLine(speaker: "B", id: "I am walking through the park.", jp: "公園を歩いています。"),
            ],
            similarExpressions: [
                SimilarExpression(id: "I am carrying a water bottle.", jp: "水筒を持っています。"),
                SimilarExpression(id: "We are walking in the park.", jp: "私たちは公園を歩いています。"),
                SimilarExpression(id: "I brought a drink for my walk.", jp: "散歩用の飲み物を持ってきました。"),
            ],
            usedKeywords: ["bottle"]
        )
        OpenAILessonServiceMockURLProtocol.responseBodies = [
            try openAIResponseBody(for: payload),
        ]
        OpenAILessonServiceMockURLProtocol.requestBodies = []
        defer {
            OpenAILessonServiceMockURLProtocol.responseBodies = []
            OpenAILessonServiceMockURLProtocol.requestBodies = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAILessonServiceMockURLProtocol.self]
        let service = OpenAILessonService(session: URLSession(configuration: configuration))
        let context = SceneContext(
            timeText: "15:20",
            dayText: "Saturday",
            locationLabel: .unknown,
            imageKeywords: [
                ImageKeyword(label: "bottle", confidence: 0.93, role: .foreground),
                ImageKeyword(label: "bench", confidence: 0.77, role: .surface),
            ],
            languageLevel: .intermediate,
            lessonLanguage: .english,
            lessonSituation: .park
        )

        let lesson = try await service.generateLesson(
            from: context,
            apiKey: "test-key",
            model: "gpt-test"
        )

        XCTAssertEqual(lesson.mainSentenceID, payload.mainSentenceID)
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 1)
        let requestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.first)
        let requestBody = String(decoding: requestData, as: UTF8.self)
        XCTAssertTrue(requestBody.contains("english_lesson"))
        XCTAssertTrue(requestBody.contains("One complete English sentence"))
        XCTAssertTrue(requestBody.contains("lesson_language"))
        XCTAssertTrue(requestBody.contains("in a park"))
        XCTAssertFalse(requestBody.contains("untranslated image keywords"))
    }

    @MainActor
    func testForegroundNotificationPromptCanOpenCamera() {
        let handler = NotificationLaunchHandler.shared
        handler.consumeCameraLaunchRequest()
        handler.dismissForegroundPrompt()

        handler.presentForegroundPrompt(title: "DailyLang", body: "テスト通知です。")
        XCTAssertNotNil(handler.foregroundPrompt)
        XCTAssertFalse(handler.shouldOpenCamera)

        handler.openCameraFromForegroundPrompt()
        XCTAssertNil(handler.foregroundPrompt)
        XCTAssertTrue(handler.shouldOpenCamera)

        handler.consumeCameraLaunchRequest()
    }

    @MainActor
    func testLessonRecordVocabularyHidesItemsNotUsedInMainSentence() throws {
        let record = try makeRecord(
            mainSentenceID: "Sepertinya sore ini masih enak buat santai di luar rumah sambil lihat motor-motor lewat.",
            mainSentenceJP: "どうやら夕方は外でのんびりしながらバイクを見るのにまだよさそうです。"
        )
        record.vocabularyJSON = try StoredJSONCoding.encode([
            VocabularyItem(id: "motorbike", jp: "バイク、オートバイ"),
            VocabularyItem(id: "luar rumah", jp: "外、屋外"),
            VocabularyItem(id: "langit biru", jp: "青空"),
            VocabularyItem(id: "gerbang lengkung", jp: "門、アーチ状の入口"),
            VocabularyItem(id: "depan bangunan", jp: "建物の前面、店先"),
            VocabularyItem(id: "sepertinya", jp: "たぶん、どうやら"),
            VocabularyItem(id: "sekalian", jp: "ついでに、合わせて"),
        ])

        XCTAssertEqual(record.vocabulary.map(\.id), ["luar rumah", "sepertinya"])
    }

    @MainActor
    func testDeviceDiagnosticsReportsStoredLessonsAndRoundTripFromProvidedContext() async throws {
        let modelContext = try makeInMemoryModelContext()
        let record = try makeRecord()
        try LessonRecordPersistence.insertAndSave(record, in: modelContext)

        let service = DeviceDiagnosticsService(userDefaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let items = await service.loadItems(modelContext: modelContext)

        let storedLessons = try XCTUnwrap(items.first { $0.id == "stored-lessons" })
        XCTAssertReady(storedLessons)
        XCTAssertTrue(storedLessons.detail.contains("1件"))
        XCTAssertTrue(storedLessons.detail.contains("表示対象 1件"))
        XCTAssertTrue(storedLessons.detail.contains("Saya sedang makan pisang."))

        let homeReviewVisibility = try XCTUnwrap(items.first { $0.id == "home-review-visibility" })
        XCTAssertReady(homeReviewVisibility)
        XCTAssertTrue(homeReviewVisibility.detail.contains("Home最新とReview対象: 1件"))
        XCTAssertTrue(homeReviewVisibility.detail.contains("私はバナナを食べているところです。"))

        let roundTrip = try XCTUnwrap(items.first { $0.id == "save-roundtrip" })
        XCTAssertReady(roundTrip)

        let savedRecords = try LessonRecordPersistence.fetchSavedRecords(in: modelContext)
        XCTAssertEqual(savedRecords.map(\.id), [record.id])
    }

    @MainActor
    private func makeInMemoryModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: LessonRecord.self, VocabularyStudyRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func removeStoreFiles(at storeURL: URL) {
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
    }

    private func XCTAssertReady(
        _ item: DeviceDiagnosticItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .ready = item.status {
            return
        }
        XCTFail("Expected \(item.id) to be ready, got \(item.status)", file: file, line: line)
    }

    private func makeRecord(
        mainSentenceID: String = "Saya sedang makan pisang.",
        mainSentenceJP: String = "私はバナナを食べているところです。"
    ) throws -> LessonRecord {
        let context = SceneContext(
            timeText: "13:59",
            dayText: "Sunday",
            locationLabel: .home,
            imageKeywords: [
                ImageKeyword(label: "banana", confidence: 0.94, count: 3),
                ImageKeyword(label: "cup", confidence: 0.72),
                ImageKeyword(label: "bottle", confidence: 0.68),
            ],
            userNote: "",
            languageLevel: .beginner
        )
        let lesson = Lesson(
            mainSentenceID: mainSentenceID,
            mainSentenceJP: mainSentenceJP,
            vocabulary: [
                VocabularyItem(id: "saya", jp: "私"),
                VocabularyItem(id: "sedang", jp: "〜している"),
                VocabularyItem(id: "makan", jp: "食べる"),
                VocabularyItem(id: "pisang", jp: "バナナ"),
            ],
            grammarNote: "sedang + 動詞 = 今〜している。",
            conversation: [
                ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                ConversationLine(speaker: "B", id: "Saya sedang makan pisang.", jp: "私はバナナを食べているところです。"),
            ],
            similarExpressions: [
                SimilarExpression(id: "Saya mau makan pisang.", jp: "私はバナナを食べたいです。"),
                SimilarExpression(id: "Ini pisang saya.", jp: "これは私のバナナです。"),
                SimilarExpression(id: "Pisang ini enak.", jp: "このバナナはおいしいです。"),
            ],
            source: .openAI
        )
        return try LessonRecord(context: context, lesson: lesson, photoLocalPath: nil)
    }

    private func openAIResponseBody(for payload: GeneratedLessonPayload) throws -> Data {
        let payloadData = try JSONEncoder().encode(payload)
        let payloadText = String(decoding: payloadData, as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["output_text": payloadText])
    }
}

private final class OpenAILessonServiceMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBodies: [Data] = []
    nonisolated(unsafe) static var requestBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestBodies.append(Self.bodyData(from: request))

        guard !Self.responseBodies.isEmpty,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let body = Self.responseBodies.removeFirst()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let bodyStream = request.httpBodyStream else {
            return Data()
        }

        bodyStream.open()
        defer {
            bodyStream.close()
        }

        var data = Data()
        let bufferSize = 1_024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while bodyStream.hasBytesAvailable {
            let count = bodyStream.read(&buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}

final class NotificationSchedulerTests: XCTestCase {
    @MainActor
    func testRandomPromptPlanSchedulesTodayThroughNextThreeDays() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 8, minute: 0)
        var nextOffset = 0

        let dates = NotificationScheduler.makeRandomPromptDates(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 3,
            randomOffset: { upperBound in
                defer { nextOffset += 1_800 }
                return nextOffset % upperBound
            }
        )

        XCTAssertEqual(dates.count, 12)

        let groupedByDay = Dictionary(grouping: dates) { date in
            calendar.startOfDay(for: date)
        }
        XCTAssertEqual(groupedByDay.count, 4)
        XCTAssertTrue(groupedByDay.values.allSatisfy { $0.count == 3 })

        let firstDay = calendar.startOfDay(for: now)
        let lastDay = try! XCTUnwrap(groupedByDay.keys.max())
        XCTAssertEqual(calendar.dateComponents([.day], from: firstDay, to: lastDay).day, 3)

        for date in dates {
            let hour = calendar.component(.hour, from: date)
            XCTAssertGreaterThanOrEqual(hour, 9)
            XCTAssertLessThan(hour, 21)
        }
    }

    @MainActor
    func testRandomPromptPlanSkipsPastTimesOnCurrentDay() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 10, minute: 30)
        var nextOffset = 0

        let dates = NotificationScheduler.makeRandomPromptDates(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 3,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            randomOffset: { upperBound in
                defer { nextOffset += 3_600 }
                return nextOffset % upperBound
            }
        )

        XCTAssertEqual(dates.count, 12)
        XCTAssertFalse(dates.contains { date in
            calendar.isDate(date, inSameDayAs: now) && date.timeIntervalSince(now) < NotificationScheduler.minimumPromptLeadTimeSeconds
        })
    }

    @MainActor
    func testRandomPromptPlanSkipsNearImmediateDatesWhenSchedulingNotifications() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 9, minute: 0)
        let offsets = [30, 120, 180]
        var index = 0

        let dates = NotificationScheduler.makeRandomPromptDates(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 3,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            randomOffset: { _ in
                defer { index += 1 }
                return offsets[index % offsets.count]
            }
        )

        XCTAssertFalse(dates.contains { $0.timeIntervalSince(now) < NotificationScheduler.minimumPromptLeadTimeSeconds })
        XCTAssertEqual(dates.count, 12)
    }

    @MainActor
    func testRandomPromptPlanKeepsTodayCountAfterSelectedEndHour() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 22, minute: 0)
        var nextOffset = 0

        let dates = NotificationScheduler.makeRandomPromptDates(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 4,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            randomOffset: { upperBound in
                defer { nextOffset += 600 }
                return nextOffset % upperBound
            }
        )

        XCTAssertEqual(dates.count, 16)

        let todayDates = dates.filter { calendar.isDate($0, inSameDayAs: now) }
        XCTAssertEqual(todayDates.count, 4)
        XCTAssertTrue(todayDates.allSatisfy { $0.timeIntervalSince(now) >= NotificationScheduler.minimumPromptLeadTimeSeconds })
    }

    @MainActor
    func testRandomPromptPlanDoesNotClusterTodayNearEndHour() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 20, minute: 58)
        var nextOffset = 0

        let dates = NotificationScheduler.makeRandomPromptDates(
            now: now,
            calendar: calendar,
            startHour: 7,
            endHour: 21,
            countPerDay: 5,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            randomOffset: { upperBound in
                defer { nextOffset += 1_800 }
                return nextOffset % upperBound
            }
        )

        let todayDates = dates.filter { calendar.isDate($0, inSameDayAs: now) }
        XCTAssertEqual(todayDates.count, 5)
        XCTAssertGreaterThan(
            todayDates.last!.timeIntervalSince(todayDates.first!),
            NotificationScheduler.minimumTodaySchedulingWindowSeconds
        )
    }

    @MainActor
    func testTriggerDateComponentsKeepSecondsAndTimeZone() {
        let calendar = fixedCalendar()
        let date = makeDate(calendar: calendar, day: 28, hour: 14, minute: 5, second: 37)

        let components = NotificationScheduler.makeTriggerDateComponents(for: date, calendar: calendar)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 28)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 5)
        XCTAssertEqual(components.second, 37)
        XCTAssertEqual(components.timeZone, calendar.timeZone)
    }

    @MainActor
    func testNextTriggerDateSupportsCalendarAndTestIntervalTriggers() throws {
        let calendar = fixedCalendar()
        let futureDate = Date().addingTimeInterval(3_600)
        let calendarComponents = NotificationScheduler.makeTriggerDateComponents(
            for: futureDate,
            calendar: calendar
        )
        let calendarRequest = UNNotificationRequest(
            identifier: "calendar-test",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: calendarComponents, repeats: false)
        )
        let intervalRequest = UNNotificationRequest(
            identifier: NotificationScheduler.testPromptIdentifier,
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: NotificationScheduler.testPromptDelaySeconds, repeats: false)
        )

        let calendarNextDate = try XCTUnwrap(NotificationScheduler.nextTriggerDate(from: calendarRequest))
        XCTAssertLessThan(abs(calendarNextDate.timeIntervalSince(futureDate)), 1)
        XCTAssertNotNil(NotificationScheduler.nextTriggerDate(from: intervalRequest))
    }

    @MainActor
    func testTestPromptIdentifierIsClassifiedSeparately() {
        let testRequest = UNNotificationRequest(
            identifier: NotificationScheduler.testPromptIdentifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let randomRequest = UNNotificationRequest(
            identifier: "\(NotificationScheduler.scheduledPromptIdentifierPrefix)-123",
            content: UNMutableNotificationContent(),
            trigger: nil
        )

        XCTAssertTrue(NotificationScheduler.isTestPrompt(testRequest))
        XCTAssertFalse(NotificationScheduler.isTestPrompt(randomRequest))
    }

    @MainActor
    func testNotificationSnapshotClassifiesPendingNotificationKinds() throws {
        let calendar = fixedCalendar()
        let randomDate = Date().addingTimeInterval(3_600)
        let randomRequest = UNNotificationRequest(
            identifier: "\(NotificationScheduler.scheduledPromptIdentifierPrefix)-test",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: NotificationScheduler.makeTriggerDateComponents(for: randomDate, calendar: calendar),
                repeats: false
            )
        )
        let testRequest = UNNotificationRequest(
            identifier: NotificationScheduler.testPromptIdentifier,
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: NotificationScheduler.testPromptDelaySeconds,
                repeats: false
            )
        )
        let unrelatedRequest = UNNotificationRequest(
            identifier: "other",
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )

        let randomSnapshot = try XCTUnwrap(NotificationScheduler.notificationSnapshot(from: randomRequest))
        let testSnapshot = try XCTUnwrap(NotificationScheduler.notificationSnapshot(from: testRequest))

        XCTAssertEqual(randomSnapshot.kind, .randomPrompt)
        XCTAssertEqual(testSnapshot.kind, .testPrompt)
        XCTAssertNil(NotificationScheduler.notificationSnapshot(from: unrelatedRequest))
    }

    @MainActor
    func testRandomPromptPlanFallsBackWhenRandomOffsetsCollide() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 8, minute: 0)

        let dates = NotificationScheduler.makeRandomPromptDates(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 3,
            randomOffset: { _ in 0 }
        )

        XCTAssertEqual(dates.count, 12)
        XCTAssertEqual(Set(dates).count, 12)
    }

    @MainActor
    func testRefreshDecisionKeepsPendingNotificationsAboveTwoDays() {
        XCTAssertTrue(NotificationScheduler.shouldRefreshRandomPrompts(pendingPromptCount: 5, countPerDay: 3))
        XCTAssertFalse(NotificationScheduler.shouldRefreshRandomPrompts(pendingPromptCount: 6, countPerDay: 3))
        XCTAssertTrue(NotificationScheduler.shouldRefreshRandomPrompts(pendingPromptCount: 19, countPerDay: 100))
        XCTAssertFalse(NotificationScheduler.shouldRefreshRandomPrompts(pendingPromptCount: 20, countPerDay: 100))
    }

    @MainActor
    func testScheduleSummaryReportsVerifiedCounts() {
        let summary = NotificationScheduleSummary(
            requestCount: 20,
            futureDayCount: NotificationScheduler.futureDaysToSchedule,
            todayCount: 5,
            addedCount: 4,
            removedCount: 0
        )

        XCTAssertTrue(summary.statusMessage.contains("通知 20件を確認しました"))
        XCTAssertTrue(summary.statusMessage.contains("今日 5件"))
        XCTAssertTrue(summary.statusMessage.contains("追加 4件"))
    }

    @MainActor
    func testSchedulePlanAddsOnlyOnePromptPerDayWhenCountIncreasesFromThreeToFour() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 8, minute: 0)
        let existingPrompts = makeExistingPrompts(
            calendar: calendar,
            now: now,
            countPerDay: 3
        )

        let plan = NotificationScheduler.makeSchedulePlan(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 4,
            existingPrompts: existingPrompts,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            randomOffset: { _ in 7_200 }
        )

        XCTAssertEqual(plan.datesToAdd.count, 4)
        XCTAssertTrue(plan.identifiersToRemove.isEmpty)
        XCTAssertEqual(plan.finalRequestCount, 16)

        let addedByDay = Dictionary(grouping: plan.datesToAdd) { date in
            calendar.startOfDay(for: date)
        }
        XCTAssertEqual(addedByDay.count, 4)
        XCTAssertTrue(addedByDay.values.allSatisfy { $0.count == 1 })
    }

    @MainActor
    func testAutomaticRefreshDoesNotReplenishDeliveredTodayPrompt() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 8, minute: 0)
        let existingPrompts = makeExistingPrompts(
            calendar: calendar,
            now: now,
            countPerDay: 4
        ).filter { prompt in
            !(calendar.isDate(prompt.nextTriggerDate, inSameDayAs: now)
                && calendar.component(.hour, from: prompt.nextTriggerDate) == 9)
        }

        let plan = NotificationScheduler.makeSchedulePlan(
            now: now,
            calendar: calendar,
            startHour: 7,
            endHour: 21,
            countPerDay: 4,
            existingPrompts: existingPrompts,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            replenishToday: false,
            randomOffset: { _ in 7_200 }
        )

        XCTAssertTrue(plan.datesToAdd.isEmpty)
        XCTAssertTrue(plan.identifiersToRemove.isEmpty)
        XCTAssertEqual(plan.finalRequestCount, 15)
    }

    @MainActor
    func testManualScheduleStillReplenishesTodayWhenUserRequestsIt() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 8, minute: 0)
        let existingPrompts = makeExistingPrompts(
            calendar: calendar,
            now: now,
            countPerDay: 4
        ).filter { prompt in
            !(calendar.isDate(prompt.nextTriggerDate, inSameDayAs: now)
                && calendar.component(.hour, from: prompt.nextTriggerDate) == 9)
        }

        let plan = NotificationScheduler.makeSchedulePlan(
            now: now,
            calendar: calendar,
            startHour: 7,
            endHour: 21,
            countPerDay: 4,
            existingPrompts: existingPrompts,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            replenishToday: true,
            randomOffset: { _ in 7_200 }
        )

        XCTAssertEqual(plan.datesToAdd.count, 1)
        XCTAssertTrue(calendar.isDate(plan.datesToAdd[0], inSameDayAs: now))
        XCTAssertTrue(plan.identifiersToRemove.isEmpty)
        XCTAssertEqual(plan.finalRequestCount, 16)
    }

    @MainActor
    func testSchedulePlanDoesNotDuplicateWhenCountsAlreadyMatch() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 8, minute: 0)
        let existingPrompts = makeExistingPrompts(
            calendar: calendar,
            now: now,
            countPerDay: 4
        )

        let plan = NotificationScheduler.makeSchedulePlan(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 4,
            existingPrompts: existingPrompts,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            randomOffset: { _ in 7_200 }
        )

        XCTAssertTrue(plan.datesToAdd.isEmpty)
        XCTAssertTrue(plan.identifiersToRemove.isEmpty)
        XCTAssertEqual(plan.finalRequestCount, 16)
    }

    @MainActor
    func testSchedulePlanRemovesOnlyOverflowWhenCountDecreases() {
        let calendar = fixedCalendar()
        let now = makeDate(calendar: calendar, day: 28, hour: 8, minute: 0)
        let existingPrompts = makeExistingPrompts(
            calendar: calendar,
            now: now,
            countPerDay: 4
        )

        let plan = NotificationScheduler.makeSchedulePlan(
            now: now,
            calendar: calendar,
            startHour: 9,
            endHour: 21,
            countPerDay: 3,
            existingPrompts: existingPrompts,
            minimumLeadTime: NotificationScheduler.minimumPromptLeadTimeSeconds,
            randomOffset: { _ in 7_200 }
        )

        XCTAssertTrue(plan.datesToAdd.isEmpty)
        XCTAssertEqual(plan.identifiersToRemove.count, 4)
        XCTAssertEqual(plan.finalRequestCount, 12)
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(calendar: Calendar, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 6
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    @MainActor
    private func makeExistingPrompts(
        calendar: Calendar,
        now: Date,
        countPerDay: Int
    ) -> [ScheduledPromptSnapshot] {
        (0...NotificationScheduler.futureDaysToSchedule).flatMap { dayOffset in
            (0..<countPerDay).map { promptIndex in
                let date = calendar.date(
                    byAdding: DateComponents(day: dayOffset, hour: promptIndex + 9),
                    to: calendar.startOfDay(for: now)
                )!
                return ScheduledPromptSnapshot(
                    identifier: "existing-\(dayOffset)-\(promptIndex)",
                    nextTriggerDate: date
                )
            }
        }
    }
}
