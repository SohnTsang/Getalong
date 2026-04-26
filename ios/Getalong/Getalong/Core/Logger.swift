import Foundation
import OSLog

enum GALog {
    static let app      = Logger(subsystem: subsystem, category: "app")
    static let auth     = Logger(subsystem: subsystem, category: "auth")
    static let invite   = Logger(subsystem: subsystem, category: "invite")
    static let chat     = Logger(subsystem: subsystem, category: "chat")
    static let media    = Logger(subsystem: subsystem, category: "media")
    static let net      = Logger(subsystem: subsystem, category: "network")
    static let push     = Logger(subsystem: subsystem, category: "push")

    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.getalong.app"
}
