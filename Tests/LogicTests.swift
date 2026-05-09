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
    conclusion: WorkflowRunConclusion?
) -> WorkflowRun {
    WorkflowRun(
        id: id,
        workflowID: 1,
        name: "CI",
        displayTitle: "CI",
        status: status,
        conclusion: conclusion,
        htmlURL: URL(string: "https://github.com/example/repo/actions/runs/\(id)")!,
        branch: "main",
        runNumber: 10,
        createdAt: Date(),
        updatedAt: Date()
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

        let idleUpdateState = SoftwareUpdateState.idle
        expect(idleUpdateState.bannerTitle == nil, "idle update state does not show a banner")
        let availableUpdate = SoftwareUpdateState.updateAvailable(version: "0.4.0")
        expect(availableUpdate.bannerTitle == "Update 0.4.0 available", "available update has a clear banner title")
        expect(availableUpdate.bannerSubtitle == "Install the latest release without downloading a DMG manually.", "available update explains seamless install")
        expect(availableUpdate.canInstallUpdate == true, "available update can be installed")
        let failedUpdate = SoftwareUpdateState.failed("Appcast could not be verified.")
        expect(failedUpdate.bannerTitle == "Update check needs attention", "update failure has an attention banner")
        expect(failedUpdate.canInstallUpdate == false, "failed update cannot install")

        print("Logic tests passed")
    }
}
