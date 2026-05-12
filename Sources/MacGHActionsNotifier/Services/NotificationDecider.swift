import Foundation

struct WorkflowNotification: Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var url: URL
    var repositoryFullName: String
    var workflowName: String
    var kind: WorkflowNotificationKind
}

enum WorkflowNotificationKind: String, Equatable {
    case started
    case succeeded
    case failed
    case cancelled
}

enum NotificationDecider {
    static func notification(
        previous: WorkflowRun?,
        current: WorkflowRun,
        repositoryWasPrimed: Bool,
        repositoryFullName: String,
        preferences: NotificationPreferences
    ) -> WorkflowNotification? {
        guard let previous else {
            guard repositoryWasPrimed else { return nil }
            return notificationForCurrentState(
                current,
                repositoryFullName: repositoryFullName,
                preferences: preferences
            )
        }

        return notification(
            previous: previous,
            current: current,
            repositoryFullName: repositoryFullName,
            preferences: preferences
        )
    }

    static func notification(
        previous: WorkflowRun?,
        current: WorkflowRun,
        repositoryFullName: String,
        preferences: NotificationPreferences
    ) -> WorkflowNotification? {
        guard let previous else {
            return nil
        }
        guard previous.id != current.id || previous.effectiveState != current.effectiveState else {
            return nil
        }

        return notificationForCurrentState(
            current,
            repositoryFullName: repositoryFullName,
            preferences: preferences
        )
    }

    private static func notificationForCurrentState(
        _ current: WorkflowRun,
        repositoryFullName: String,
        preferences: NotificationPreferences
    ) -> WorkflowNotification? {
        switch current.effectiveState {
        case .running where preferences.notifyOnStarted:
            return WorkflowNotification(
                title: "Workflow started",
                body: notificationBody(for: current, repositoryFullName: repositoryFullName, action: "is running"),
                url: current.htmlURL,
                repositoryFullName: repositoryFullName,
                workflowName: current.name,
                kind: .started
            )
        case .succeeded where preferences.notifyOnSucceeded:
            return WorkflowNotification(
                title: "Workflow succeeded",
                body: notificationBody(for: current, repositoryFullName: repositoryFullName, action: "completed successfully"),
                url: current.htmlURL,
                repositoryFullName: repositoryFullName,
                workflowName: current.name,
                kind: .succeeded
            )
        case .failed where preferences.notifyOnFailed:
            return WorkflowNotification(
                title: "Workflow failed",
                body: notificationBody(for: current, repositoryFullName: repositoryFullName, action: "failed"),
                url: current.failurePreview?.htmlURL ?? current.htmlURL,
                repositoryFullName: repositoryFullName,
                workflowName: current.name,
                kind: .failed
            )
        case .cancelled where preferences.notifyOnCancelled:
            return WorkflowNotification(
                title: "Workflow cancelled",
                body: notificationBody(for: current, repositoryFullName: repositoryFullName, action: "was cancelled"),
                url: current.htmlURL,
                repositoryFullName: repositoryFullName,
                workflowName: current.name,
                kind: .cancelled
            )
        default:
            return nil
        }
    }

    private static func notificationBody(for run: WorkflowRun, repositoryFullName: String, action: String) -> String {
        var body = "\(repositoryFullName) - \(run.name) #\(run.runNumber) \(action)"
        if let triggeredBy = run.triggeredBy {
            body += " by \(triggeredBy)"
        }
        if !run.branch.isEmpty {
            body += " on \(run.branch)"
        }
        if let failurePreview = run.failurePreview, run.effectiveState == .failed {
            body += ". Failed at \(failurePreview.displayText)"
        } else {
            body += "."
        }
        return body
    }
}
