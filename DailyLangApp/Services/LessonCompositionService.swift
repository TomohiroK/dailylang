import Foundation
import UIKit

struct LessonCompositionResult {
    var context: SceneContext
    var lesson: Lesson
    var photoLocalPath: String?
}

enum LessonCompositionPhase: Sendable {
    case imageAnalysis
    case lessonGeneration
    case photoStorage

    var title: String {
        switch self {
        case .imageAnalysis:
            "画像解析中"
        case .lessonGeneration:
            "レッスン作成中"
        case .photoStorage:
            "保存中"
        }
    }
}

@MainActor
final class LessonCompositionService {
    private let imageKeywordService: ImageKeywordService
    private let contextFactory: SceneContextFactory
    private let photoStorageService: PhotoStorageService
    private let openAIService: OpenAILessonService

    init(
        imageKeywordService: ImageKeywordService? = nil,
        contextFactory: SceneContextFactory? = nil,
        photoStorageService: PhotoStorageService? = nil,
        openAIService: OpenAILessonService? = nil
    ) {
        self.imageKeywordService = imageKeywordService ?? ImageKeywordService()
        self.contextFactory = contextFactory ?? SceneContextFactory()
        self.photoStorageService = photoStorageService ?? PhotoStorageService()
        self.openAIService = openAIService ?? OpenAILessonService()
    }

    func composeLesson(
        from image: UIImage,
        userNote: String,
        settings: LessonGenerationSettings,
        onPhaseChange: (@MainActor (LessonCompositionPhase) -> Void)? = nil
    ) async throws -> LessonCompositionResult {
        onPhaseChange?(.imageAnalysis)
        let evidence = await analyzeImage(image)

        return try await composeLesson(
            from: image,
            evidence: evidence,
            userNote: userNote,
            settings: settings,
            onPhaseChange: onPhaseChange
        )
    }

    func analyzeImage(_ image: UIImage) async -> ImageSceneEvidence {
        (try? await imageKeywordService.detectSceneEvidence(in: image))
            ?? ImageSceneEvidence(keywords: [], relations: [])
    }

    func composeLesson(
        from image: UIImage,
        evidence: ImageSceneEvidence,
        userNote: String,
        settings: LessonGenerationSettings,
        onPhaseChange: (@MainActor (LessonCompositionPhase) -> Void)? = nil
    ) async throws -> LessonCompositionResult {
        let evidence = evidence.removingRelationsForMissingKeywords()

        let context = contextFactory.makeContext(
            date: Date(),
            imageKeywords: evidence.keywords,
            imageRelations: evidence.relations,
            userNote: userNote,
            level: settings.languageLevel,
            lessonLanguage: settings.lessonLanguage,
            lessonSituation: settings.lessonSituation,
            lessonGrammarFocus: settings.lessonGrammarFocus,
            recentlyRepeatedExpressions: settings.recentlyRepeatedExpressions
        )

        onPhaseChange?(.lessonGeneration)
        let lesson = try await openAIService.generateLesson(
            from: context,
            apiKey: settings.openAIAPIKey,
            model: settings.openAIModel
        )

        onPhaseChange?(.photoStorage)
        let photoPath = try photoStorageService.savePhotoIfNeeded(
            image,
            shouldSave: settings.savePhotos
        )

        return LessonCompositionResult(
            context: context,
            lesson: lesson,
            photoLocalPath: photoPath
        )
    }
}

private extension ImageSceneEvidence {
    func removingRelationsForMissingKeywords() -> ImageSceneEvidence {
        let labels = Set(keywords.map { $0.label.lowercased() })
        guard !labels.isEmpty else {
            return ImageSceneEvidence(keywords: [], relations: [])
        }

        return ImageSceneEvidence(
            keywords: keywords,
            relations: relations.filter { relation in
                let matchedLabelCount = labels.filter { label in
                    relation.localizedCaseInsensitiveContains(label)
                }.count
                return matchedLabelCount >= 2
            }
        )
    }
}
