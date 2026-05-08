import Foundation
import OSLog

struct AppLogger {
    private let logger: Logger

    init(category: String) {
        logger = Logger(subsystem: "com.exodoslabs.MacGHActionsNotifier", category: category)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
