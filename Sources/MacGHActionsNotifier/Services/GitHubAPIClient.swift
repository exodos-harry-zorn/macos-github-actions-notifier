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
            triggeredBy: triggeringActor?.login ?? actor?.login
        )
    }
}

final class GitHubAPIClient: @unchecked Sendable {
    private let tokenProvider: any TokenProvider
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = AppLogger(category: "GitHubAPI")

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

    func recentRuns(owner: String, repository: String, limit: Int = 20) async throws -> [WorkflowRun] {
        let pageSize = max(1, min(limit, 50))
        let url = URL(string: "https://api.github.com/repos/\(encodedPath(owner))/\(encodedPath(repository))/actions/runs?per_page=\(pageSize)")!
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        try validate(response: response, data: data)
        let decoded = try decoder.decode(GitHubWorkflowResponse.self, from: data)
        return decoded.workflowRuns.map { $0.domainModel(fallbackName: $0.name ?? "Workflow") }
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
}
