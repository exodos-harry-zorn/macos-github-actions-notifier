import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    private let appModel = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusBarController(appModel: appModel)
        appModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.stop()
    }
}
