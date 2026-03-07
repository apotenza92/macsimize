import Foundation

enum WindowActionMode: String, CaseIterable, Codable, Identifiable {
    case maximize
    case fullScreen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .maximize:
            return "Maximize"
        case .fullScreen:
            return "Full Screen"
        }
    }

    var helpText: String {
        switch self {
        case .maximize:
            return "Resize the window to the current display’s visible usable frame, then restore the previous frame on the next clean click."
        case .fullScreen:
            return "Pass the green-button click through to standard macOS full-screen behavior."
        }
    }

    var isExperimental: Bool {
        false
    }
}
