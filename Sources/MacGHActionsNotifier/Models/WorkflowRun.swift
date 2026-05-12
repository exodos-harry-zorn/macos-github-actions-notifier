import Foundation

struct RepositoryWorkflowKey: Codable, Hashable, Identifiable {
    var owner: String
    var repository: String
    var workflowIdentifier: String

    static func repository(owner: String, repository: String) -> RepositoryWorkflowKey {
        RepositoryWorkflowKey(owner: owner, repository: repository, workflowIdentifier: "all")
    }

    var id: String {
        "\(owner)/\(repository):\(workflowIdentifier)"
    }
}

struct WorkflowSnapshot: Equatable {
    var key: RepositoryWorkflowKey
    var runs: [WorkflowRun]

    var run: WorkflowRun? {
        runs.first
    }
}

struct WorkflowRun: Codable, Equatable, Identifiable {
    var id: Int64
    var workflowID: Int64
    var name: String
    var displayTitle: String
    var status: WorkflowRunStatus
    var conclusion: WorkflowRunConclusion?
    var htmlURL: URL
    var branch: String
    var runNumber: Int
    var createdAt: Date
    var updatedAt: Date
    var triggeredBy: String?
    var event: String?
    var pullRequests: [WorkflowPullRequest]
    var failurePreview: WorkflowFailurePreview?
    var durationSeconds: TimeInterval?
    var isDeployment: Bool

    var effectiveState: WorkflowEffectiveState {
        switch status {
        case .queued, .inProgress, .waiting, .requested, .pending:
            return .running
        case .completed:
            switch conclusion {
            case .success: return .succeeded
            case .cancelled: return .cancelled
            case .failure, .timedOut, .actionRequired, .startupFailure: return .failed
            case .skipped, .neutral: return .succeeded
            case nil: return .running
            }
        case .unknown:
            return .problem
        }
    }
}

struct WorkflowPullRequest: Codable, Equatable, Identifiable {
    var number: Int
    var htmlURL: URL?
    var title: String?

    var id: Int { number }
}

struct WorkflowFailurePreview: Codable, Equatable {
    var jobName: String
    var stepName: String?
    var htmlURL: URL?

    var displayText: String {
        if let stepName, !stepName.isEmpty {
            return "\(jobName) / \(stepName)"
        }
        return jobName
    }
}

enum WorkflowRunStatus: String, Codable, Equatable {
    case queued
    case inProgress = "in_progress"
    case completed
    case waiting
    case requested
    case pending
    case unknown
}

enum WorkflowRunConclusion: String, Codable, Equatable {
    case success
    case failure
    case cancelled
    case skipped
    case timedOut = "timed_out"
    case actionRequired = "action_required"
    case neutral
    case startupFailure = "startup_failure"
}

enum WorkflowEffectiveState: String, Codable, Equatable {
    case running
    case succeeded
    case failed
    case cancelled
    case problem
}
