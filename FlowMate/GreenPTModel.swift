import Foundation

enum GreenPTModel: String, CaseIterable {
    case greenL = "green-l"
    case greenR = "green-r"

    var displayName: String {
        switch self {
        case .greenL:
            return "Green-L"
        case .greenR:
            return "Green-R"
        }
    }

    var description: String {
        switch self {
        case .greenL:
            return "Large generative model optimized for sustainability. Best for general conversations, content creation, and text analysis."
        case .greenR:
            return "Reasoning model specialized in logical reasoning and problem-solving. Ideal for complex analytical tasks and mathematical problems"
        }
    }

    var iconName: String {
        switch self {
        case .greenL:
            return "leaf.fill"
        case .greenR:
            return "magnifyingglass"
        }
    }
}
