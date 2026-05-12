import Foundation

struct AppConfiguration: Codable, Equatable {
    var githubClientID: String
    var defaultOwner: String
    var monitoredRepositories: [MonitoredRepository]
    var notificationPreferences: NotificationPreferences
    var pollingIntervalSeconds: TimeInterval
    var recentRunsPerRepository: Int

    init(
        githubClientID: String,
        defaultOwner: String,
        monitoredRepositories: [MonitoredRepository],
        notificationPreferences: NotificationPreferences,
        pollingIntervalSeconds: TimeInterval,
        recentRunsPerRepository: Int = 5
    ) {
        self.githubClientID = githubClientID
        self.defaultOwner = defaultOwner
        self.monitoredRepositories = monitoredRepositories
        self.notificationPreferences = notificationPreferences
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.recentRunsPerRepository = recentRunsPerRepository
    }

    enum CodingKeys: String, CodingKey {
        case githubClientID
        case defaultOwner
        case monitoredRepositories
        case notificationPreferences
        case pollingIntervalSeconds
        case recentRunsPerRepository
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        githubClientID = try container.decodeIfPresent(String.self, forKey: .githubClientID) ?? ""
        defaultOwner = try container.decodeIfPresent(String.self, forKey: .defaultOwner) ?? ""
        monitoredRepositories = try container.decodeIfPresent([MonitoredRepository].self, forKey: .monitoredRepositories) ?? []
        notificationPreferences = try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? .default
        pollingIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingIntervalSeconds) ?? 180
        recentRunsPerRepository = try container.decodeIfPresent(Int.self, forKey: .recentRunsPerRepository) ?? 5
    }

    static let `default` = AppConfiguration(
        githubClientID: "",
        defaultOwner: "",
        monitoredRepositories: [],
        notificationPreferences: .default,
        pollingIntervalSeconds: 180,
        recentRunsPerRepository: 5
    )

    func normalized() -> AppConfiguration {
        var copy = self
        copy.githubClientID = githubClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.defaultOwner = defaultOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.pollingIntervalSeconds = max(60, min(900, pollingIntervalSeconds))
        copy.recentRunsPerRepository = max(1, min(20, recentRunsPerRepository))
        copy.notificationPreferences = notificationPreferences.normalized()
        copy.monitoredRepositories = monitoredRepositories.map { $0.normalized() }.filter { !$0.owner.isEmpty && !$0.name.isEmpty }
        return copy
    }

    func sanitizedForPersistence() -> AppConfiguration {
        var copy = normalized()
        copy.githubClientID = ""
        return copy
    }
}

struct MonitoredRepository: Codable, Identifiable, Hashable {
    var id: UUID
    var owner: String
    var name: String
    var workflows: [MonitoredWorkflow]
    var branchFilters: [String]
    var deploymentWorkflowPatterns: [String]
    var mutedUntil: Date?

    init(
        id: UUID = UUID(),
        owner: String,
        name: String,
        workflows: [MonitoredWorkflow] = [],
        branchFilters: [String] = [],
        deploymentWorkflowPatterns: [String] = [],
        mutedUntil: Date? = nil
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.workflows = workflows
        self.branchFilters = branchFilters
        self.deploymentWorkflowPatterns = deploymentWorkflowPatterns
        self.mutedUntil = mutedUntil
    }

    var fullName: String {
        "\(owner)/\(name)"
    }

    func normalized() -> MonitoredRepository {
        MonitoredRepository(
            id: id,
            owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            workflows: workflows.map { $0.normalized() }.filter { !$0.identifier.isEmpty },
            branchFilters: branchFilters.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            deploymentWorkflowPatterns: deploymentWorkflowPatterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            mutedUntil: mutedUntil
        )
    }
}

struct MonitoredWorkflow: Codable, Identifiable, Hashable {
    var id: UUID
    var identifier: String
    var displayName: String
    var deploymentRelated: Bool

    init(id: UUID = UUID(), identifier: String, displayName: String = "", deploymentRelated: Bool = false) {
        self.id = id
        self.identifier = identifier
        self.displayName = displayName
        self.deploymentRelated = deploymentRelated
    }

    func normalized() -> MonitoredWorkflow {
        let cleanIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return MonitoredWorkflow(
            id: id,
            identifier: cleanIdentifier,
            displayName: cleanName.isEmpty ? cleanIdentifier : cleanName,
            deploymentRelated: deploymentRelated
        )
    }
}

struct NotificationPreferences: Codable, Equatable {
    var notifyOnStarted: Bool
    var notifyOnSucceeded: Bool
    var notifyOnFailed: Bool
    var notifyOnCancelled: Bool
    var quietHoursEnabled: Bool
    var quietHoursStartHour: Int
    var quietHoursEndHour: Int
    var notifyOnlyForCurrentUser: Bool
    var groupFailures: Bool

    static let `default` = NotificationPreferences(
        notifyOnStarted: true,
        notifyOnSucceeded: true,
        notifyOnFailed: true,
        notifyOnCancelled: true,
        quietHoursEnabled: false,
        quietHoursStartHour: 18,
        quietHoursEndHour: 8,
        notifyOnlyForCurrentUser: false,
        groupFailures: true
    )

    enum CodingKeys: String, CodingKey {
        case notifyOnStarted
        case notifyOnSucceeded
        case notifyOnFailed
        case notifyOnCancelled
        case quietHoursEnabled
        case quietHoursStartHour
        case quietHoursEndHour
        case notifyOnlyForCurrentUser
        case groupFailures
    }

    init(
        notifyOnStarted: Bool,
        notifyOnSucceeded: Bool,
        notifyOnFailed: Bool,
        notifyOnCancelled: Bool,
        quietHoursEnabled: Bool = false,
        quietHoursStartHour: Int = 18,
        quietHoursEndHour: Int = 8,
        notifyOnlyForCurrentUser: Bool = false,
        groupFailures: Bool = true
    ) {
        self.notifyOnStarted = notifyOnStarted
        self.notifyOnSucceeded = notifyOnSucceeded
        self.notifyOnFailed = notifyOnFailed
        self.notifyOnCancelled = notifyOnCancelled
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartHour = quietHoursStartHour
        self.quietHoursEndHour = quietHoursEndHour
        self.notifyOnlyForCurrentUser = notifyOnlyForCurrentUser
        self.groupFailures = groupFailures
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifyOnStarted = try container.decodeIfPresent(Bool.self, forKey: .notifyOnStarted) ?? true
        notifyOnSucceeded = try container.decodeIfPresent(Bool.self, forKey: .notifyOnSucceeded) ?? true
        notifyOnFailed = try container.decodeIfPresent(Bool.self, forKey: .notifyOnFailed) ?? true
        notifyOnCancelled = try container.decodeIfPresent(Bool.self, forKey: .notifyOnCancelled) ?? true
        quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? false
        quietHoursStartHour = try container.decodeIfPresent(Int.self, forKey: .quietHoursStartHour) ?? 18
        quietHoursEndHour = try container.decodeIfPresent(Int.self, forKey: .quietHoursEndHour) ?? 8
        notifyOnlyForCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .notifyOnlyForCurrentUser) ?? false
        groupFailures = try container.decodeIfPresent(Bool.self, forKey: .groupFailures) ?? true
    }

    func normalized() -> NotificationPreferences {
        var copy = self
        copy.quietHoursStartHour = max(0, min(23, quietHoursStartHour))
        copy.quietHoursEndHour = max(0, min(23, quietHoursEndHour))
        return copy
    }
}
