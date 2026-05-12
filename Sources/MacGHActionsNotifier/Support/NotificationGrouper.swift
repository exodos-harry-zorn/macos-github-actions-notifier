import Foundation

enum NotificationGrouper {
    static func grouped(_ notifications: [WorkflowNotification], groupFailures: Bool) -> [WorkflowNotification] {
        guard groupFailures else { return notifications }
        var output: [WorkflowNotification] = []
        let groupedFailures = Dictionary(grouping: notifications.filter { $0.kind == .failed }, by: \.repositoryFullName)
        let groupedFailureIDs = Set(groupedFailures.values.flatMap { $0.map(\.id) })

        output.append(contentsOf: notifications.filter { !groupedFailureIDs.contains($0.id) })

        for (repository, failures) in groupedFailures.sorted(by: { $0.key < $1.key }) {
            guard let first = failures.first else { continue }
            if failures.count == 1 {
                output.append(first)
            } else {
                let names = failures.prefix(3).map(\.workflowName).joined(separator: ", ")
                output.append(WorkflowNotification(
                    title: "\(failures.count) workflows failed",
                    body: "\(repository): \(names)",
                    url: first.url,
                    repositoryFullName: repository,
                    workflowName: first.workflowName,
                    kind: .failed
                ))
            }
        }

        return output
    }
}
