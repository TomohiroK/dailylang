import Foundation
import UserNotifications

enum NotificationSchedulerError: LocalizedError {
    case invalidTimeRange
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            "通知の開始時刻は終了時刻より前にしてください。"
        case .authorizationDenied:
            "通知が許可されていません。設定アプリで通知を許可してください。"
        }
    }
}

@MainActor
struct NotificationScheduleSummary: Sendable {
    let requestCount: Int
    let futureDayCount: Int

    var statusMessage: String {
        "\(requestCount)件の通知を今日から\(futureDayCount)日先まで予約しました。"
    }
}

@MainActor
struct NotificationScheduler {
    static let scheduledPromptIdentifierPrefix = "daily-lang-random-prompt"
    static let futureDaysToSchedule = 3
    static let minimumPromptLeadTimeSeconds: TimeInterval = 60
    private static let testIdentifier = "daily-lang-test-prompt"
    private static let testPromptDelaySeconds: TimeInterval = 5
    private static let maxNotificationsPerDay = 10
    private static let minimumPendingDays = 2
    private static let promptBodies = [
        "今何してる？写真を撮ってインドネシア語にしよう",
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

        return try await replaceScheduledPrompts(
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

        center.removePendingNotificationRequests(withIdentifiers: [Self.testIdentifier])

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
            identifier: Self.testIdentifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
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

        let pending = await center.pendingNotificationRequests()
        let promptCount = pending.filter { $0.identifier.hasPrefix(Self.scheduledPromptIdentifierPrefix) }.count
        guard Self.shouldRefreshRandomPrompts(
            pendingPromptCount: promptCount,
            countPerDay: countPerDay
        ) else {
            return
        }

        _ = try await replaceScheduledPrompts(
            startHour: startHour,
            endHour: endHour,
            countPerDay: countPerDay
        )
    }

    private func replaceScheduledPrompts(
        startHour: Int,
        endHour: Int,
        countPerDay: Int
    ) async throws -> NotificationScheduleSummary {
        let existingPromptIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.scheduledPromptIdentifierPrefix) }
        let fallbackIdentifiers = Self.identifiersForScheduledRange(countPerDay: countPerDay)
        center.removePendingNotificationRequests(withIdentifiers: existingPromptIdentifiers + fallbackIdentifiers)

        let safeCount = Self.safeNotificationCount(countPerDay)
        let now = Date()
        let dates = Self.makeRandomPromptDates(
            now: now,
            calendar: calendar,
            startHour: startHour,
            endHour: endHour,
            countPerDay: safeCount,
            minimumLeadTime: Self.minimumPromptLeadTimeSeconds
        )

        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "DailyLang"
            content.body = Self.promptBodies[index % Self.promptBodies.count]
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.captureScene

            let components = Self.makeTriggerDateComponents(for: date, calendar: calendar)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(Self.scheduledPromptIdentifierPrefix)-\(index)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }

        return NotificationScheduleSummary(
            requestCount: dates.count,
            futureDayCount: Self.futureDaysToSchedule
        )
    }

    static func shouldRefreshRandomPrompts(
        pendingPromptCount: Int,
        countPerDay: Int
    ) -> Bool {
        pendingPromptCount < safeNotificationCount(countPerDay) * minimumPendingDays
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
            return randomTimes(
                on: day,
                calendar: calendar,
                startHour: startHour,
                endHour: endHour,
                count: safeCount,
                randomOffset: randomOffset
            )
        }
        .filter { $0 > minimumDate }
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

    private static func safeNotificationCount(_ countPerDay: Int) -> Int {
        min(max(countPerDay, 1), Self.maxNotificationsPerDay)
    }

    private static func randomTimes(
        on day: Date,
        calendar: Calendar,
        startHour: Int,
        endHour: Int,
        count: Int,
        randomOffset: (Int) -> Int
    ) -> [Date] {
        guard let start = date(on: day, hour: startHour, calendar: calendar),
              let end = date(on: day, hour: endHour, calendar: calendar)
        else {
            return []
        }

        let duration = max(Int(end.timeIntervalSince(start)), 1)
        var offsets: Set<Int> = []
        var attempts = 0
        let maximumAttempts = max(count * 8, 1)
        while offsets.count < count && attempts < maximumAttempts {
            attempts += 1
            let offset = min(max(randomOffset(duration), 0), duration - 1)
            offsets.insert(offset)
        }
        if offsets.count < count {
            for offset in 0..<duration {
                offsets.insert(offset)
                if offsets.count == count {
                    break
                }
            }
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
