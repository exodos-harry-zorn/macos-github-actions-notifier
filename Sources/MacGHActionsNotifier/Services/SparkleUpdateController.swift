import Foundation
import Sparkle

@MainActor
final class SparkleUpdateController: NSObject, SoftwareUpdateChecking, SPUUpdaterDelegate {
    private weak var appModel: AppModel?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
    }

    var settings: SoftwareUpdateSettings {
        let updater = updaterController.updater
        return SoftwareUpdateSettings(
            isAvailable: true,
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            automaticallyDownloadsUpdates: updater.automaticallyDownloadsUpdates,
            allowsAutomaticUpdates: updater.allowsAutomaticUpdates,
            canCheckForUpdates: updater.canCheckForUpdates,
            lastUpdateCheckDate: updater.lastUpdateCheckDate
        )
    }

    func start() {
        updaterController.startUpdater()
        _ = updaterController.updater.clearFeedURLFromUserDefaults()
        appModel?.applySoftwareUpdateSettings(settings)
        if updaterController.updater.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdateInformation()
        }
    }

    func checkForUpdates() {
        appModel?.softwareUpdateState = .checking
        updaterController.checkForUpdates(nil)
        appModel?.applySoftwareUpdateSettings(settings)
    }

    func checkForUpdateInformation() {
        appModel?.softwareUpdateState = .checking
        updaterController.updater.checkForUpdateInformation()
        appModel?.applySoftwareUpdateSettings(settings)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        appModel?.applySoftwareUpdateSettings(settings)
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        appModel?.applySoftwareUpdateSettings(settings)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        appModel?.softwareUpdateState = .updateAvailable(version: item.displayVersionString)
        appModel?.applySoftwareUpdateSettings(settings)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        appModel?.softwareUpdateState = .upToDate
        appModel?.applySoftwareUpdateSettings(settings)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        appModel?.softwareUpdateState = .upToDate
        appModel?.applySoftwareUpdateSettings(settings)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let state = SoftwareUpdateState.finishedUpdateCycle(error: error) {
            appModel?.softwareUpdateState = state
        }
        appModel?.applySoftwareUpdateSettings(settings)
    }
}
