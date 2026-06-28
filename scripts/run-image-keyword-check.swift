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
            "Usage: scripts/run-image-keyword-check.swift [--model <mlmodel-or-mlmodelc>] <image> [<image> ...]"
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
}

private struct KeywordCandidate {
    var label: String
    var confidence: Double
    var count: Int
}

private struct LocalImageKeywordService {
    private static let minimumObjectConfidence: VNConfidence = 0.25
    private static let minimumModelClassificationConfidence: VNConfidence = 0.05
    private static let minimumClassificationConfidence: VNConfidence = 0.08
    private static let maximumKeywords = 16
    private static let maximumSalientRegions = 8
    private static let maximumRegionKeywords = 3

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

    func detectKeywords(in image: CGImage) throws -> [ImageKeyword] {
        var lastError: Error?
        let objectKeywords: [ImageKeyword]

        do {
            objectKeywords = try detectObjectKeywords(in: image)
        } catch {
            objectKeywords = []
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
        let mergedKeywords = Self.merge(primary: objectKeywords, fallback: fallbackKeywords)
        if !mergedKeywords.isEmpty {
            return mergedKeywords
        }

        if !objectKeywords.isEmpty {
            return Array(objectKeywords.prefix(Self.maximumKeywords))
        }

        if let lastError {
            throw lastError
        }

        return []
    }

    private func detectObjectKeywords(in image: CGImage) throws -> [ImageKeyword] {
        guard let objectDetectionModel else {
            return []
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
                    into: &candidatesByKey
                )
            }
        }

        return Self.sortedKeywords(from: candidatesByKey)
    }

    private func detectClassificationKeywords(in image: CGImage) throws -> [ImageKeyword] {
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
            minimumConfidence: Self.minimumClassificationConfidence
        )
    }

    private func detectModelClassificationKeywords(in image: CGImage) throws -> [ImageKeyword] {
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
            minimumConfidence: Self.minimumModelClassificationConfidence
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
}

private struct ParsedArguments {
    var modelPath: String?
    var imagePaths: [String]
}

private func parseArguments() throws -> ParsedArguments {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var modelPath: String?

    if arguments.first == "--model" {
        guard arguments.count >= 3 else {
            throw ImageKeywordCheckError.missingArguments
        }
        modelPath = arguments[1]
        arguments.removeFirst(2)
    } else {
        let defaultModelPath = "DailyLangApp/Resources/Models/YOLOv3TinyInt8LUT.mlmodel"
        if FileManager.default.fileExists(atPath: defaultModelPath) {
            modelPath = defaultModelPath
        }
    }

    guard !arguments.isEmpty else {
        throw ImageKeywordCheckError.missingArguments
    }

    return ParsedArguments(modelPath: modelPath, imagePaths: arguments)
}

private func loadImage(at path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ImageKeywordCheckError.unreadableImage(path)
    }
    return image
}

private func run() throws {
    let arguments = try parseArguments()
    let service = try LocalImageKeywordService(modelPath: arguments.modelPath)

    for path in arguments.imagePaths {
        let image = try loadImage(at: path)
        let keywords = try service.detectKeywords(in: image)
        let keywordText = keywords
            .map { keyword in
                let countText = keyword.count > 1 ? " x\(keyword.count)" : ""
                return "\(keyword.label)\(countText)=\(String(format: "%.2f", keyword.confidence))"
            }
            .joined(separator: ", ")

        print("## \(URL(fileURLWithPath: path).lastPathComponent)")
        print("IMAGE_KEYWORDS=\(keywordText.isEmpty ? "[]" : keywordText)")
        print("")
    }
}

do {
    try run()
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
