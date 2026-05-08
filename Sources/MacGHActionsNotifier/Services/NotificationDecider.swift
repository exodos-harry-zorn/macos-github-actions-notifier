import Foundation

struct WorkflowNotification: Equatable {
    var title: String
    var body: String
    var url: URL
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
                body: "\(repositoryFullName) - \(current.name) #\(current.runNumber) is running on \(current.branch).",
                url: current.htmlURL
            )
        case .succeeded where preferences.notifyOnSucceeded:
            return WorkflowNotification(
                title: "Workflow succeeded",
                body: "\(repositoryFullName) - \(current.name) #\(current.runNumber) completed successfully.",
                url: current.htmlURL
            )
        case .failed where preferences.notifyOnFailed:
            return WorkflowNotification(
                title: "Workflow failed",
                body: "\(repositoryFullName) - \(current.name) #\(current.runNumber) failed.",
                url: current.htmlURL
            )
        case .cancelled where preferences.notifyOnCancelled:
            return WorkflowNotification(
                title: "Workflow cancelled",
                body: "\(repositoryFullName) - \(current.name) #\(current.runNumber) was cancelled.",
                url: current.htmlURL
            )
        default:
            return nil
        }
    }
}
