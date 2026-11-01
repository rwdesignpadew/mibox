import Foundation

enum SharedSettings {
    static let appGroup = "group.pl.miboxscreen.ios"
    static let serverURLKey = "serverURL"
    static let roomCodeKey = "roomCode"

    static var defaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            fatalError("App Group \(appGroup) is not configured")
        }
        return defaults
    }
}

