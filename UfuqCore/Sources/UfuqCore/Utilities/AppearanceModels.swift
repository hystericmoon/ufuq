import Foundation

public enum UfuqAccent: String, CaseIterable, Codable, Equatable, Sendable {
    case emerald
    case sky
    case amber
    case coral
    case indigo

    public var displayName: String {
        switch self {
        case .emerald: return "Emerald"
        case .sky: return "Sky"
        case .amber: return "Amber"
        case .coral: return "Coral"
        case .indigo: return "Indigo"
        }
    }

    public var hex: UInt32 {
        switch self {
        case .emerald: return 0x4FD1A5
        case .sky: return 0x6E9BFF
        case .amber: return 0xFFB340
        case .coral: return 0xD97757
        case .indigo: return 0x9B8CFF
        }
    }
}

public enum UfuqGlassStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case automatic
    case frosted
    case solid

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic glass"
        case .frosted: return "Frosted dark"
        case .solid: return "Solid obsidian"
        }
    }
}

public enum UfuqShapeStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case standard
    case pill
    case crisp

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .pill: return "Soft pill"
        case .crisp: return "Crisp"
        }
    }

    public var collapsedRadius: Double {
        switch self {
        case .standard: return 14
        case .pill: return 18
        case .crisp: return 8
        }
    }

    public var peekRadius: Double {
        switch self {
        case .standard: return 22
        case .pill: return 26
        case .crisp: return 14
        }
    }

    public var expandedRadius: Double {
        switch self {
        case .standard: return 28
        case .pill: return 34
        case .crisp: return 18
        }
    }
}
