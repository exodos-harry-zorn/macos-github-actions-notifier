import AppKit
import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private enum Action {
        static let openRun = "OPEN_RUN"
        static let muteRepository = "MUTE_REPOSITORY_1H"
        static let workflowEventCategory = "WORKFLOW_EVENT"
    }

    private let center = UNUserNotificationCenter.current()
    var onMuteRepository: (@Sendable (String) async -> Void)?

    override init() {
        super.init()
        center.delegate = self
        configureCategories()
    }

    func requestAuthorizationIfNeeded() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ notification: WorkflowNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = Action.workflowEventCategory
        content.userInfo = [
            "url": notification.url.absoluteString,
            "repository": notification.repositoryFullName
        ]

        let request = UNNotificationRequest(
            identifier: "\(notification.url.absoluteString)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func deliverTestNotification() async {
        await deliver(WorkflowNotification(
            title: "Test notification",
            body: "GitHub Actions Notifier notifications are working.",
            url: URL(string: "https://github.com/exodos-harry-zorn/macos-github-actions-notifier")!,
            repositoryFullName: "test",
            workflowName: "Test",
            kind: .succeeded
        ))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == Action.muteRepository,
           let repository = response.notification.request.content.userInfo["repository"] as? String {
            await onMuteRepository?(repository)
            return
        }
        guard let rawURL = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: rawURL) else { return }
        _ = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func configureCategories() {
        let open = UNNotificationAction(identifier: Action.openRun, title: "Open Run", options: [.foreground])
        let mute = UNNotificationAction(identifier: Action.muteRepository, title: "Mute Repo 1h", options: [])
        let category = UNNotificationCategory(
            identifier: Action.workflowEventCategory,
            actions: [open, mute],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }
}
