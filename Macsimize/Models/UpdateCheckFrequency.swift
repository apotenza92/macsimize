import Foundation

enum UpdateCheckFrequency: String, CaseIterable, Codable, Identifiable {
    case never
    case startup
    case hourly
    case sixHours
    case twelveHours
    case daily
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never:
            return "Never"
        case .startup:
            return "On Startup"
        case .hourly:
            return "Every Hour"
        case .sixHours:
            return "Every 6 Hours"
        case .twelveHours:
            return "Every 12 Hours"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .hourly:
            return 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .twelveHours:
            return 12 * 60 * 60
        case .daily:
            return 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .never, .startup:
            return nil
        }
    }
}
