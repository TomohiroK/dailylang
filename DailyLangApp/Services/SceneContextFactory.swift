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
        imageKeywords: [ImageKeyword],
        imageRelations: [String] = [],
        userNote: String,
        level: LanguageLevel,
        lessonLanguage: LessonLanguage = .indonesian,
        lessonSituation: LessonSituation = .random,
        lessonGrammarFocus: LessonGrammarFocus = .simpleStatement,
        lessonVocabularyFocus: LessonVocabularyFocus = .objectDetails,
        recentVocabularyTerms: [String] = [],
        recentlyRepeatedExpressions: [String] = []
    ) -> SceneContext {
        SceneContext(
            capturedAt: date,
            timeText: timeFormatter.string(from: date),
            dayText: dayFormatter.string(from: date),
            locationLabel: .unknown,
            imageKeywords: imageKeywords,
            imageRelations: imageRelations,
            userNote: userNote,
            languageLevel: level,
            lessonLanguage: lessonLanguage,
            lessonSituation: lessonSituation.resolved(),
            lessonGrammarFocus: lessonGrammarFocus,
            lessonVocabularyFocus: lessonVocabularyFocus,
            recentVocabularyTerms: recentVocabularyTerms,
            recentlyRepeatedExpressions: recentlyRepeatedExpressions
        )
    }
}
