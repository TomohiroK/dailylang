import Foundation
import CoreML
import UIKit
import Vision

enum ImageAnalysisError: LocalizedError {
    case invalidImage
    case visionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "画像を読み取れませんでした。"
        case .visionFailed:
            "画像解析に失敗しました。"
        }
    }
}

struct ImageSceneEvidence: Sendable {
    var keywords: [ImageKeyword]
    var relations: [String]
}

struct ImageKeywordService: Sendable {
    private static let objectDetectionModelName = "YOLOv3TinyInt8LUT"
    private static let imageClassificationModelName = "MobileNetV2Int8LUT"
    private static let minimumObjectConfidence: VNConfidence = 0.25
    private static let minimumModelClassificationConfidence: VNConfidence = 0.15
    private static let minimumClassificationConfidence: VNConfidence = 0.20
    private static let minimumRelaxedModelClassificationConfidence: VNConfidence = 0.08
    private static let minimumRelaxedClassificationConfidence: VNConfidence = 0.12
    private static let minimumReturnedKeywords = 3
    private static let maximumKeywords = 10
    private static let maximumSalientRegions = 8
    private static let maximumRegionKeywords = 3
    private static let minimumCropSidePixels: CGFloat = 64
    private static let minimumCropLongSideRatio: CGFloat = 0.05

    private static let normalizedLabels: [String: String] = [
        "computer keyboard": "keyboard",
        "notebook computer": "laptop",
        "cellular telephone": "phone",
        "cell phone": "phone",
        "mobile phone": "phone",
        "monitor": "screen",
        "desktop computer": "computer",
        "coffee mug": "cup",
        "water bottle": "bottle",
        "flowerpot": "plant",
        "vase": "vase",
        "people": "person",
        "adult": "person",
        "automobile": "car",
        "vehicle": "car",
        "sports car": "car",
        "cab": "car",
        "limousine": "car",
        "dining table": "dining table",
        "desk": "desk",
        "golden retriever": "dog",
        "labrador retriever": "dog",
        "tabby": "cat",
        "tiger cat": "cat",
        "egyptian cat": "cat",
    ]

    private static let excludedLabels: Set<String> = [
        "web site",
        "website",
        "envelope",
        "menu",
        "packet",
        "book jacket",
        "binder",
        "screen",
        "material",
        "wood processed",
        "structure",
        "clothing",
        "chain saw",
        "machine",
        "conveyance",
        "maze",
    ]

    private static let surfaceLabels: Set<String> = [
        "dining table",
        "table",
        "desk",
        "counter",
        "kitchen counter",
        "coffee table",
        "chair",
        "couch",
        "sofa",
        "bed",
        "bench",
        "shelf",
        "cabinet",
    ]

    private static let contextLabels: Set<String> = [
        "indoor",
        "room",
        "wall",
        "floor",
        "ceiling",
        "building",
        "house",
        "store",
        "shop",
        "interior room",
        "interior shop",
        "grocery store",
        "office",
        "road",
        "street",
        "sky",
        "outdoor",
        "land",
        "grass",
        "foliage",
        "cloudy",
        "agriculture",
        "parking lot",
        "bookshop",
        "farm",
        "crowd",
        "recreation",
        "sport",
        "ballgames",
        "blue sky",
        "library",
    ]

    @MainActor
    func detectKeywords(in image: UIImage) async throws -> [ImageKeyword] {
        try await detectSceneEvidence(in: image).keywords
    }

    @MainActor
    func detectSceneEvidence(in image: UIImage) async throws -> ImageSceneEvidence {
        let input = try VisionImageInput(image: image)

        return try await Task.detached(priority: .userInitiated) {
            try Self.detectSceneEvidence(in: input)
        }.value
    }

