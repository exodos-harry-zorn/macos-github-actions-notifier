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
    var lastErrorMessage: String?
    var isRefreshing = false
    var isAuthenticated = false
    var deviceFlow: DeviceFlowSession?
    var onStatusChanged: ((AppStatus) -> Void)?

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
        configuration = configurationStore.load()
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
            let runs = try await monitor.refresh(configuration: configuration)
            latestRuns = Dictionary(uniqueKeysWithValues: runs.map { ($0.key, $0.run) })
            lastErrorMessage = nil
            isAuthenticated = (try? keychainStore.readToken()) != nil
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
            logger.error("Refresh failed: \(lastErrorMessage ?? "unknown")")
        }
    }

    func saveConfiguration(_ next: AppConfiguration) {
        configuration = next.normalized()
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
            lastErrorMessage = nil
            onStatusChanged?(overallStatus)
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func handleMonitorResult(_ result: WorkflowMonitorResult) async {
        latestRuns = result.latestRuns
        lastErrorMessage = result.errorMessage
        isAuthenticated = (try? keychainStore.readToken()) != nil
        onStatusChanged?(overallStatus)
    }
}
