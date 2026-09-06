import Foundation
import UserNotifications

enum NotificationIdentifier {
    static let scheduledPromptIdentifierPrefix = "daily-lang-random-prompt"
    static let testPromptIdentifier = "daily-lang-test-prompt"
}

enum NotificationSchedulerError: LocalizedError {
    case invalidTimeRange
    case authorizationDenied
    case testNotificationNotScheduled
    case scheduledPromptVerificationFailed(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            "通知の開始時刻は終了時刻より前にしてください。"
        case .authorizationDenied:
            "通知が許可されていません。設定アプリで通知を許可してください。"
        case .testNotificationNotScheduled:
            "テスト通知の予約を確認できませんでした。通知設定を確認してもう一度試してください。"
        case .scheduledPromptVerificationFailed(let expected, let actual):
            "通知予約後の確認に失敗しました。予定 \(expected)件 / 実際 \(actual)件。"
        }
    }
}

@MainActor
struct NotificationScheduleSummary: Sendable {
    let requestCount: Int
    let futureDayCount: Int
    let todayCount: Int
    let addedCount: Int
    let removedCount: Int

    var statusMessage: String {
        "通知 \(requestCount)件を確認しました。今日 \(todayCount)件 / 今日から\(futureDayCount)日先まで。追加 \(addedCount)件 / 削除 \(removedCount)件。"
    }
}

struct ScheduledPromptSnapshot: Equatable, Sendable {
    var identifier: String
    var nextTriggerDate: Date
}

struct NotificationSchedulePlan: Equatable, Sendable {
    var datesToAdd: [Date]
    var identifiersToRemove: [String]
    var finalRequestCount: Int
}

enum ScheduledNotificationKind: String, Sendable {
    case randomPrompt
    case testPrompt

    var japaneseName: String {
        switch self {
        case .randomPrompt:
            "ランダム"
        case .testPrompt:
            "テスト"
        }
    }
}

struct ScheduledNotificationSnapshot: Equatable, Identifiable, Sendable {
    var identifier: String
    var nextTriggerDate: Date
    var kind: ScheduledNotificationKind

    var id: String { identifier }
}

