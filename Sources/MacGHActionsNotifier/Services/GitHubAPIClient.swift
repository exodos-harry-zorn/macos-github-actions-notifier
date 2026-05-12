import Foundation

protocol TokenProvider: Sendable {
    func readToken() throws -> String
}

struct GitHubWorkflowResponse: Decodable {
    let workflowRuns: [GitHubWorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct GitHubWorkflowJobsResponse: Decodable {
    let jobs: [GitHubWorkflowJob]
}

struct GitHubRepository: Decodable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let fullName: String
    let isPrivate: Bool
    let htmlURL: URL
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
    }
}

struct GitHubOrganization: Decodable, Identifiable, Hashable {
    let id: Int64
    let login: String
}

private struct GitHubUser: Decodable {
    let login: String
}

struct GitHubWorkflowActor: Decodable {
    let login: String
}

struct GitHubWorkflowRun: Decodable {
    let id: Int64
    let name: String?
    let workflowID: Int64
    let status: String
    let conclusion: String?
    let htmlURL: URL
    let headBranch: String?
    let runNumber: Int
    let displayTitle: String?
    let createdAt: Date
    let updatedAt: Date
    let actor: GitHubWorkflowActor?
    let triggeringActor: GitHubWorkflowActor?
    let event: String?
    let runStartedAt: Date?
    let pullRequests: [GitHubWorkflowPullRequest]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case workflowID = "workflow_id"
        case status
        case conclusion
        case htmlURL = "html_url"
        case headBranch = "head_branch"
        case runNumber = "run_number"
        case displayTitle = "display_title"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case actor
        case triggeringActor = "triggering_actor"
        case event
        case runStartedAt = "run_started_at"
        case pullRequests = "pull_requests"
    }

    func domainModel(fallbackName: String) -> WorkflowRun {
        WorkflowRun(
            id: id,
            workflowID: workflowID,
            name: name ?? fallbackName,
            displayTitle: displayTitle ?? name ?? fallbackName,
            status: WorkflowRunStatus(rawValue: status) ?? .unknown,
            conclusion: conclusion.flatMap(WorkflowRunConclusion.init(rawValue:)),
            htmlURL: htmlURL,
            branch: headBranch ?? "unknown",
            runNumber: runNumber,
            createdAt: createdAt,
            updatedAt: updatedAt,
            triggeredBy: triggeringActor?.login ?? actor?.login,
            event: event,
            pullRequests: (pullRequests ?? []).map(\.domainModel),
            failurePreview: nil,
            durationSeconds: durationSeconds(start: runStartedAt ?? createdAt, end: updatedAt, status: status),
            isDeployment: false
        )
    }

    private func durationSeconds(start: Date, end: Date, status: String) -> TimeInterval? {
        guard status == WorkflowRunStatus.completed.rawValue else { return nil }
        return max(0, end.timeIntervalSince(start))
    }
}

struct GitHubWorkflowPullRequest: Decodable {
    let number: Int
    let url: URL?
    let htmlURL: URL?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case number
        case url
        case htmlURL = "html_url"
        case title
    }

    var domainModel: WorkflowPullRequest {
        WorkflowPullRequest(number: number, htmlURL: htmlURL ?? url, title: title)
    }
}

struct GitHubWorkflowJob: Decodable {
    let name: String
    let htmlURL: URL?
    let status: String
    let conclusion: String?
    let steps: [GitHubWorkflowStep]?

    enum CodingKeys: String, CodingKey {
        case name
        case htmlURL = "html_url"
        case status
        case conclusion
        case steps
    }
}

struct GitHubWorkflowStep: Decodable {
    let name: String
    let status: String
    let conclusion: String?
}

struct GitHubRateLimit: Codable, Equatable {
    var limit: Int
    var remaining: Int
    var used: Int?
    var reset: Date?

    var displayText: String {
        var text = "\(remaining)/\(limit) API calls remaining"
        if let reset {
            text += ", resets \(TimestampFormatter.compact(reset))"
        }
        return text
    }
}

private struct GitHubRateLimitResponse: Decodable {
    let resources: Resources

    struct Resources: Decodable {
        let core: Core
    }

    struct Core: Decodable {
        let limit: Int
        let remaining: Int
        let used: Int?
        let reset: TimeInterval

        var domainModel: GitHubRateLimit {
            GitHubRateLimit(limit: limit, remaining: remaining, used: used, reset: Date(timeIntervalSince1970: reset))
        }
    }
}

final class GitHubAPIClient: @unchecked Sendable {
    private let tokenProvider: any TokenProvider
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = AppLogger(category: "GitHubAPI")
    private let stateLock = NSLock()
    private var rateLimitStorage: GitHubRateLimit?

