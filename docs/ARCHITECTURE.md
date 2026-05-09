# Architecture

## Components

- `AppDelegate` starts a menu-bar-only AppKit application and owns the shared `AppModel`.
- `StatusBarController` owns the `NSStatusItem`, renders status icons, and hosts the SwiftUI popover.
- `AppModel` coordinates configuration, authentication, polling, notification state, and UI state.
- `PopoverView` and `SettingsView` provide the compact monitoring surface and onboarding/settings experience.
- `WorkflowMonitor` polls configured repositories and compares recent Actions runs against previous snapshots.
- `GitHubAPIClient` lists repositories and calls GitHub's repository workflow-runs REST endpoint.
- `GitHubDeviceAuthenticator` implements OAuth device flow.
- `SparkleUpdateController` wraps Sparkle's `SPUStandardUpdaterController` and reports update availability into `AppModel`.
- `KeychainTokenStore` stores the GitHub access token and OAuth Client ID.
- `UserDefaultsConfigurationStore` persists non-secret app configuration.

## Auth Flow

The app uses GitHub OAuth device flow, which is appropriate for native apps because it does not require shipping a client secret.

Users provide an OAuth App client ID. During sign-in, the app requests a device code from GitHub, opens the GitHub verification URL, and polls for the access token after the user authorizes the app in the browser.

Public repository monitoring requests no scope. Private repository monitoring requests `repo`, because private workflow run reads require repository access.

## Storage

Secrets:

- GitHub access token is stored in macOS Keychain.
- GitHub OAuth Client ID is also stored in macOS Keychain because it is user-entered authentication material.
- The Keychain item uses service `com.exodoslabs.MacGHActionsNotifier`.
- Tokens and the OAuth Client ID are never logged or written to config files.

Configuration:

- Monitored repositories, notification preferences, polling interval, and display preferences are stored as JSON in UserDefaults.
- Recent run display count is stored in UserDefaults and defaults to 5.
- Polling interval is clamped to 60-900 seconds.
- Sparkle stores its own update preferences in the app's standard user defaults keys, as recommended by Sparkle. The app does not duplicate those settings in `AppConfiguration`.

## App Updates

Updates use Sparkle 2 through `SPUStandardUpdaterController`.

The app bundle contains:

- `SUFeedURL`, pointing to the latest GitHub release's `appcast.xml` asset.
- `SUPublicEDKey`, the public EdDSA key used to verify update archives.
- `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, and `SUAllowsAutomaticUpdates`, enabling automatic checks and automatic download/install support by default.

Release publishing creates a signed Sparkle appcast:

1. GitHub Actions builds the `.app` bundle and DMG.
2. `scripts/create-appcast.sh` runs Sparkle's `generate_appcast` with the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.
3. The workflow uploads the DMG, checksum, and `appcast.xml` to the GitHub release.
4. Installed apps read the stable latest-release appcast URL and let Sparkle validate and install the update.

`AppModel.softwareUpdateState` provides the in-app banner state. The popover shows a compact update notification when Sparkle reports a valid update, and the settings screen exposes manual checks and automatic update preferences.

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

The monitor keeps recent displayed runs for each repository and a previous-state snapshot for recent workflow run IDs. A notification is emitted only when a run appears or changes state after the repository has already been observed once. The menu bar shows the event status for 5 minutes, keeps running status visible while a run is active, then returns to the app logo with an unread red dot until the user opens the popover.

Effective states are:

- `running` for queued/in-progress/waiting/requested/pending.
- `succeeded` for successful, skipped, or neutral completed runs.
- `failed` for failure, timed out, action required, or startup failure.
- `cancelled` for cancelled completed runs.
- `problem` for unknown API states.

Repeated polls of unchanged runs stay silent.
