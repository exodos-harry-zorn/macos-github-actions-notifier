import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    private let appModel = AppModel()
    private var updateController: SparkleUpdateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
        let updateController = SparkleUpdateController(appModel: appModel)
        self.updateController = updateController
        appModel.setSoftwareUpdateChecker(updateController)
        statusController = StatusBarController(appModel: appModel)
        appModel.start()
        updateController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.stop()
    }
}
