# Architecture

## Components

- `AppDelegate` starts a menu-bar-only AppKit application and owns the shared `AppModel`.
- `StatusBarController` owns the `NSStatusItem`, renders status icons, and hosts the SwiftUI popover.
- `AppModel` coordinates configuration, authentication, polling, notification state, and UI state.
- `PopoverView` and `SettingsView` provide the compact monitoring surface and onboarding/settings experience.
- `WorkflowMonitor` polls configured repositories and compares recent Actions runs against previous snapshots.
- `GitHubAPIClient` lists repositories and calls GitHub's repository workflow-runs REST endpoint.
- `GitHubDeviceAuthenticator` implements OAuth device flow.
- `KeychainTokenStore` stores the GitHub access token.
- `UserDefaultsConfigurationStore` persists non-secret app configuration.

## Auth Flow

The app uses GitHub OAuth device flow, which is appropriate for native apps because it does not require shipping a client secret.

Users provide an OAuth App client ID. During sign-in, the app requests a device code from GitHub, opens the GitHub verification URL, and polls for the access token after the user authorizes the app in the browser.

Public repository monitoring requests no scope. Private repository monitoring requests `repo`, because private workflow run reads require repository access.

## Storage

Secrets:

- GitHub access token is stored in macOS Keychain.
- The Keychain item uses service `com.exodoslabs.MacGHActionsNotifier`.
- The token is never logged or written to config files.

Configuration:

- OAuth client ID, monitored repositories, notification preferences, and polling interval are stored as JSON in UserDefaults.
- Polling interval is clamped to 60-900 seconds.

## GitHub API Usage

The settings screen lists repositories for the configured account or organization through GitHub's repositories REST API. Organization repositories use `/orgs/{org}/repos`; when the configured owner matches the authenticated user, personal repositories use `/user/repos` so private owned repositories can appear with the `repo` scope.

For each configured repository, the monitor calls:

```text
GET /repos/{owner}/{repo}/actions/runs?per_page=20
```

The app sends:

- `Authorization: Bearer <token>`
- `Accept: application/vnd.github+json`
- `X-GitHub-Api-Version: 2022-11-28`

Errors are converted into user-facing status messages. `401` asks the user to sign in again, `403` distinguishes rate limits when possible, and `404` points to account or repository configuration issues.

## Notification Logic

The monitor keeps the latest displayed run for each repository and a previous-state snapshot for recent workflow run IDs. A notification is emitted only when a run appears or changes state after the repository has already been observed once.

Effective states are:

- `running` for queued/in-progress/waiting/requested/pending.
- `succeeded` for successful, skipped, or neutral completed runs.
- `failed` for failure, timed out, action required, or startup failure.
- `cancelled` for cancelled completed runs.
- `problem` for unknown API states.

Repeated polls of unchanged runs stay silent.
