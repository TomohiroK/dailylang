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
        XCTAssertEqual(AppLaunchArgument.scheduleRandomNotifications, "-DailyLangScheduleRandomNotifications")
        XCTAssertEqual(AppLaunchArgument.scheduleTestNotification, "-DailyLangScheduleTestNotification")
        XCTAssertEqual(AppLaunchArgument.showNotificationTimes, "-DailyLangShowNotificationTimes")
        XCTAssertEqual(AppLaunchArgument.hideNotificationTimes, "-DailyLangHideNotificationTimes")
        XCTAssertEqual(AppLaunchArgument.exportDiagnostics, "-DailyLangExportDiagnostics")
    }

    func testDailyLangNotificationCategoryRoutesToCamera() {
        XCTAssertTrue(NotificationCategory.shouldOpenCamera(for: NotificationCategory.captureScene))
        XCTAssertFalse(NotificationCategory.shouldOpenCamera(for: "OTHER"))
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
                    mainSentenceID: "Saya makan pisang di meja sambil minum susu.",
                    mainSentenceJP: "私はテーブルで牛乳を飲みながらバナナを食べています。",
                    vocabulary: [
                        VocabularyItem(id: "saya", jp: "私"),
                        VocabularyItem(id: "makan", jp: "食べる"),
                        VocabularyItem(id: "pisang", jp: "バナナ"),
                        VocabularyItem(id: "meja", jp: "テーブル"),
                        VocabularyItem(id: "susu", jp: "牛乳"),
                    ],
                    grammarNote: "sambil + 動詞 = 〜しながら。",
                    conversation: [
                        ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                        ConversationLine(speaker: "B", id: "Saya makan pisang.", jp: "バナナを食べています。"),
                    ],
                    similarExpressions: [
                        SimilarExpression(id: "Saya minum susu.", jp: "私は牛乳を飲みます。"),
                        SimilarExpression(id: "Pisang ini manis.", jp: "このバナナは甘いです。"),
                        SimilarExpression(id: "Saya makan di meja.", jp: "私はテーブルで食べます。"),
                    ]
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

        XCTAssertEqual(lesson.mainSentenceID, "Saya makan pisang di meja sambil minum susu.")
        XCTAssertEqual(OpenAILessonServiceMockURLProtocol.requestBodies.count, 2)
        let secondRequestData = try XCTUnwrap(OpenAILessonServiceMockURLProtocol.requestBodies.dropFirst().first)
        let secondRequestBody = String(decoding: secondRequestData, as: UTF8.self)
        XCTAssertTrue(secondRequestBody.contains("previous response was invalid"))
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
                    ]
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
                    ]
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
                ImageKeyword(label: "table", confidence: 0.74),
                ImageKeyword(label: "bottle", confidence: 0.68),
            ],
            userNote: "",
            languageLevel: .advanced
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
        XCTAssertTrue(secondRequestBody.contains("main_sentence_jp was not Japanese"))
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
            for: LessonRecord.self,
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
