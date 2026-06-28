import SwiftData
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
    func testDeviceDiagnosticsReportsStoredLessonsAndRoundTripFromProvidedContext() async throws {
        let modelContext = try makeInMemoryModelContext()
        let record = try makeRecord()
        try LessonRecordPersistence.insertAndSave(record, in: modelContext)

        let service = DeviceDiagnosticsService(userDefaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let items = await service.loadItems(modelContext: modelContext)

        let storedLessons = try XCTUnwrap(items.first { $0.id == "stored-lessons" })
        XCTAssertReady(storedLessons)
        XCTAssertTrue(storedLessons.detail.contains("1件"))
        XCTAssertTrue(storedLessons.detail.contains("Saya sedang makan pisang."))

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
            randomOffset: { upperBound in
                defer { nextOffset += 3_600 }
                return nextOffset % upperBound
            }
        )

        XCTAssertEqual(dates.count, 10)
        XCTAssertFalse(dates.contains { date in
            calendar.isDate(date, inSameDayAs: now) && calendar.component(.hour, from: date) < 11
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

        XCTAssertFalse(dates.contains { $0.timeIntervalSince(now) <= NotificationScheduler.minimumPromptLeadTimeSeconds })
        XCTAssertEqual(dates.count, 11)
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
}
