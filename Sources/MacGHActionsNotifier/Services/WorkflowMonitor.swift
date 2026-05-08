import Foundation

struct WorkflowMonitorResult {
    var latestRuns: [RepositoryWorkflowKey: WorkflowRun]
    var recentRuns: [RepositoryWorkflowKey: [WorkflowRun]]
    var eventStatus: AppStatus?
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
                    let latestRuns = Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot in
                        snapshot.run.map { (snapshot.key, $0) }
                    })
                    await onUpdate(WorkflowMonitorResult(
                        latestRuns: latestRuns,
                        recentRuns: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key, $0.runs) }),
                        eventStatus: self.lastEventStatus,
                        errorMessage: nil
                    ))
                    self.lastEventStatus = nil
                } catch {
                    await onUpdate(WorkflowMonitorResult(
                        latestRuns: self.previousRuns,
                        recentRuns: [:],
                        eventStatus: nil,
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
        lastEventStatus = nil

        for repository in normalized.monitoredRepositories {
            let runs = try await apiClient.recentRuns(owner: repository.owner, repository: repository.name, limit: normalized.recentRunsPerRepository)
            let repositoryKey = RepositoryWorkflowKey.repository(owner: repository.owner, repository: repository.name)
            let repositoryWasPrimed = primedRepositories.contains(repositoryKey)
            if let latestRun = runs.first {
                previousRuns[repositoryKey] = latestRun
            }
            snapshots.append(WorkflowSnapshot(key: repositoryKey, runs: runs))

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
                    lastEventStatus = AppStatus.workflowEventStatus(for: run.effectiveState)
                }
                previousRunStates[runKey] = run
            }
            primedRepositories.insert(repositoryKey)
        }

        return snapshots
    }

    func consumeLastEventStatus() -> AppStatus? {
        defer { lastEventStatus = nil }
        return lastEventStatus
    }

    private var lastEventStatus: AppStatus?
}
