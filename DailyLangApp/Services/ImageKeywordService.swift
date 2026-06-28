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

struct ImageKeywordService: Sendable {
    private static let objectDetectionModelName = "YOLOv3TinyInt8LUT"
    private static let imageClassificationModelName = "MobileNetV2Int8LUT"
    private static let minimumObjectConfidence: VNConfidence = 0.25
    private static let minimumModelClassificationConfidence: VNConfidence = 0.05
    private static let minimumClassificationConfidence: VNConfidence = 0.08
    private static let maximumKeywords = 16
    private static let maximumSalientRegions = 8
    private static let maximumRegionKeywords = 3

    @MainActor
    func detectKeywords(in image: UIImage) async throws -> [ImageKeyword] {
        let input = try VisionImageInput(image: image)

        return try await Task.detached(priority: .userInitiated) {
            try Self.detectKeywords(in: input)
        }.value
    }

    private static func detectKeywords(in input: VisionImageInput) throws -> [ImageKeyword] {
        var lastError: Error?

        let objectKeywords: [ImageKeyword]
        do {
            objectKeywords = try detectObjectKeywords(in: input)
        } catch {
            objectKeywords = []
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
        let mergedKeywords = merge(primary: objectKeywords, fallback: fallbackKeywords)
        if !mergedKeywords.isEmpty {
            return mergedKeywords
        }

        if !objectKeywords.isEmpty {
            return Array(objectKeywords.prefix(maximumKeywords))
        }

        if let lastError {
            throw lastError
        }

        return []
    }

    private static func detectObjectKeywords(in input: VisionImageInput) throws -> [ImageKeyword] {
        guard let visionModel = try bundledVisionModel(named: objectDetectionModelName) else {
            return []
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
                    into: &candidatesByKey
                )
            }
        }

        return sortedKeywords(from: candidatesByKey)
    }

    private static func detectClassificationKeywords(in input: VisionImageInput) throws -> [ImageKeyword] {
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
            minimumConfidence: minimumClassificationConfidence
        )
    }

    private static func detectModelClassificationKeywords(in input: VisionImageInput) throws -> [ImageKeyword] {
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
            minimumConfidence: minimumModelClassificationConfidence
        )
    }

    private static func normalizeObjectObservations(_ observations: [VNRecognizedObjectObservation]) -> [ImageKeyword] {
        var candidatesByKey: [String: KeywordCandidate] = [:]

        for observation in observations {
            guard let bestLabel = observation.labels.first else {
                continue
            }
            guard bestLabel.confidence >= minimumObjectConfidence else {
                continue
            }

            for label in labels(from: bestLabel.identifier) {
                mergeCandidate(
                    label: label,
                    confidence: Double(bestLabel.confidence),
                    count: 1,
                    into: &candidatesByKey
                )
            }
        }

        return sortedKeywords(from: candidatesByKey)
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
                into: &candidatesByKey
            )
        }

        return sortedKeywords(from: candidatesByKey)
    }

    private static func sortedKeywords(from candidatesByKey: [String: KeywordCandidate]) -> [ImageKeyword] {
        candidatesByKey.values
            .sorted { lhs, rhs in
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
                    count: candidate.count
                )
            }
    }

    private static func mergeCandidate(
        label: String,
        confidence: Double,
        count: Int,
        into candidatesByKey: inout [String: KeywordCandidate]
    ) {
        let key = label.lowercased()
        if var existing = candidatesByKey[key] {
            existing.confidence = max(existing.confidence, confidence)
            existing.count += count
            candidatesByKey[key] = existing
            return
        }

        candidatesByKey[key] = KeywordCandidate(
            label: label,
            confidence: confidence,
            count: count
        )
    }

    private static func labels(from identifier: String) -> [String] {
        identifier
            .split(separator: ",")
            .prefix(1)
            .map { part in
                part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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

        guard cropRect.width >= 16, cropRect.height >= 16 else {
            return nil
        }

        return image.cropping(to: cropRect)
    }

    private struct KeywordCandidate {
        var label: String
        var confidence: Double
        var count: Int
    }
}
