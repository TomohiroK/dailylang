import ImageIO
import UIKit

struct VisionImageInput: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation

    init(image: UIImage) throws {
        guard let cgImage = image.cgImage else {
            throw ImageAnalysisError.invalidImage
        }

        self.cgImage = cgImage
        orientation = CGImagePropertyOrientation(image.imageOrientation)
    }

    init(cgImage: CGImage, orientation: CGImagePropertyOrientation) {
        self.cgImage = cgImage
        self.orientation = orientation
    }
}

extension CGImagePropertyOrientation {
    init(_ imageOrientation: UIImage.Orientation) {
        switch imageOrientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
