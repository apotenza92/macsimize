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
            return AppStrings.updateFrequencyNever
        case .startup:
            return AppStrings.updateFrequencyStartup
        case .hourly:
            return AppStrings.updateFrequencyHourly
        case .sixHours:
            return AppStrings.updateFrequencySixHours
        case .twelveHours:
            return AppStrings.updateFrequencyTwelveHours
        case .daily:
            return AppStrings.updateFrequencyDaily
        case .weekly:
            return AppStrings.updateFrequencyWeekly
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