@MainActor
struct NotificationScheduler {
    static let scheduledPromptIdentifierPrefix = NotificationIdentifier.scheduledPromptIdentifierPrefix
    static let testPromptIdentifier = NotificationIdentifier.testPromptIdentifier
    static let futureDaysToSchedule = 3
    static let minimumPromptLeadTimeSeconds: TimeInterval = 60
    static let testPromptDelaySeconds: TimeInterval = 5
    static let minimumTodaySchedulingWindowSeconds: TimeInterval = 3_600
    private static let maxNotificationsPerDay = 10
    private static let minimumPendingDays = 2
    private static let promptBodies = [
        "今何してる？写真を撮ってレッスンにしよう",
        "今の場面を教材にしましょう",
        "いまの一枚から、使える例文を作ろう",
    ]

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current
    ) {
        self.center = center
        self.calendar = calendar
    }

    func scheduleRandomPrompts(
        startHour: Int,
        endHour: Int,
        countPerDay: Int
    ) async throws -> NotificationScheduleSummary {
        guard startHour < endHour else {
            throw NotificationSchedulerError.invalidTimeRange
        }

        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else {
            throw NotificationSchedulerError.authorizationDenied
        }

        return try await reconcileScheduledPrompts(
            startHour: startHour,
            endHour: endHour,
            countPerDay: countPerDay
        )
    }

    func scheduleTestPrompt() async throws {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else {
            throw NotificationSchedulerError.authorizationDenied
        }

        center.removePendingNotificationRequests(withIdentifiers: [Self.testPromptIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "DailyLang"
        content.body = "テスト通知です。タップして撮影画面を開きましょう"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.captureScene

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.testPromptDelaySeconds,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.testPromptIdentifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)

        let pendingTestRequestExists = await center.pendingNotificationRequests()
            .contains(where: Self.isTestPrompt)
        guard pendingTestRequestExists else {
            throw NotificationSchedulerError.testNotificationNotScheduled
        }
    }

    func refreshRandomPromptsIfAuthorized(
        startHour: Int,
        endHour: Int,
        countPerDay: Int
    ) async throws {
        guard startHour < endHour else {
            throw NotificationSchedulerError.invalidTimeRange
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus.allowsScheduling else {
            return
        }

        _ = try await reconcileScheduledPrompts(
            startHour: startHour,
            endHour: endHour,
            countPerDay: countPerDay,
            replenishToday: false
        )
    }

    func scheduledNotificationSnapshots() async -> [ScheduledNotificationSnapshot] {
        await center.pendingNotificationRequests()
            .compactMap(Self.notificationSnapshot(from:))
            .sorted { $0.nextTriggerDate < $1.nextTriggerDate }
    }

    func clearDeliveredDailyLangNotifications() async {
        let identifiers = await center.deliveredNotifications()
            .map(\.request)
            .filter(NotificationCategory.shouldOpenCamera(for:))
            .map(\.identifier)

        guard !identifiers.isEmpty else {
            return
        }

        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func reconcileScheduledPrompts(
        startHour: Int,
        endHour: Int,
        countPerDay: Int,
        replenishToday: Bool = true
    ) async throws -> NotificationScheduleSummary {
        let now = Date()
        let pendingPromptRequests = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.scheduledPromptIdentifierPrefix) }
        let existingPrompts = pendingPromptRequests.compactMap(Self.promptSnapshot(from:))
        let invalidIdentifiers = pendingPromptRequests
            .filter { Self.promptSnapshot(from: $0) == nil }
            .map(\.identifier)
        let plan = Self.makeSchedulePlan(
            now: now,
            calendar: calendar,
            startHour: startHour,
            endHour: endHour,
            countPerDay: countPerDay,
            existingPrompts: existingPrompts,
            minimumLeadTime: Self.minimumPromptLeadTimeSeconds,
            replenishToday: replenishToday
        )

        let identifiersToRemove = invalidIdentifiers + plan.identifiersToRemove
        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }

        for (index, date) in plan.datesToAdd.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "DailyLang"
            content.body = Self.promptBodies[index % Self.promptBodies.count]
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.captureScene

            let components = Self.makeTriggerDateComponents(for: date, calendar: calendar)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.makePromptIdentifier(for: date, index: index),
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }

        let verifiedPrompts = await verifiedPromptSnapshots(now: now)
        guard verifiedPrompts.count == plan.finalRequestCount else {
            throw NotificationSchedulerError.scheduledPromptVerificationFailed(
                expected: plan.finalRequestCount,
                actual: verifiedPrompts.count
            )
        }

        return NotificationScheduleSummary(
            requestCount: verifiedPrompts.count,
            futureDayCount: Self.futureDaysToSchedule,
            todayCount: verifiedPrompts.filter {
                calendar.isDate($0.nextTriggerDate, inSameDayAs: now)
            }.count,
            addedCount: plan.datesToAdd.count,
            removedCount: identifiersToRemove.count
        )
    }

    static func shouldRefreshRandomPrompts(
        pendingPromptCount: Int,
        countPerDay: Int
    ) -> Bool {
        pendingPromptCount < safeNotificationCount(countPerDay) * minimumPendingDays
    }

    static func makeSchedulePlan(
        now: Date,
        calendar: Calendar,
        startHour: Int,
        endHour: Int,
        countPerDay: Int,
        existingPrompts: [ScheduledPromptSnapshot],
        minimumLeadTime: TimeInterval = 0,
        replenishToday: Bool = true,
        randomOffset: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) -> NotificationSchedulePlan {
        let safeCount = safeNotificationCount(countPerDay)
        let minimumDate = now.addingTimeInterval(minimumLeadTime)
        let todayStart = calendar.startOfDay(for: now)
        let targetDays = (0...Self.futureDaysToSchedule).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: now)
        }
        let targetDayStarts = Set(targetDays.map { calendar.startOfDay(for: $0) })

        var datesToAdd: [Date] = []
        var identifiersToRemove: [String] = existingPrompts
            .filter { prompt in
                prompt.nextTriggerDate <= now || !targetDayStarts.contains(calendar.startOfDay(for: prompt.nextTriggerDate))
            }
            .map(\.identifier)

        for day in targetDays {
            let dayStart = calendar.startOfDay(for: day)
            let shouldAddMissingForDay = replenishToday || dayStart != todayStart
            guard let range = promptRange(
                on: day,
                now: now,
                minimumDate: minimumDate,
                calendar: calendar,
                startHour: startHour,
                endHour: endHour
            ) else {
                continue
            }

            let existingForDay = existingPrompts
                .filter { prompt in
                    calendar.startOfDay(for: prompt.nextTriggerDate) == dayStart
                        && prompt.nextTriggerDate > now
                }
                .sorted { $0.nextTriggerDate < $1.nextTriggerDate }

            if existingForDay.count > safeCount {
                identifiersToRemove += existingForDay.dropFirst(safeCount).map(\.identifier)
                continue
            }

            guard shouldAddMissingForDay else {
                continue
            }

            let missingCount = safeCount - existingForDay.count
            guard missingCount > 0 else {
                continue
            }

            let existingDates = existingForDay.map(\.nextTriggerDate)
            datesToAdd += randomTimes(
                in: range,
                count: missingCount,
                excluding: existingDates,
                randomOffset: randomOffset
            )
        }

        let finalRequestCount = existingPrompts.count - identifiersToRemove.count + datesToAdd.count
        return NotificationSchedulePlan(
            datesToAdd: datesToAdd.sorted(),
            identifiersToRemove: identifiersToRemove,
            finalRequestCount: finalRequestCount
        )
    }

    static func makeRandomPromptDates(
        now: Date,
        calendar: Calendar,
        startHour: Int,
        endHour: Int,
        countPerDay: Int,
        minimumLeadTime: TimeInterval = 0,
        randomOffset: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) -> [Date] {
        let safeCount = safeNotificationCount(countPerDay)
        let minimumDate = now.addingTimeInterval(minimumLeadTime)
        return (0...Self.futureDaysToSchedule).flatMap { dayOffset in
            let day = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            guard let range = promptRange(
                on: day,
                now: now,
                minimumDate: minimumDate,
                calendar: calendar,
                startHour: startHour,
                endHour: endHour
            ) else {
                return [Date]()
            }

            return randomTimes(in: range, count: safeCount, randomOffset: randomOffset)
        }
        .sorted()
    }

    static func makeTriggerDateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    static func isTestPrompt(_ request: UNNotificationRequest) -> Bool {
        request.identifier == Self.testPromptIdentifier
    }

    static func notificationSnapshot(from request: UNNotificationRequest) -> ScheduledNotificationSnapshot? {
        guard let nextTriggerDate = Self.nextTriggerDate(from: request) else {
            return nil
        }

        if request.identifier.hasPrefix(Self.scheduledPromptIdentifierPrefix) {
            return ScheduledNotificationSnapshot(
                identifier: request.identifier,
                nextTriggerDate: nextTriggerDate,
                kind: .randomPrompt
            )
        }

        if Self.isTestPrompt(request) {
            return ScheduledNotificationSnapshot(
                identifier: request.identifier,
                nextTriggerDate: nextTriggerDate,
                kind: .testPrompt
            )
        }

        return nil
    }

    static func nextTriggerDate(from request: UNNotificationRequest) -> Date? {
        switch request.trigger {
        case let trigger as UNCalendarNotificationTrigger:
            trigger.nextTriggerDate()
        case let trigger as UNTimeIntervalNotificationTrigger:
            trigger.nextTriggerDate()
        default:
            nil
        }
    }

    private static func promptSnapshot(from request: UNNotificationRequest) -> ScheduledPromptSnapshot? {
        guard request.identifier.hasPrefix(Self.scheduledPromptIdentifierPrefix),
              let nextTriggerDate = Self.nextTriggerDate(from: request)
        else {
            return nil
        }

        return ScheduledPromptSnapshot(
            identifier: request.identifier,
            nextTriggerDate: nextTriggerDate
        )
    }

    private func verifiedPromptSnapshots(now: Date) async -> [ScheduledPromptSnapshot] {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.scheduledPromptIdentifierPrefix) }
            .compactMap(Self.promptSnapshot(from:))
            .filter { $0.nextTriggerDate > now }
    }

    private static func makePromptIdentifier(for date: Date, index: Int) -> String {
        let timestamp = Int(date.timeIntervalSince1970)
        return "\(scheduledPromptIdentifierPrefix)-\(timestamp)-\(index)"
    }

    private static func safeNotificationCount(_ countPerDay: Int) -> Int {
        min(max(countPerDay, 1), Self.maxNotificationsPerDay)
    }

    private static func promptRange(
        on day: Date,
        now: Date,
        minimumDate: Date,
        calendar: Calendar,
        startHour: Int,
        endHour: Int
    ) -> Range<Date>? {
        guard let start = date(on: day, hour: startHour, calendar: calendar),
              let end = date(on: day, hour: endHour, calendar: calendar)
        else {
            return nil
        }

        if calendar.isDate(day, inSameDayAs: now) {
            let dayEnd = calendar.date(
                byAdding: DateComponents(day: 1, second: -1),
                to: calendar.startOfDay(for: day)
            ) ?? end
            let effectiveStart = max(start, minimumDate)
            let selectedEnd = effectiveStart < end ? end : dayEnd
            let effectiveEnd = selectedEnd.timeIntervalSince(effectiveStart) < Self.minimumTodaySchedulingWindowSeconds
                ? dayEnd
                : selectedEnd
            guard effectiveStart < effectiveEnd else {
                return nil
            }

            return effectiveStart..<effectiveEnd
        }

        guard start < end else {
            return nil
        }

        return start..<end
    }

    private static func randomTimes(
        in range: Range<Date>,
        count: Int,
        excluding existingDates: [Date] = [],
        randomOffset: (Int) -> Int
    ) -> [Date] {
        let start = range.lowerBound
        let end = range.upperBound
        let duration = max(Int(end.timeIntervalSince(start)), 1)
        var offsets: [Int] = []
        var seenOffsets = Set(existingDates.map { date in
            min(max(Int(date.timeIntervalSince(start)), 0), duration - 1)
        })
        var attempts = 0
        let maximumAttempts = max(count * 8, 1)
        while offsets.count < count && attempts < maximumAttempts {
            attempts += 1
            let offset = min(max(randomOffset(duration), 0), duration - 1)
            guard !seenOffsets.contains(offset) else {
                continue
            }
            seenOffsets.insert(offset)
            offsets.append(offset)
        }
        if offsets.count < count {
            for offset in 0..<duration {
                guard !seenOffsets.contains(offset) else {
                    continue
                }
                seenOffsets.insert(offset)
                offsets.append(offset)
                if offsets.count == count {
                    break
                }
            }
        }
        while offsets.count < count {
            offsets.append(duration - 1)
        }

        return offsets
            .map { start.addingTimeInterval(TimeInterval($0)) }
            .sorted()
    }

    private static func date(on day: Date, hour: Int, calendar: Calendar) -> Date? {
        if hour == 24 {
            let midnight = calendar.startOfDay(for: day)
            return calendar.date(byAdding: .day, value: 1, to: midnight)
        }

        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private static func identifiersForScheduledRange(countPerDay: Int) -> [String] {
        let scheduledCalendarDays = futureDaysToSchedule + 1
        let maxCount = scheduledCalendarDays * max(maxNotificationsPerDay, countPerDay)
        return (0..<maxCount).map { "\(scheduledPromptIdentifierPrefix)-\($0)" }
    }
}

private extension UNAuthorizationStatus {
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .denied, .notDetermined:
            false
        @unknown default:
            false
        }
    }
}
