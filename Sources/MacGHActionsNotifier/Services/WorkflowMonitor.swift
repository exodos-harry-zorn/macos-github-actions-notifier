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
    private var previousRunStates: [String: WorkflowRun] = [:]
    private var primedRepositories: Set<RepositoryWorkflowKey> = []

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
            let runs = try await apiClient.recentRuns(owner: repository.owner, repository: repository.name)
            let repositoryKey = RepositoryWorkflowKey.repository(owner: repository.owner, repository: repository.name)
            let repositoryWasPrimed = primedRepositories.contains(repositoryKey)
            if let latestRun = runs.first {
                previousRuns[repositoryKey] = latestRun
                snapshots.append(WorkflowSnapshot(key: repositoryKey, run: latestRun))
            }

            for run in runs.reversed() {
                let runKey = "\(repository.fullName)#\(run.id)"
                if let notification = NotificationDecider.notification(
                    previous: previousRunStates[runKey],
                    current: run,
                    repositoryWasPrimed: repositoryWasPrimed,
                    repositoryFullName: repository.fullName,
                    preferences: normalized.notificationPreferences
                ) {
                    await notificationService.deliver(notification)
                }
                previousRunStates[runKey] = run
            }
            primedRepositories.insert(repositoryKey)
        }

        return snapshots
    }
}
