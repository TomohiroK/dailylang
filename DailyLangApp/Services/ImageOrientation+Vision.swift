import ImageIO
import UIKit

struct VisionImageInput: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation

    init(image: UIImage) throws {
        let normalizedImage = image.normalizedUp(maxDimension: 1_536)
        guard let cgImage = normalizedImage.cgImage else {
            throw ImageAnalysisError.invalidImage
        }

        self.cgImage = cgImage
        orientation = .up
    }

    init(cgImage: CGImage, orientation: CGImagePropertyOrientation) {
        self.cgImage = cgImage
        self.orientation = orientation
    }
}

extension UIImage {
    func normalizedUp(maxDimension: CGFloat) -> UIImage {
        let sourceSize = size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return self
        }

        let scaleRatio = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: (sourceSize.width * scaleRatio).rounded(.toNearestOrAwayFromZero),
            height: (sourceSize.height * scaleRatio).rounded(.toNearestOrAwayFromZero)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
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
