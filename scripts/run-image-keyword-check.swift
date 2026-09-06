#!/usr/bin/env swift

import CoreGraphics
import CoreML
import Foundation
import ImageIO
import Vision

private enum ImageKeywordCheckError: LocalizedError {
    case missingArguments
    case unreadableImage(String)
    case unreadableModel(String)
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingArguments:
            "Usage: scripts/run-image-keyword-check.swift [--model <mlmodel-or-mlmodelc>] [--expected <json>] <image> [<image> ...]"
        case .unreadableImage(let path):
            "Could not read image: \(path)"
        case .unreadableModel(let path):
            "Could not read Core ML model: \(path)"
        case .visionFailed(let detail):
            "Vision image analysis failed: \(detail)"
        }
    }
}

private struct ImageKeyword {
    var label: String
    var confidence: Double
    var count: Int
    var role: KeywordRole
}

private enum KeywordRole: String, Codable {
    case foreground
    case surface
    case context
}

private struct ImageSceneEvidence {
    var keywords: [ImageKeyword]
    var relations: [String]
}

private struct KeywordCandidate {
    var label: String
    var confidence: Double
    var count: Int
    var role: KeywordRole
}

private struct DetectedObject {
    var label: String
    var role: KeywordRole
    var boundingBox: CGRect
}

private struct LocalImageKeywordService {
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
    private static let maximumImageDimension = 1_536

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

    private let objectDetectionModel: VNCoreMLModel?
    private let imageClassificationModel: VNCoreMLModel?

    init(modelPath: String?) throws {
        objectDetectionModel = try Self.loadVisionModel(at: modelPath)
        imageClassificationModel = try Self.loadVisionModel(
            at: Self.defaultModelPath("MobileNetV2Int8LUT.mlmodel")
        )
    }

    private static func defaultModelPath(_ fileName: String) -> String? {
        let path = "DailyLangApp/Resources/Models/\(fileName)"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func loadVisionModel(at modelPath: String?) throws -> VNCoreMLModel? {
        guard let modelPath else {
            return nil
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw ImageKeywordCheckError.unreadableModel(modelPath)
        }

        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try MLModel.compileModel(at: modelURL)
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let mlModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
        return try VNCoreMLModel(for: mlModel)
    }

    static func loadImage(at path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageKeywordCheckError.unreadableImage(path)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumImageDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageKeywordCheckError.unreadableImage(path)
        }
        return image
    }

    func detectKeywords(in image: CGImage) throws -> [ImageKeyword] {
        try detectSceneEvidence(in: image).keywords
    }

