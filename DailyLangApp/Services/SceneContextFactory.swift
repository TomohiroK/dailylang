import Foundation

struct SceneContextFactory {
    private let timeFormatter: DateFormatter
    private let dayFormatter: DateFormatter

    init(locale: Locale = Locale(identifier: "en_US_POSIX")) {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateFormat = "HH:mm"

        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.dateFormat = "EEEE"

        self.timeFormatter = timeFormatter
        self.dayFormatter = dayFormatter
    }

    func makeContext(
        date: Date,
        locationLabel: LocationLabel,
        imageKeywords: [ImageKeyword],
        userNote: String,
        level: LanguageLevel
    ) -> SceneContext {
        SceneContext(
            capturedAt: date,
            timeText: timeFormatter.string(from: date),
            dayText: dayFormatter.string(from: date),
            locationLabel: locationLabel,
            imageKeywords: imageKeywords,
            userNote: userNote,
            languageLevel: level
        )
    }
}
