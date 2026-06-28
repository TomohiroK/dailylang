import Foundation

public enum LanguageLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case beginner
    case intermediate
    case advanced

    public var id: String { rawValue }

    public var japaneseName: String {
        switch self {
        case .beginner:
            "初級"
        case .intermediate:
            "中級"
        case .advanced:
            "上級"
        }
    }

    public var generationGuidance: String {
        switch self {
        case .beginner:
            "短文中心。基本文型を使い、語彙を少なめにして日本語解説を多めにする。"
        case .intermediate:
            "karena, sebelum, setelah, sambil などの接続表現を自然に増やす。"
        case .advanced:
            "自然な職場表現、丁寧表現、軽い雑談表現を含める。"
        }
    }
}

