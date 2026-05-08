import Foundation

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if condition() {
        return true
    }
    FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
    exit(1)
}

func makeRun(
    id: Int64 = Int64.random(in: 1...999),
    status: WorkflowRunStatus,
    conclusion: WorkflowRunConclusion?
) -> WorkflowRun {
    WorkflowRun(
        id: id,
        workflowID: 1,
        name: "CI",
        displayTitle: "CI",
        status: status,
        conclusion: conclusion,
        htmlURL: URL(string: "https://github.com/example/repo/actions/runs/\(id)")!,
        branch: "main",
        runNumber: 10,
        createdAt: Date(),
        updatedAt: Date()
    )
}

@main
struct LogicTests {
    static func main() {
        expect(StatusAggregator.status(for: []) == .idle, "empty runs are idle")
        expect(StatusAggregator.status(for: [
            makeRun(status: .completed, conclusion: .success),
            makeRun(status: .completed, conclusion: .failure)
        ]) == .failed, "failed runs take priority")
        expect(StatusAggregator.status(for: [
            makeRun(status: .completed, conclusion: .success),
            makeRun(status: .inProgress, conclusion: nil)
        ]) == .running, "running takes priority over success")

        let repeatedRun = makeRun(id: 1, status: .inProgress, conclusion: nil)
        expect(NotificationDecider.notification(
            previous: repeatedRun,
            current: repeatedRun,
            repositoryFullName: "exodos/repo",
            preferences: .default
        ) == nil, "same run and state does not notify")

        let startedRun = makeRun(id: 2, status: .inProgress, conclusion: nil)
        expect(NotificationDecider.notification(
            previous: nil,
            current: startedRun,
            repositoryFullName: "exodos/repo",
            preferences: .default
        )?.title == "Workflow started", "new running workflow notifies as started")

        var preferences = NotificationPreferences.default
        preferences.notifyOnSucceeded = false
        let successRun = makeRun(id: 3, status: .completed, conclusion: .success)
        expect(NotificationDecider.notification(
            previous: nil,
            current: successRun,
            repositoryFullName: "exodos/repo",
            preferences: preferences
        ) == nil, "success preference suppresses success notifications")

        let config = AppConfiguration(
            githubClientID: " abc ",
            defaultOwner: " org ",
            monitoredRepositories: [
                MonitoredRepository(owner: " exodos ", name: " repo ", workflows: [
                    MonitoredWorkflow(identifier: " ci.yml ", displayName: "")
                ])
            ],
            notificationPreferences: .default,
            pollingIntervalSeconds: 10
        ).normalized()
        expect(config.githubClientID == "abc", "client ID is trimmed")
        expect(config.defaultOwner == "org", "default owner is trimmed")
        expect(config.pollingIntervalSeconds == 60, "polling interval is clamped")
        expect(config.monitoredRepositories.first?.owner == "exodos", "owner is trimmed")
        expect(config.monitoredRepositories.first?.workflows.first?.displayName == "ci.yml", "workflow display defaults to identifier")

        print("Logic tests passed")
    }
}
