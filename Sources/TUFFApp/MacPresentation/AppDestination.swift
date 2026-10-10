public enum AppDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case chat
    case research
    case models
    case benchmarks
    case server
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chat: "Chat"
        case .research: "Research"
        case .models: "Models"
        case .benchmarks: "Benchmarks"
        case .server: "Server"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .research: "magnifyingglass"
        case .models: "shippingbox"
        case .benchmarks: "gauge.with.dots.needle.67percent"
        case .server: "network"
        case .settings: "gearshape"
        }
    }

    public var keyboardShortcut: String {
        switch self {
        case .chat: "1"
        case .research: "2"
        case .models: "3"
        case .benchmarks: "4"
        case .server: "5"
        case .settings: "6"
        }
    }
}
