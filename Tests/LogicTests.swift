import Foundation

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if condition() {
        return true
    }
    FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
    exit(1)
}

func makeRun(
    id: Int64 = Int64.random(in: 1...999),
    status: WorkflowRunStatus,
    conclusion: WorkflowRunConclusion?,
    triggeredBy: String? = nil,
    branch: String = "main",
    pullRequests: [WorkflowPullRequest] = [],
    failurePreview: WorkflowFailurePreview? = nil,
    durationSeconds: TimeInterval? = nil,
    isDeployment: Bool = false
) -> WorkflowRun {
    WorkflowRun(
        id: id,
        workflowID: 1,
        name: "CI",
        displayTitle: "CI",
        status: status,
        conclusion: conclusion,
        htmlURL: URL(string: "https://github.com/example/repo/actions/runs/\(id)")!,
        branch: branch,
        runNumber: 10,
        createdAt: Date(),
        updatedAt: Date(timeIntervalSince1970: 10_000),
        triggeredBy: triggeredBy,
        event: "push",
        pullRequests: pullRequests,
        failurePreview: failurePreview,
        durationSeconds: durationSeconds,
        isDeployment: isDeployment
    )
}

@main
struct LogicTests {
    static func main() {
        expect(StatusAggregator.status(for: []) == .idle, "empty runs are idle")
        expect(StatusAggregator.status(for: [
            makeRun(status: .completed, conclusion: .success),
            makeRun(status: .completed, conclusion: .failure)
        ]) == .failed, "failed runs take priority")
        expect(StatusAggregator.status(for: [
            makeRun(status: .completed, conclusion: .success),
            makeRun(status: .inProgress, conclusion: nil)
        ]) == .running, "running takes priority over success")

        let repeatedRun = makeRun(id: 1, status: .inProgress, conclusion: nil)
        expect(NotificationDecider.notification(
            previous: repeatedRun,
            current: repeatedRun,
            repositoryFullName: "exodos/repo",
            preferences: .default
        ) == nil, "same run and state does not notify")

        let firstObservedRun = makeRun(id: 2, status: .inProgress, conclusion: nil)
        expect(NotificationDecider.notification(
            previous: nil,
            current: firstObservedRun,
            repositoryWasPrimed: false,
            repositoryFullName: "exodos/repo",
            preferences: .default
        ) == nil, "first observed workflow run primes state silently")

        expect(NotificationDecider.notification(
            previous: nil,
            current: firstObservedRun,
            repositoryWasPrimed: true,
            repositoryFullName: "exodos/repo",
            preferences: .default
        )?.title == "Workflow started", "new workflow after repository baseline notifies as started")

        let previousRun = makeRun(id: 2, status: .completed, conclusion: .success)
        let startedRun = makeRun(id: 3, status: .inProgress, conclusion: nil)
        expect(NotificationDecider.notification(
            previous: previousRun,
            current: startedRun,
            repositoryFullName: "exodos/repo",
            preferences: .default
        )?.title == "Workflow started", "new running workflow after baseline notifies as started")

        var preferences = NotificationPreferences.default
        preferences.notifyOnSucceeded = false
        let successRun = makeRun(id: 3, status: .completed, conclusion: .success)
        expect(NotificationDecider.notification(
            previous: nil,
            current: successRun,
            repositoryFullName: "exodos/repo",
            preferences: preferences
        ) == nil, "success preference suppresses success notifications")

        let config = AppConfiguration(
            githubClientID: " abc ",
            defaultOwner: " org ",
            monitoredRepositories: [
                MonitoredRepository(owner: " exodos ", name: " repo ", workflows: [])
            ],
            notificationPreferences: .default,
            pollingIntervalSeconds: 10,
            recentRunsPerRepository: 50
        ).normalized()
        expect(config.githubClientID == "abc", "client ID is trimmed")
        expect(config.defaultOwner == "org", "default owner is trimmed")
        expect(config.pollingIntervalSeconds == 60, "polling interval is clamped")
        expect(config.recentRunsPerRepository == 20, "recent runs display count is clamped")
        expect(config.monitoredRepositories.first?.owner == "exodos", "owner is trimmed")
        expect(config.monitoredRepositories.first?.workflows.isEmpty == true, "repositories can monitor all workflows without workflow config")
        let persistedConfigData = try! JSONEncoder().encode(config.sanitizedForPersistence())
        let persistedConfigJSON = String(data: persistedConfigData, encoding: .utf8)!
        expect(!persistedConfigJSON.contains("abc"), "persisted configuration does not contain OAuth client ID")

        let legacyConfigJSON = Data("""
        {
          "githubClientID": "client",
          "defaultOwner": "exodos",
          "monitoredRepositories": [],
          "notificationPreferences": {
            "notifyOnStarted": true,
            "notifyOnSucceeded": true,
            "notifyOnFailed": true,
            "notifyOnCancelled": true
          },
          "pollingIntervalSeconds": 180
        }
        """.utf8)
        let decodedLegacyConfig = try! JSONDecoder().decode(AppConfiguration.self, from: legacyConfigJSON)
        expect(decodedLegacyConfig.recentRunsPerRepository == 5, "legacy config defaults recent runs display count")

        let repoKey = RepositoryWorkflowKey.repository(owner: "exodos", repository: "repo")
        expect(repoKey.workflowIdentifier == "all", "repository monitor key uses all workflow runs")

        let now = Date(timeIntervalSince1970: 10_000)
        expect(TimestampFormatter.compact(Date(timeIntervalSince1970: 9_970), now: now) == "just now", "timestamp formats seconds as just now")
        expect(TimestampFormatter.compact(Date(timeIntervalSince1970: 9_700), now: now) == "5m ago", "timestamp formats minutes")
        expect(TimestampFormatter.compact(Date(timeIntervalSince1970: 2_800), now: now) == "2h ago", "timestamp formats hours")
        let actorRun = makeRun(status: .completed, conclusion: .success, triggeredBy: "exodos-harry-zorn")
        expect(WorkflowRunDisplayFormatter.detail(for: actorRun, now: now) == "#10 succeeded - main - by exodos-harry-zorn - just now", "workflow detail includes triggering user")
        let actorlessRun = makeRun(status: .completed, conclusion: .success)
        expect(!WorkflowRunDisplayFormatter.detail(for: actorlessRun, now: now).contains(" by "), "workflow detail omits actor segment when unknown")
        let pullRequestRun = makeRun(status: .completed, conclusion: .success, pullRequests: [WorkflowPullRequest(number: 897, htmlURL: nil, title: "Add cache")])
        expect(WorkflowRunDisplayFormatter.detail(for: pullRequestRun, now: now).contains("PR #897 Add cache"), "workflow detail includes pull request context")
        let failedRun = makeRun(status: .completed, conclusion: .failure, failurePreview: WorkflowFailurePreview(jobName: "build", stepName: "Run tests", htmlURL: nil))
        expect(WorkflowRunDisplayFormatter.failureDetail(for: failedRun) == "Failed at build / Run tests", "failure detail previews failed job and step")
        let durationRun = makeRun(status: .completed, conclusion: .success, durationSeconds: 125)
        expect(WorkflowRunDisplayFormatter.detail(for: durationRun, now: now).contains("2m"), "workflow detail includes completed duration")
        let workflowRunJSON = Data("""
        {
          "workflow_runs": [
            {
              "id": 42,
              "name": "Deploy",
              "workflow_id": 7,
              "status": "completed",
              "conclusion": "success",
              "html_url": "https://github.com/example/repo/actions/runs/42",
              "head_branch": "main",
              "run_number": 12,
              "display_title": "Deploy production",
              "created_at": "2026-05-11T06:00:00Z",
              "updated_at": "2026-05-11T06:04:00Z",
              "event": "pull_request",
              "run_started_at": "2026-05-11T06:01:00Z",
              "actor": { "login": "original-user" },
              "triggering_actor": { "login": "rerun-user" },
              "pull_requests": [
                { "number": 33, "html_url": "https://github.com/example/repo/pull/33", "title": "Improve deploy" }
              ]
            }
          ]
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedRun = try! decoder.decode(GitHubWorkflowResponse.self, from: workflowRunJSON).workflowRuns[0].domainModel(fallbackName: "Workflow")
        expect(decodedRun.triggeredBy == "rerun-user", "workflow run prefers triggering actor login")
        expect(decodedRun.pullRequests.first?.number == 33, "workflow run decodes pull request context")
        expect(decodedRun.durationSeconds == 180, "workflow run computes completed run duration")

        expect(BranchMatcher.matches(branch: "feature/detail-page", patterns: ["main", "feature/*"]), "branch filter supports wildcards")
        expect(!BranchMatcher.matches(branch: "develop", patterns: ["main", "release/*"]), "branch filter excludes unmatched branches")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let evening = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 5, day: 12, hour: 22).date!
        expect(QuietHours.contains(evening, startHour: 18, endHour: 8, calendar: calendar), "quiet hours can span midnight")
        let mutedRepository = MonitoredRepository(owner: "exodos", name: "repo", mutedUntil: now.addingTimeInterval(3_600))
        expect(!NotificationPolicy.shouldNotify(run: actorRun, repository: mutedRepository, preferences: .default, currentUserLogin: "exodos-harry-zorn", now: now), "muted repositories suppress notifications")
        var myRunPreferences = NotificationPreferences.default
        myRunPreferences.notifyOnlyForCurrentUser = true
        expect(!NotificationPolicy.shouldNotify(run: actorRun, repository: MonitoredRepository(owner: "exodos", name: "repo"), preferences: myRunPreferences, currentUserLogin: "someone-else", now: now), "my-runs mode suppresses other users")
        let deploymentRepository = MonitoredRepository(owner: "exodos", name: "repo", deploymentWorkflowPatterns: ["*CI*"])
        let deploymentRun = makeRun(status: .completed, conclusion: .success)
        expect(DeploymentClassifier.isDeployment(run: deploymentRun, repository: deploymentRepository), "deployment classifier matches workflow names")
        let firstFailure = WorkflowNotification(title: "Workflow failed", body: "one", url: URL(string: "https://github.com/example/repo/actions/runs/1")!, repositoryFullName: "exodos/repo", workflowName: "CI", kind: .failed)
        let secondFailure = WorkflowNotification(title: "Workflow failed", body: "two", url: URL(string: "https://github.com/example/repo/actions/runs/2")!, repositoryFullName: "exodos/repo", workflowName: "Deploy", kind: .failed)
        let groupedFailures = NotificationGrouper.grouped([firstFailure, secondFailure], groupFailures: true)
        expect(groupedFailures.count == 1 && groupedFailures[0].title == "2 workflows failed", "failure grouping collapses repository failures")

        let idleUpdateState = SoftwareUpdateState.idle
        expect(idleUpdateState.bannerTitle == nil, "idle update state does not show a banner")
        let availableUpdate = SoftwareUpdateState.updateAvailable(version: "0.4.0")
        expect(availableUpdate.bannerTitle == "Update 0.4.0 available", "available update has a clear banner title")
        expect(availableUpdate.bannerSubtitle == "Install the latest release without downloading a DMG manually.", "available update explains seamless install")
        expect(availableUpdate.canInstallUpdate == true, "available update can be installed")
        let failedUpdate = SoftwareUpdateState.failed("Appcast could not be verified.")
        expect(failedUpdate.bannerTitle == "Update check needs attention", "update failure has an attention banner")
        expect(failedUpdate.canInstallUpdate == false, "failed update cannot install")
        let noUpdateError = NSError(domain: "SUSparkleErrorDomain", code: 1001, userInfo: [NSLocalizedDescriptionKey: "You’re up to date!"])
        let noUpdateCycleState = SoftwareUpdateState.finishedUpdateCycle(error: noUpdateError)
        expect(noUpdateCycleState == .upToDate, "Sparkle no-update finish error maps to quiet up-to-date state")
        expect(noUpdateCycleState?.bannerTitle == nil, "Sparkle no-update finish error does not show a banner")

        print("Logic tests passed")
    }
}
