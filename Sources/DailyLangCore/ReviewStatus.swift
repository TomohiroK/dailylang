import Foundation

public enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case new
    case remembered
    case again

    public var title: String {
        switch self {
        case .new:
            "未復習"
        case .remembered:
            "覚えた"
        case .again:
            "もう一度"
        }
    }
}
