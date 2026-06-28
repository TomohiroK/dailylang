import Foundation

public enum LocationLabel: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case office
    case restaurant
    case supermarket
    case road
    case unknown

    public var id: String { rawValue }

    public var japaneseName: String {
        switch self {
        case .home:
            "自宅"
        case .office:
            "会社"
        case .restaurant:
            "レストラン"
        case .supermarket:
            "スーパー"
        case .road:
            "道路"
        case .unknown:
            "不明"
        }
    }
}