    func detectSceneEvidence(in image: CGImage) throws -> ImageSceneEvidence {
        var lastError: Error?
        let objectEvidence: ImageSceneEvidence

        do {
            objectEvidence = try detectObjectEvidence(in: image)
        } catch {
            objectEvidence = ImageSceneEvidence(keywords: [], relations: [])
            lastError = error
        }

        var fallbackKeywordGroups: [[ImageKeyword]] = []
        do {
            fallbackKeywordGroups.append(try detectSaliencyClassificationKeywords(in: image))
        } catch {
            lastError = error
        }

        do {
            fallbackKeywordGroups.append(try detectModelClassificationKeywords(in: image))
        } catch {
            lastError = error
        }

        do {
            fallbackKeywordGroups.append(try detectClassificationKeywords(in: image))
        } catch {
            lastError = error
        }

        let fallbackKeywords = Self.combine(fallbackKeywordGroups)
        let mergedKeywords = Self.merge(primary: objectEvidence.keywords, fallback: fallbackKeywords)
        if !mergedKeywords.isEmpty {
            return ImageSceneEvidence(
                keywords: fillMinimumKeywordCoverage(
                    mergedKeywords,
                    image: image,
                    lastError: &lastError
                ),
                relations: objectEvidence.relations
            )
        }

        if !objectEvidence.keywords.isEmpty {
            return ImageSceneEvidence(
                keywords: fillMinimumKeywordCoverage(
                    Array(objectEvidence.keywords.prefix(Self.maximumKeywords)),
                    image: image,
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

    private func detectObjectEvidence(in image: CGImage) throws -> ImageSceneEvidence {
        guard let objectDetectionModel else {
            return ImageSceneEvidence(keywords: [], relations: [])
        }

        var observations: [VNRecognizedObjectObservation] = []
        var requestError: Error?

        let request = VNCoreMLRequest(model: objectDetectionModel) { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                requestError = ImageKeywordCheckError.visionFailed("Unexpected object detection result type")
                return
            }

            observations = results
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let requestError {
            throw requestError
        }

        return Self.normalizeObjectObservations(observations)
    }

    private func detectSaliencyClassificationKeywords(in image: CGImage) throws -> [ImageKeyword] {
        var observations: [VNSaliencyImageObservation] = []
        var requestError: Error?

        let request = VNGenerateObjectnessBasedSaliencyImageRequest { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNSaliencyImageObservation] else {
                requestError = ImageKeywordCheckError.visionFailed("Unexpected saliency result type")
                return
            }

            observations = results
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let requestError {
            throw requestError
        }

        let salientObjects = observations
            .flatMap { $0.salientObjects ?? [] }
            .prefix(Self.maximumSalientRegions)

        var candidatesByKey: [String: KeywordCandidate] = [:]
        for salientObject in salientObjects {
            guard let croppedImage = Self.cropImage(image, toNormalizedRect: salientObject.boundingBox) else {
                continue
            }

            let keywordGroups = [
                (try? detectModelClassificationKeywords(in: croppedImage)) ?? [],
                (try? detectClassificationKeywords(in: croppedImage)) ?? [],
            ]
            let keywords = Self.combine(keywordGroups)
            for keyword in keywords.prefix(Self.maximumRegionKeywords) {
                Self.mergeCandidate(
                    label: keyword.label,
                    confidence: keyword.confidence,
                    count: keyword.count,
                    role: keyword.role,
                    into: &candidatesByKey
                )
            }
        }

        return Self.sortedKeywords(from: candidatesByKey)
    }

    private func detectClassificationKeywords(
        in image: CGImage,
        minimumConfidence: VNConfidence = Self.minimumClassificationConfidence
    ) throws -> [ImageKeyword] {
        var observations: [VNClassificationObservation] = []
        var requestError: Error?

        let request = VNClassifyImageRequest { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNClassificationObservation] else {
                requestError = ImageKeywordCheckError.visionFailed("Unexpected classification result type")
                return
            }

            observations = results
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let requestError {
            throw requestError
        }

        return Self.normalizeClassificationObservations(
            observations,
            minimumConfidence: minimumConfidence
        )
    }

    private func detectModelClassificationKeywords(
        in image: CGImage,
        minimumConfidence: VNConfidence = Self.minimumModelClassificationConfidence
    ) throws -> [ImageKeyword] {
        guard let imageClassificationModel else {
            return []
        }

        var observations: [VNClassificationObservation] = []
        var requestError: Error?

        let request = VNCoreMLRequest(model: imageClassificationModel) { request, error in
            if let error {
                requestError = error
                return
            }

            guard let results = request.results as? [VNClassificationObservation] else {
                requestError = ImageKeywordCheckError.visionFailed("Unexpected model classification result type")
                return
            }

            observations = results
        }
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let requestError {
            throw requestError
        }

        return Self.normalizeClassificationObservations(
            observations,
            minimumConfidence: minimumConfidence
        )
    }

    private func fillMinimumKeywordCoverage(
        _ keywords: [ImageKeyword],
        image: CGImage,
        lastError: inout Error?
    ) -> [ImageKeyword] {
        guard !keywords.isEmpty, keywords.count < Self.minimumReturnedKeywords else {
            return keywords
        }

        var relaxedGroups: [[ImageKeyword]] = []
        do {
            relaxedGroups.append(try detectModelClassificationKeywords(
                in: image,
                minimumConfidence: Self.minimumRelaxedModelClassificationConfidence
            ))
        } catch {
            lastError = error
        }

        do {
            relaxedGroups.append(try detectClassificationKeywords(
                in: image,
                minimumConfidence: Self.minimumRelaxedClassificationConfidence
            ))
        } catch {
            lastError = error
        }

        return Self.merge(primary: keywords, fallback: Self.combine(relaxedGroups))
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

    private static func merge(primary: [ImageKeyword], fallback: [ImageKeyword]) -> [ImageKeyword] {
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
}

private struct ParsedArguments {
    var modelPath: String?
    var expectedPath: String?
    var imagePaths: [String]
}

private func parseArguments() throws -> ParsedArguments {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var modelPath: String?
    var expectedPath: String?

    while let first = arguments.first, first.hasPrefix("--") {
        switch first {
        case "--model":
            guard arguments.count >= 3 else {
                throw ImageKeywordCheckError.missingArguments
            }
            modelPath = arguments[1]
            arguments.removeFirst(2)
        case "--expected":
            guard arguments.count >= 3 else {
                throw ImageKeywordCheckError.missingArguments
            }
            expectedPath = arguments[1]
            arguments.removeFirst(2)
        default:
            throw ImageKeywordCheckError.missingArguments
        }
    }

    if modelPath == nil {
        let defaultModelPath = "DailyLangApp/Resources/Models/YOLOv3TinyInt8LUT.mlmodel"
        if FileManager.default.fileExists(atPath: defaultModelPath) {
            modelPath = defaultModelPath
        }
    }

    guard !arguments.isEmpty else {
        throw ImageKeywordCheckError.missingArguments
    }

    return ParsedArguments(modelPath: modelPath, expectedPath: expectedPath, imagePaths: arguments)
}

private struct GoldenExpectation: Decodable {
    var foreground: [String]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let labels = try? container.decode([String].self) {
            foreground = labels
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        foreground = try container.decode([String].self, forKey: .foreground)
    }

    enum CodingKeys: String, CodingKey {
        case foreground
    }
}

private struct EvaluationSummary {
    var expectedCount = 0
    var matchedCount = 0
    var detectedForegroundCount = 0
    var unexpectedForegroundCount = 0

    var foregroundRecall: Double {
        guard expectedCount > 0 else {
            return 0
        }
        return Double(matchedCount) / Double(expectedCount)
    }

    var noiseRate: Double {
        guard detectedForegroundCount > 0 else {
            return 0
        }
        return Double(unexpectedForegroundCount) / Double(detectedForegroundCount)
    }
}

private func loadExpectations(at path: String?) throws -> [String: GoldenExpectation] {
    guard let path else {
        return [:]
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode([String: GoldenExpectation].self, from: data)
}

private func normalizedMetricLabel(_ label: String) -> String {
    label
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func expectation(
    for path: String,
    in expectations: [String: GoldenExpectation]
) -> GoldenExpectation? {
    let fileName = URL(fileURLWithPath: path).lastPathComponent
    return expectations[fileName] ?? expectations[path]
}

private func run() throws {
    let arguments = try parseArguments()
    let service = try LocalImageKeywordService(modelPath: arguments.modelPath)
    let expectations = try loadExpectations(at: arguments.expectedPath)
    var summary = EvaluationSummary()

    for path in arguments.imagePaths {
        let image = try LocalImageKeywordService.loadImage(at: path)
        let evidence = try service.detectSceneEvidence(in: image)
        let keywords = evidence.keywords
        let keywordText = keywords
            .map { keyword in
                let countText = keyword.count > 1 ? " x\(keyword.count)" : ""
                return "\(keyword.label)\(countText)=\(String(format: "%.2f", keyword.confidence)):\(keyword.role.rawValue)"
            }
            .joined(separator: ", ")
        let relationText = evidence.relations.joined(separator: ", ")

        print("## \(URL(fileURLWithPath: path).lastPathComponent)")
        print("IMAGE_KEYWORDS=\(keywordText.isEmpty ? "[]" : keywordText)")
        print("RELATIONS=\(relationText.isEmpty ? "[]" : relationText)")

        if let expectation = expectation(for: path, in: expectations) {
            let expected = Set(expectation.foreground.map(normalizedMetricLabel).filter { !$0.isEmpty })
            let detected = Set(
                keywords
                    .filter { $0.role == .foreground }
                    .map { normalizedMetricLabel($0.label) }
                    .filter { !$0.isEmpty }
            )
            let matched = expected.intersection(detected)
            let missing = expected.subtracting(detected)
            let unexpected = detected.subtracting(expected)

            summary.expectedCount += expected.count
            summary.matchedCount += matched.count
            summary.detectedForegroundCount += detected.count
            summary.unexpectedForegroundCount += unexpected.count

            print("EXPECTED_FOREGROUND=\(expected.sorted().joined(separator: ", "))")
            print("MATCHED=\(matched.sorted().joined(separator: ", "))")
            print("MISSING=\(missing.sorted().joined(separator: ", "))")
            print("UNEXPECTED_FOREGROUND=\(unexpected.sorted().joined(separator: ", "))")
        }
        print("")
    }

    if !expectations.isEmpty {
        print("## SUMMARY")
        print("FOREGROUND_RECALL_AT_10=\(String(format: "%.2f", summary.foregroundRecall))")
        print("NOISE_RATE=\(String(format: "%.2f", summary.noiseRate))")
    }
}

do {
    try run()
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