    private static func detectSceneEvidence(in input: VisionImageInput) throws -> ImageSceneEvidence {
        var lastError: Error?

        let objectEvidence: ImageSceneEvidence
        do {
            objectEvidence = try detectObjectEvidence(in: input)
        } catch {
            objectEvidence = ImageSceneEvidence(keywords: [], relations: [])
            lastError = error
        }

        var fallbackKeywordGroups: [[ImageKeyword]] = []
        do {
            fallbackKeywordGroups.append(try detectSaliencyClassificationKeywords(in: input))
        } catch {
            lastError = error
        }

        do {
            fallbackKeywordGroups.append(try detectModelClassificationKeywords(in: input))
        } catch {
            lastError = error
        }

        do {
            fallbackKeywordGroups.append(try detectClassificationKeywords(in: input))
        } catch {
            lastError = error
        }

        let fallbackKeywords = combine(fallbackKeywordGroups)
        let mergedKeywords = merge(primary: objectEvidence.keywords, fallback: fallbackKeywords)
        if !mergedKeywords.isEmpty {
            return ImageSceneEvidence(
                keywords: fillMinimumKeywordCoverage(
                    mergedKeywords,
                    input: input,
                    lastError: &lastError
                ),
                relations: objectEvidence.relations
            )
        }

        if !objectEvidence.keywords.isEmpty {
            return ImageSceneEvidence(
                keywords: fillMinimumKeywordCoverage(
                    Array(objectEvidence.keywords.prefix(maximumKeywords)),
                    input: input,
                    lastError: &lastError
                ),
                relations: objectEvidence.relations
            )
        }

        if let lastError {
            throw lastError
        }

        return ImageSceneEvidence(keywords: [], relations: [])
    }

    private static func detectObjectEvidence(in input: VisionImageInput) throws -> ImageSceneEvidence {
        guard let visionModel = try bundledVisionModel(named: objectDetectionModelName) else {
            return ImageSceneEvidence(keywords: [], relations: [])
        }

        var observations: [VNRecognizedObjectObservation] = []
        var requestError: Error?

        let request = VNCoreMLRequest(model: visionModel) { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                requestError = ImageAnalysisError.visionFailed
                return
            }

            observations = results
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(
            cgImage: input.cgImage,
            orientation: input.orientation,
            options: [:]
        )

        try handler.perform([request])
        if let requestError {
            throw requestError
        }

        return normalizeObjectObservations(observations)
    }

    private static func detectSaliencyClassificationKeywords(in input: VisionImageInput) throws -> [ImageKeyword] {
        var observations: [VNSaliencyImageObservation] = []
        var requestError: Error?

        let request = VNGenerateObjectnessBasedSaliencyImageRequest { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNSaliencyImageObservation] else {
                requestError = ImageAnalysisError.visionFailed
                return
            }

            observations = results
        }

        let handler = VNImageRequestHandler(
            cgImage: input.cgImage,
            orientation: input.orientation,
            options: [:]
        )

        try handler.perform([request])
        if let requestError {
            throw requestError
        }

        let salientObjects = observations
            .flatMap { $0.salientObjects ?? [] }
            .prefix(maximumSalientRegions)

        var candidatesByKey: [String: KeywordCandidate] = [:]
        for salientObject in salientObjects {
            guard let croppedImage = cropImage(input.cgImage, toNormalizedRect: salientObject.boundingBox) else {
                continue
            }

            let croppedInput = VisionImageInput(cgImage: croppedImage, orientation: .up)
            let keywordGroups = [
                (try? detectModelClassificationKeywords(in: croppedInput)) ?? [],
                (try? detectClassificationKeywords(in: croppedInput)) ?? [],
            ]
            let keywords = combine(keywordGroups)
            for keyword in keywords.prefix(maximumRegionKeywords) {
                mergeCandidate(
                    label: keyword.label,
                    confidence: keyword.confidence,
                    count: keyword.count,
                    role: keyword.role,
                    into: &candidatesByKey
                )
            }
        }

