import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

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
    var availableOrganizations: [GitHubOrganization] = []
    var currentUserLogin: String?
    var isLoadingRepositories = false
    var repositoryLoadMessage: String?
    var lastRefreshDate: Date?
    var lastRateLimit: GitHubRateLimit?
    var configurationMessage: String?
    var onStatusChanged: ((AppStatus) -> Void)?
    var onWorkflowEvent: ((AppStatus) -> Void)?
    var softwareUpdateState: SoftwareUpdateState = .idle
    var softwareUpdateSettings: SoftwareUpdateSettings = .unavailable
    private var softwareUpdateChecker: (any SoftwareUpdateChecking)?

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
        notificationService.onMuteRepository = { [weak self] repository in
            await MainActor.run {
                self?.muteRepository(fullName: repository, duration: 3_600)
            }
        }
    }

    func start() {
        Task {
            await notificationService.requestAuthorizationIfNeeded()
            isAuthenticated = (try? keychainStore.readToken()) != nil
            if isAuthenticated {
                await loadAuthenticatedContext()
            }
            monitor.start(configuration: configuration) { [weak self] result in
                await self?.handleMonitorResult(result)
            }
            await refresh()
        }
    }

    func setSoftwareUpdateChecker(_ checker: any SoftwareUpdateChecking) {
        softwareUpdateChecker = checker
        softwareUpdateSettings = checker.settings
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
            lastRefreshDate = Date()
            lastRateLimit = apiClient.lastRateLimit
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
        monitor.updateCurrentUserLogin(currentUserLogin)
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
            await loadAuthenticatedContext()
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
            currentUserLogin = nil
            availableOrganizations = []
            latestRuns = [:]
            recentRuns = [:]
            lastErrorMessage = nil
            onStatusChanged?(overallStatus)
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    func checkForUpdates() {
        guard let softwareUpdateChecker else {
            softwareUpdateState = .failed("Automatic updates are not available in this build.")
            return
        }
        softwareUpdateChecker.checkForUpdates()
    }

    func checkForUpdateInformation() {
        guard let softwareUpdateChecker else {
            softwareUpdateState = .failed("Automatic updates are not available in this build.")
            return
        }
        softwareUpdateChecker.checkForUpdateInformation()
    }

    func installAvailableUpdate() {
        checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        softwareUpdateChecker?.setAutomaticallyChecksForUpdates(enabled)
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        softwareUpdateChecker?.setAutomaticallyDownloadsUpdates(enabled)
    }

    func applySoftwareUpdateSettings(_ settings: SoftwareUpdateSettings) {
        softwareUpdateSettings = settings
    }

    func loadAuthenticatedContext() async {
        do {
            currentUserLogin = try await apiClient.authenticatedUserLogin()
            monitor.updateCurrentUserLogin(currentUserLogin)
            availableOrganizations = (try? await apiClient.organizations()) ?? []
            if configuration.defaultOwner.isEmpty, let currentUserLogin {
                var updated = configuration
                updated.defaultOwner = currentUserLogin
                configuration = updated.normalized()
                configurationStore.save(configuration)
            }
            if let owner = configuration.defaultOwner.isEmpty ? currentUserLogin : configuration.defaultOwner {
                await loadAvailableRepositories(owner: owner)
            }
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
            lastRateLimit = apiClient.lastRateLimit
            repositoryLoadMessage = availableRepositories.isEmpty ? "No repositories found for \(cleanOwner)." : nil
        } catch {
            repositoryLoadMessage = ErrorPresenter.message(for: error)
        }
    }

    func refreshRateLimit() async {
        do {
            lastRateLimit = try await apiClient.rateLimit()
        } catch {
            lastErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    func muteRepository(fullName: String, duration: TimeInterval) {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        var next = configuration
        next.monitoredRepositories = next.monitoredRepositories.map { repository in
            guard repository.owner == parts[0], repository.name == parts[1] else { return repository }
            var copy = repository
            copy.mutedUntil = Date().addingTimeInterval(duration)
            return copy
        }
        saveConfiguration(next)
    }

    func unmuteRepository(_ repository: MonitoredRepository) {
        var next = configuration
        next.monitoredRepositories = next.monitoredRepositories.map {
            guard $0.id == repository.id else { return $0 }
            var copy = $0
            copy.mutedUntil = nil
            return copy
        }
        saveConfiguration(next)
    }

    func sendTestNotification() {
        Task { await notificationService.deliverTestNotification() }
    }

    func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "GitHub-Actions-Notifier-Config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder.prettyPrinted.encode(configuration.sanitizedForPersistence())
            try data.write(to: url, options: [.atomic])
            configurationMessage = "Configuration exported without secrets."
        } catch {
            configurationMessage = ErrorPresenter.message(for: error)
        }
    }

    func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            var imported = try JSONDecoder().decode(AppConfiguration.self, from: data).normalized()
            imported.githubClientID = configuration.githubClientID
            saveConfiguration(imported)
            configurationMessage = "Configuration imported. Secrets were not changed."
        } catch {
            configurationMessage = ErrorPresenter.message(for: error)
        }
    }

    func copyDebugReport() {
        let report = debugReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        configurationMessage = "Debug report copied without secrets."
    }

    func debugReport() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let repositories = configuration.monitoredRepositories.map(\.fullName).joined(separator: ", ")
        return """
        GitHub Actions Notifier Debug Report
        Version: \(version)
        Authenticated: \(isAuthenticated)
        Current user: \(currentUserLogin ?? "unknown")
        Monitored repositories: \(repositories.isEmpty ? "none" : repositories)
        Last refresh: \(lastRefreshDate.map(String.init(describing:)) ?? "never")
        Rate limit: \(lastRateLimit?.displayText ?? "unknown")
        Update state: \(softwareUpdateState.bannerTitle ?? "quiet")
        Last error: \(lastErrorMessage ?? "none")
        """
    }

    private func handleMonitorResult(_ result: WorkflowMonitorResult) async {
        latestRuns = result.latestRuns
        if !result.recentRuns.isEmpty {
            recentRuns = result.recentRuns
        }
        lastErrorMessage = result.errorMessage
        isAuthenticated = (try? keychainStore.readToken()) != nil
        lastRefreshDate = Date()
        lastRateLimit = apiClient.lastRateLimit
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

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
