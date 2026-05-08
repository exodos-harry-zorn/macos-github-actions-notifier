import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let configurationStore: any ConfigurationStore
    private let keychainStore: any KeychainStore
    private let apiClient: GitHubAPIClient
    private let notificationService: NotificationService
    private let monitor: WorkflowMonitor
    private let logger = AppLogger(category: "AppModel")

    var configuration: AppConfiguration
    var latestRuns: [RepositoryWorkflowKey: WorkflowRun] = [:]
    var recentRuns: [RepositoryWorkflowKey: [WorkflowRun]] = [:]
    var lastErrorMessage: String?
    var isRefreshing = false
    var isAuthenticated = false
    var deviceFlow: DeviceFlowSession?
    var availableRepositories: [GitHubRepository] = []
    var isLoadingRepositories = false
    var repositoryLoadMessage: String?
    var onStatusChanged: ((AppStatus) -> Void)?
    var onWorkflowEvent: ((AppStatus) -> Void)?

    var overallStatus: AppStatus {
        if lastErrorMessage != nil { return .problem }
        if !isAuthenticated { return .problem }
        return StatusAggregator.status(for: Array(latestRuns.values))
    }

    init(
        configurationStore: any ConfigurationStore = UserDefaultsConfigurationStore(),
        keychainStore: any KeychainStore = KeychainTokenStore()
    ) {
        self.configurationStore = configurationStore
        self.keychainStore = keychainStore
        configuration = AppModel.loadConfiguration(configurationStore: configurationStore, keychainStore: keychainStore)
        apiClient = GitHubAPIClient(tokenProvider: keychainStore)
        notificationService = NotificationService()
        monitor = WorkflowMonitor(apiClient: apiClient, notificationService: notificationService)
    }

    func start() {
        Task {
            await notificationService.requestAuthorizationIfNeeded()
            isAuthenticated = (try? keychainStore.readToken()) != nil
            monitor.start(configuration: configuration) { [weak self] result in
                await self?.handleMonitorResult(result)
            }
            await refresh()
        }
    }

    func stop() {
        monitor.stop()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            onStatusChanged?(overallStatus)
        }

        do {
            let snapshots = try await monitor.refresh(configuration: configuration)
            latestRuns = Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot in
                snapshot.run.map { (snapshot.key, $0) }
            })
            recentRuns = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key, $0.runs) })
            lastErrorMessage = nil
            isAuthenticated = (try? keychainStore.readToken()) != nil
            if let eventStatus = monitor.consumeLastEventStatus() {
                onWorkflowEvent?(eventStatus)
            }
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
            logger.error("Refresh failed: \(lastErrorMessage ?? "unknown")")
        }
    }

    func saveConfiguration(_ next: AppConfiguration) {
        let normalized = next.normalized()
        do {
            if normalized.githubClientID.isEmpty {
                try keychainStore.deleteClientID()
            } else {
                try keychainStore.saveClientID(normalized.githubClientID)
            }
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
            logger.error("Failed to update OAuth client ID in Keychain: \(lastErrorMessage ?? "unknown")")
        }
        configuration = normalized
        configurationStore.save(configuration)
        monitor.start(configuration: configuration) { [weak self] result in
            await self?.handleMonitorResult(result)
        }
        Task { await refresh() }
    }

    func beginDeviceAuthorization(privateRepoAccess: Bool) async {
        do {
            let clientID = configuration.githubClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clientID.isEmpty else {
                lastErrorMessage = "Enter a GitHub OAuth client ID before signing in."
                return
            }
            let authenticator = GitHubDeviceAuthenticator(clientID: clientID, tokenStore: keychainStore)
            let session = try await authenticator.requestDeviceCode(scopes: privateRepoAccess ? ["repo"] : [])
            deviceFlow = session
            lastErrorMessage = nil
            NSWorkspace.shared.open(session.verificationURI)
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    func completeDeviceAuthorization() async {
        guard let session = deviceFlow else { return }
        do {
            let authenticator = GitHubDeviceAuthenticator(clientID: configuration.githubClientID, tokenStore: keychainStore)
            try await authenticator.pollForToken(session: session)
            deviceFlow = nil
            isAuthenticated = true
            lastErrorMessage = nil
            if !configuration.defaultOwner.isEmpty {
                await loadAvailableRepositories(owner: configuration.defaultOwner)
            }
            await refresh()
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    func logout() {
        do {
            try keychainStore.deleteToken()
            isAuthenticated = false
            latestRuns = [:]
            recentRuns = [:]
            lastErrorMessage = nil
            onStatusChanged?(overallStatus)
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    func loadAvailableRepositories(owner: String) async {
        let cleanOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAuthenticated else {
            repositoryLoadMessage = "Sign in with GitHub before loading repositories."
            return
        }
        guard !cleanOwner.isEmpty else {
            repositoryLoadMessage = "Enter a GitHub account or organization first."
            return
        }

        isLoadingRepositories = true
        repositoryLoadMessage = nil
        defer { isLoadingRepositories = false }

        do {
            availableRepositories = try await apiClient.repositories(owner: cleanOwner)
            repositoryLoadMessage = availableRepositories.isEmpty ? "No repositories found for \(cleanOwner)." : nil
        } catch {
            repositoryLoadMessage = ErrorPresenter.message(for: error)
        }
    }

    private func handleMonitorResult(_ result: WorkflowMonitorResult) async {
        latestRuns = result.latestRuns
        if !result.recentRuns.isEmpty {
            recentRuns = result.recentRuns
        }
        lastErrorMessage = result.errorMessage
        isAuthenticated = (try? keychainStore.readToken()) != nil
        if let eventStatus = result.eventStatus {
            onWorkflowEvent?(eventStatus)
        }
        onStatusChanged?(overallStatus)
    }

    private static func loadConfiguration(
        configurationStore: any ConfigurationStore,
        keychainStore: any KeychainStore
    ) -> AppConfiguration {
        var loaded = configurationStore.load().normalized()
        if let keychainClientID = try? keychainStore.readClientID() {
            loaded.githubClientID = keychainClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            return loaded
        }

        let migratedClientID = loaded.githubClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !migratedClientID.isEmpty {
            try? keychainStore.saveClientID(migratedClientID)
            loaded.githubClientID = migratedClientID
            configurationStore.save(loaded)
        }
        return loaded
    }
}