    var lastRateLimit: GitHubRateLimit? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return rateLimitStorage
    }

    init(tokenProvider: any TokenProvider, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func repositories(owner: String) async throws -> [GitHubRepository] {
        let normalizedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOwner.isEmpty else {
            throw AppError.api("Enter a GitHub account or organization first.")
        }

        do {
            return try await fetchRepositories(path: "orgs/\(encodedPath(normalizedOwner))/repos?type=all&sort=updated&per_page=100")
        } catch AppError.api {
            if let user = try? await authenticatedUser(),
               user.login.caseInsensitiveCompare(normalizedOwner) == .orderedSame {
                return try await fetchRepositories(path: "user/repos?affiliation=owner&visibility=all&sort=updated&per_page=100")
            }
            return try await fetchRepositories(path: "users/\(encodedPath(normalizedOwner))/repos?type=all&sort=updated&per_page=100")
        }
    }

    func authenticatedUserLogin() async throws -> String {
        try await authenticatedUser().login
    }

    func organizations() async throws -> [GitHubOrganization] {
        let url = URL(string: "https://api.github.com/user/orgs?per_page=100")!
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        try validate(response: response, data: data)
        return try decoder.decode([GitHubOrganization].self, from: data)
    }

    func recentRuns(owner: String, repository: String, limit: Int = 20) async throws -> [WorkflowRun] {
        let pageSize = max(1, min(limit, 50))
        let url = URL(string: "https://api.github.com/repos/\(encodedPath(owner))/\(encodedPath(repository))/actions/runs?per_page=\(pageSize)")!
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        try validate(response: response, data: data)
        let decoded = try decoder.decode(GitHubWorkflowResponse.self, from: data)
        var runs = decoded.workflowRuns.map { $0.domainModel(fallbackName: $0.name ?? "Workflow") }
        for index in runs.indices where runs[index].effectiveState == .failed || runs[index].effectiveState == .cancelled {
            runs[index].failurePreview = try? await failurePreview(owner: owner, repository: repository, runID: runs[index].id)
        }
        return runs
    }

    func rateLimit() async throws -> GitHubRateLimit {
        let url = URL(string: "https://api.github.com/rate_limit")!
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        try validate(response: response, data: data)
        let rateLimit = try decoder.decode(GitHubRateLimitResponse.self, from: data).resources.core.domainModel
        updateRateLimit(rateLimit)
        return rateLimit
    }

    private func failurePreview(owner: String, repository: String, runID: Int64) async throws -> WorkflowFailurePreview? {
        let url = URL(string: "https://api.github.com/repos/\(encodedPath(owner))/\(encodedPath(repository))/actions/runs/\(runID)/jobs?per_page=100")!
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        try validate(response: response, data: data)
        let decoded = try decoder.decode(GitHubWorkflowJobsResponse.self, from: data)
        guard let failedJob = decoded.jobs.first(where: { $0.conclusion == "failure" || $0.conclusion == "timed_out" || $0.conclusion == "action_required" || $0.conclusion == "cancelled" }) else {
            return nil
        }
        let failedStep = failedJob.steps?.first { $0.conclusion == "failure" || $0.conclusion == "timed_out" || $0.conclusion == "action_required" || $0.conclusion == "cancelled" }
        return WorkflowFailurePreview(jobName: failedJob.name, stepName: failedStep?.name, htmlURL: failedJob.htmlURL)
    }

    private func fetchRepositories(path: String) async throws -> [GitHubRepository] {
        let url = URL(string: "https://api.github.com/\(path)")!
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        try validate(response: response, data: data)
        return try decoder.decode([GitHubRepository].self, from: data)
    }

    private func authenticatedUser() async throws -> GitHubUser {
        let url = URL(string: "https://api.github.com/user")!
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        try validate(response: response, data: data)
        return try decoder.decode(GitHubUser.self, from: data)
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(try tokenProvider.readToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func encodedPath(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("GitHub returned an invalid response.")
        }
        updateRateLimit(from: http)
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw AppError.authentication("GitHub rejected the stored token. Sign in again.")
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw AppError.rateLimited("GitHub API rate limit reached. The app will try again later.")
            }
            throw AppError.api("GitHub denied access. Check repository permissions and scopes.")
        case 404:
            throw AppError.api("GitHub could not find the configured account, repository, or Actions runs.")
        default:
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            logger.error("GitHub API error \(http.statusCode): \(detail)")
            throw AppError.api("GitHub API error \(http.statusCode).")
        }
    }

    private func updateRateLimit(from response: HTTPURLResponse) {
        guard let limit = Int(response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? ""),
              let remaining = Int(response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "") else {
            return
        }
        let reset = TimeInterval(response.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "").map { Date(timeIntervalSince1970: $0) }
        let used = Int(response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "")
        updateRateLimit(GitHubRateLimit(limit: limit, remaining: remaining, used: used, reset: reset))
    }

    private func updateRateLimit(_ rateLimit: GitHubRateLimit) {
        stateLock.lock()
        rateLimitStorage = rateLimit
        stateLock.unlock()
    }
}
