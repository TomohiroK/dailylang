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
    private let locationLabelService: LocationLabelService
    private let contextFactory: SceneContextFactory
    private let photoStorageService: PhotoStorageService
    private let openAIService: OpenAILessonService

    init(
        imageKeywordService: ImageKeywordService? = nil,
        locationLabelService: LocationLabelService? = nil,
        contextFactory: SceneContextFactory? = nil,
        photoStorageService: PhotoStorageService? = nil,
        openAIService: OpenAILessonService? = nil
    ) {
        self.imageKeywordService = imageKeywordService ?? ImageKeywordService()
        self.locationLabelService = locationLabelService ?? LocationLabelService()
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
        let locationLabel = await locationLabelService.currentLabel(fallback: settings.defaultLocationLabel)
        onPhaseChange?(.imageAnalysis)
        let imageKeywords = (try? await imageKeywordService.detectKeywords(in: image)) ?? []

        let context = contextFactory.makeContext(
            date: Date(),
            locationLabel: locationLabel,
            imageKeywords: imageKeywords,
            userNote: userNote,
            level: settings.languageLevel
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
