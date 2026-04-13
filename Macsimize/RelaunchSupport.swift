import Foundation

enum RelaunchSupport {
    static let automaticRelaunchAttemptArgumentPrefix = "--macsimize-relaunch-attempt="
    static let defaultAutomaticRelaunchAttempt = 0

    static func automaticRelaunchAttempt(arguments: [String]) -> Int {
        for argument in arguments {
            guard argument.hasPrefix(automaticRelaunchAttemptArgumentPrefix) else {
                continue
            }

            let rawValue = String(argument.dropFirst(automaticRelaunchAttemptArgumentPrefix.count))
            if let attempt = Int(rawValue), attempt >= 0 {
                return attempt
            }
        }

        return defaultAutomaticRelaunchAttempt
    }

    static func launchArguments(
        from existingArguments: [String],
        openSettingsArguments: Set<String>,
        nextAutomaticRelaunchAttempt: Int?
    ) -> [String] {
        var launchArguments = existingArguments.filter { argument in
            openSettingsArguments.contains(argument)
        }

        if let nextAutomaticRelaunchAttempt {
            launchArguments.append("\(automaticRelaunchAttemptArgumentPrefix)\(nextAutomaticRelaunchAttempt)")
        }

        return launchArguments
    }
}
