import Foundation

struct WorkflowMonitorResult {
    var latestRuns: [RepositoryWorkflowKey: WorkflowRun]
    var errorMessage: String?
}

final class WorkflowMonitor: @unchecked Sendable {
    private let apiClient: GitHubAPIClient
    private let notificationService: NotificationService
    private var task: Task<Void, Never>?
    private var previousRuns: [RepositoryWorkflowKey: WorkflowRun] = [:]

    init(apiClient: GitHubAPIClient, notificationService: NotificationService) {
        self.apiClient = apiClient
        self.notificationService = notificationService
    }

    func start(configuration: AppConfiguration, onUpdate: @escaping @MainActor (WorkflowMonitorResult) async -> Void) {
        stop()
        let normalized = configuration.normalized()
        guard !normalized.monitoredRepositories.isEmpty else { return }

        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let snapshots = try await self.refresh(configuration: normalized)
                    await onUpdate(WorkflowMonitorResult(
                        latestRuns: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key, $0.run) }),
                        errorMessage: nil
                    ))
                } catch {
                    await onUpdate(WorkflowMonitorResult(
                        latestRuns: self.previousRuns,
                        errorMessage: ErrorPresenter.message(for: error)
                    ))
                }
                let seconds = UInt64(normalized.pollingIntervalSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: seconds)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh(configuration: AppConfiguration) async throws -> [WorkflowSnapshot] {
        let normalized = configuration.normalized()
        var snapshots: [WorkflowSnapshot] = []

        for repository in normalized.monitoredRepositories {
            for workflow in repository.workflows {
                let key = RepositoryWorkflowKey(owner: repository.owner, repository: repository.name, workflowIdentifier: workflow.identifier)
                if let run = try await apiClient.latestRun(owner: repository.owner, repository: repository.name, workflow: workflow) {
                    if let notification = NotificationDecider.notification(
                        previous: previousRuns[key],
                        current: run,
                        repositoryFullName: repository.fullName,
                        preferences: normalized.notificationPreferences
                    ) {
                        await notificationService.deliver(notification)
                    }
                    previousRuns[key] = run
                    snapshots.append(WorkflowSnapshot(key: key, run: run))
                }
            }
        }

        return snapshots
    }
}
