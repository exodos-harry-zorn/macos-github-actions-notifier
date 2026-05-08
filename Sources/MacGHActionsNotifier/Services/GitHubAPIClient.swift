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
            updatedAt: updatedAt
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

    func latestRun(owner: String, repository: String, workflow: MonitoredWorkflow) async throws -> WorkflowRun? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encodedWorkflow = workflow.identifier.addingPercentEncoding(withAllowedCharacters: allowed) ?? workflow.identifier
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/actions/workflows/\(encodedWorkflow)/runs?per_page=1")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(try tokenProvider.readToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try decoder.decode(GitHubWorkflowResponse.self, from: data)
        return decoded.workflowRuns.first?.domainModel(fallbackName: workflow.displayName)
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
            throw AppError.api("GitHub could not find a configured repository or workflow.")
        default:
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            logger.error("GitHub API error \(http.statusCode): \(detail)")
            throw AppError.api("GitHub API error \(http.statusCode).")
        }
    }
}
