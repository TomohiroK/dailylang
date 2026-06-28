import Foundation
import UIKit

enum PhotoStorageError: LocalizedError {
    case encodingFailed
    case directoryUnavailable

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "写真を保存形式に変換できませんでした。"
        case .directoryUnavailable:
            "写真の保存先を準備できませんでした。"
        }
    }
}

struct PhotoStorageService: Sendable {
    private static let jpegQuality = 0.82

    func savePhotoIfNeeded(_ image: UIImage, shouldSave: Bool) throws -> String? {
        guard shouldSave else {
            return nil
        }

        guard let data = image.jpegData(compressionQuality: Self.jpegQuality) else {
            throw PhotoStorageError.encodingFailed
        }

        let directory = try photosDirectory()
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        try data.write(to: fileURL, options: [.atomic])
        return fileURL.path
    }

    private func photosDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PhotoStorageError.directoryUnavailable
        }

        let directory = applicationSupport.appendingPathComponent("DailyLang/Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