        return sortedKeywords(from: candidatesByKey)
    }

    private static func detectClassificationKeywords(
        in input: VisionImageInput,
        minimumConfidence: VNConfidence = minimumClassificationConfidence
    ) throws -> [ImageKeyword] {
        var observations: [VNClassificationObservation] = []
        var requestError: Error?

        let request = VNClassifyImageRequest { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNClassificationObservation] else {
                requestError = ImageAnalysisError.visionFailed
                return
            }

            observations = results
        }

        let handler = VNImageRequestHandler(
            cgImage: input.cgImage,
            orientation: input.orientation,
            options: [:]
        )

        try handler.perform([request])
        if let requestError {
            throw requestError
        }

        return normalizeClassificationObservations(
            observations,
            minimumConfidence: minimumConfidence
        )
    }

    private static func detectModelClassificationKeywords(
        in input: VisionImageInput,
        minimumConfidence: VNConfidence = minimumModelClassificationConfidence
    ) throws -> [ImageKeyword] {
        guard let visionModel = try bundledVisionModel(named: imageClassificationModelName) else {
            return []
        }

        var observations: [VNClassificationObservation] = []
        var requestError: Error?

        let request = VNCoreMLRequest(model: visionModel) { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNClassificationObservation] else {
                requestError = ImageAnalysisError.visionFailed
                return
            }

            observations = results
        }
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(
            cgImage: input.cgImage,
            orientation: input.orientation,
            options: [:]
        )

        try handler.perform([request])
        if let requestError {
            throw requestError
        }

        return normalizeClassificationObservations(
            observations,
            minimumConfidence: minimumConfidence
        )
    }

    private static func fillMinimumKeywordCoverage(
        _ keywords: [ImageKeyword],
        input: VisionImageInput,
        lastError: inout Error?
    ) -> [ImageKeyword] {
        guard !keywords.isEmpty, keywords.count < minimumReturnedKeywords else {
            return keywords
        }

        var relaxedGroups: [[ImageKeyword]] = []
        do {
            relaxedGroups.append(try detectModelClassificationKeywords(
                in: input,
                minimumConfidence: minimumRelaxedModelClassificationConfidence
            ))
        } catch {
            lastError = error
        }

        do {
            relaxedGroups.append(try detectClassificationKeywords(
                in: input,
                minimumConfidence: minimumRelaxedClassificationConfidence
            ))
        } catch {
            lastError = error
        }

        let relaxedKeywords = combine(relaxedGroups)
        return merge(primary: keywords, fallback: relaxedKeywords)
    }

    private static func normalizeObjectObservations(_ observations: [VNRecognizedObjectObservation]) -> ImageSceneEvidence {
        var candidatesByKey: [String: KeywordCandidate] = [:]
        var detectedObjects: [DetectedObject] = []

        for observation in observations {
            guard let bestLabel = observation.labels.first else {
                continue
            }
            guard bestLabel.confidence >= minimumObjectConfidence else {
                continue
            }

            for label in labels(from: bestLabel.identifier) {
                let role = role(for: label)
                mergeCandidate(
                    label: label,
                    confidence: Double(bestLabel.confidence),
                    count: 1,
                    role: role,
                    into: &candidatesByKey
                )
                detectedObjects.append(DetectedObject(
                    label: label,
                    confidence: Double(bestLabel.confidence),
                    role: role,
                    boundingBox: observation.boundingBox
                ))
            }
        }

        return ImageSceneEvidence(
            keywords: sortedKeywords(from: candidatesByKey),
            relations: relations(from: detectedObjects)
        )
    }

    private static func normalizeClassificationObservations(
        _ observations: [VNClassificationObservation],
        minimumConfidence: VNConfidence
    ) -> [ImageKeyword] {
        var candidatesByKey: [String: KeywordCandidate] = [:]

        for observation in observations where observation.confidence >= minimumConfidence {
            for label in labels(from: observation.identifier) {
                mergeCandidate(
                    label: label,
                    confidence: Double(observation.confidence),
                    count: 1,
                    role: role(for: label),
                    into: &candidatesByKey
                )
            }
        }

        return sortedKeywords(from: candidatesByKey)
    }

    private static func bundledVisionModel(named modelName: String) throws -> VNCoreMLModel? {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            return nil
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let mlModel = try MLModel(contentsOf: modelURL, configuration: configuration)
        return try VNCoreMLModel(for: mlModel)
    }

    private static func merge(
        primary: [ImageKeyword],
        fallback: [ImageKeyword]
    ) -> [ImageKeyword] {
        var labels: Set<String> = []
        var keywords: [ImageKeyword] = []

        for keyword in primary + fallback {
            let key = keyword.label.lowercased()
            guard !labels.contains(key) else {
                continue
            }
            labels.insert(key)
            keywords.append(keyword)
            if keywords.count == maximumKeywords {
                break
            }
        }

        return keywords
    }

    private static func combine(_ groups: [[ImageKeyword]]) -> [ImageKeyword] {
        var candidatesByKey: [String: KeywordCandidate] = [:]

        for keyword in groups.flatMap({ $0 }) {
            mergeCandidate(
                label: keyword.label,
                confidence: keyword.confidence,
                count: keyword.count,
                role: keyword.role,
                into: &candidatesByKey
            )
        }

        return sortedKeywords(from: candidatesByKey)
    }

    private static func sortedKeywords(from candidatesByKey: [String: KeywordCandidate]) -> [ImageKeyword] {
        candidatesByKey.values
            .sorted { lhs, rhs in
                let lhsRoleRank = roleRank(lhs.role)
                let rhsRoleRank = roleRank(rhs.role)
                if lhsRoleRank != rhsRoleRank {
                    return lhsRoleRank < rhsRoleRank
                }
                if lhs.confidence == rhs.confidence {
                    if lhs.count == rhs.count {
                        return lhs.label < rhs.label
                    }
                    return lhs.count > rhs.count
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(maximumKeywords)
            .map { candidate in
                ImageKeyword(
                    label: candidate.label,
                    confidence: candidate.confidence,
                    count: candidate.count,
                    role: candidate.role
                )
            }
    }

    private static func mergeCandidate(
        label: String,
        confidence: Double,
        count: Int,
        role: KeywordRole,
        into candidatesByKey: inout [String: KeywordCandidate]
    ) {
        let key = label.lowercased()
        if var existing = candidatesByKey[key] {
            existing.confidence = max(existing.confidence, confidence)
            existing.count += count
            existing.role = moreImportantRole(existing.role, role)
            candidatesByKey[key] = existing
            return
        }

        candidatesByKey[key] = KeywordCandidate(
            label: label,
            confidence: confidence,
            count: count,
            role: role
        )
    }

    private static func labels(from identifier: String) -> [String] {
        identifier
            .split(separator: ",")
            .prefix(1)
            .compactMap { part in
                normalizedLabel(for: part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                )
            }
            .filter { $0.count >= 2 }
    }

    private static func cropImage(_ image: CGImage, toNormalizedRect boundingBox: CGRect) -> CGImage? {
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = CGRect(
            x: boundingBox.minX * imageRect.width,
            y: (1 - boundingBox.maxY) * imageRect.height,
            width: boundingBox.width * imageRect.width,
            height: boundingBox.height * imageRect.height
        )
        .integral
        .intersection(imageRect)

        let minimumSide = max(
            minimumCropSidePixels,
            CGFloat(max(image.width, image.height)) * minimumCropLongSideRatio
        )
        guard cropRect.width >= minimumSide, cropRect.height >= minimumSide else {
            return nil
        }

        return image.cropping(to: cropRect)
    }

    private static func relations(from objects: [DetectedObject]) -> [String] {
        let foregroundObjects = objects.filter { $0.role == .foreground }
        let surfaces = objects.filter { $0.role == .surface }
        var relations: [String] = []
        var seenRelations = Set<String>()

        for object in foregroundObjects {
            for surface in surfaces where isOn(object.boundingBox, surface.boundingBox) {
                let relation = "\(object.label) on \(surface.label)"
                guard seenRelations.insert(relation.lowercased()).inserted else {
                    continue
                }
                relations.append(relation)
                if relations.count == maximumKeywords {
                    return relations
                }
            }
        }

        return relations
    }

    private static func isOn(_ item: CGRect, _ surface: CGRect) -> Bool {
        let horizontalOverlap = item.midX >= surface.minX && item.midX <= surface.maxX
        let restsOnUpperHalf = item.minY >= surface.midY - 0.05
            && item.minY <= surface.maxY + 0.10
        return horizontalOverlap && restsOnUpperHalf
    }

    private static func role(for label: String) -> KeywordRole {
        let normalized = label.lowercased()
        if surfaceLabels.contains(normalized) {
            return .surface
        }
        if contextLabels.contains(normalized) {
            return .context
        }
        return .foreground
    }

    private static func roleRank(_ role: KeywordRole) -> Int {
        switch role {
        case .foreground:
            0
        case .surface:
            1
        case .context:
            2
        }
    }

    private static func moreImportantRole(_ lhs: KeywordRole, _ rhs: KeywordRole) -> KeywordRole {
        roleRank(lhs) <= roleRank(rhs) ? lhs : rhs
    }

    private static func normalizedLabel(for label: String) -> String? {
        let lowercased = label.lowercased()
        if excludedLabels.contains(lowercased) {
            return nil
        }
        return normalizedLabels[lowercased] ?? lowercased
    }

    private struct KeywordCandidate {
        var label: String
        var confidence: Double
        var count: Int
        var role: KeywordRole
    }

    private struct DetectedObject {
        var label: String
        var confidence: Double
        var role: KeywordRole
        var boundingBox: CGRect
    }
}
