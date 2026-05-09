import Foundation

enum SoftwareUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String)
    case failed(String)

    var bannerTitle: String? {
        switch self {
        case .idle, .checking, .upToDate:
            return nil
        case .updateAvailable(let version):
            return "Update \(version) available"
        case .failed:
            return "Update check needs attention"
        }
    }

    var bannerSubtitle: String? {
        switch self {
        case .idle:
            return nil
        case .checking:
            return "Checking for a new release."
        case .upToDate:
            return "You are running the latest release."
        case .updateAvailable:
            return "Install the latest release without downloading a DMG manually."
        case .failed(let message):
            return message
        }
    }

    var canInstallUpdate: Bool {
        if case .updateAvailable = self {
            return true
        }
        return false
    }
}

struct SoftwareUpdateSettings: Equatable {
    var isAvailable: Bool
    var automaticallyChecksForUpdates: Bool
    var automaticallyDownloadsUpdates: Bool
    var allowsAutomaticUpdates: Bool
    var canCheckForUpdates: Bool
    var lastUpdateCheckDate: Date?

    static let unavailable = SoftwareUpdateSettings(
        isAvailable: false,
        automaticallyChecksForUpdates: false,
        automaticallyDownloadsUpdates: false,
        allowsAutomaticUpdates: false,
        canCheckForUpdates: false,
        lastUpdateCheckDate: nil
    )
}

@MainActor
protocol SoftwareUpdateChecking: AnyObject {
    var settings: SoftwareUpdateSettings { get }

    func start()
    func checkForUpdates()
    func checkForUpdateInformation()
    func setAutomaticallyChecksForUpdates(_ enabled: Bool)
    func setAutomaticallyDownloadsUpdates(_ enabled: Bool)
}
