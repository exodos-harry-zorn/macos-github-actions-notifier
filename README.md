# GitHub Actions Notifier for macOS

A small native macOS menu bar app that watches selected GitHub Actions workflows and only interrupts you when a workflow meaningfully changes state.

The app is built with Swift, SwiftUI, and AppKit menu bar integration. It stores GitHub tokens in macOS Keychain, keeps configuration separate from secrets, and polls conservatively so it behaves like a calm background assistant instead of another noisy dashboard.

## Features

- Menu bar only app with native status icon states: idle, running, succeeded, failed, and configuration/authentication problem.
- Compact SwiftUI popover showing overall status, configured repositories, latest workflow states, refresh, settings, and GitHub links.
- GitHub OAuth device flow authentication for native-app friendly sign-in.
- Keychain-backed token storage.
- Configurable repositories, workflow file names/IDs, deployment-related labels, notification preferences, and polling interval.
- Native macOS notifications only for workflow start, success, failure, or cancellation changes.
- GitHub REST API workflow polling with API error and rate-limit handling.

## Requirements

- macOS 14 or newer. The project builds cleanly with current Apple Swift command line tools targeting macOS 26.
- Swift 6 toolchain.
- A GitHub OAuth App client ID with Device Flow enabled.

## GitHub Authentication Setup

Create a GitHub OAuth App in GitHub Developer Settings:

1. Set the app name to something recognizable, such as `GitHub Actions Notifier`.
2. Use any valid homepage URL controlled by you.
3. Enable Device Flow for the OAuth App.
4. Copy the OAuth App client ID.
5. Paste the client ID into the app settings.

The app uses GitHub's device flow:

1. Click **Sign in with GitHub**.
2. The app opens GitHub's device authorization page.
3. Enter the shown user code in the browser.
4. Return to the app and click **I authorized in browser**.

## Required Scopes

Public repositories can be monitored with no requested OAuth scopes.

Private repositories require GitHub's classic OAuth `repo` scope because the GitHub Actions workflow-runs REST endpoint needs repository read access for private repositories. The settings screen makes this explicit before sign-in.

Tokens are stored only in macOS Keychain under `com.exodoslabs.MacGHActionsNotifier`. Tokens are never written to UserDefaults, logs, or config files.

## Configure Repositories and Workflows

Open settings from the menu bar popover:

1. Add a repository owner or organization.
2. Add the repository name.
3. Add one or more workflow identifiers. GitHub accepts workflow file names such as `ci.yml` or numeric workflow IDs.
4. Optionally mark workflows as deployment related for your own organization in the UI.
5. Choose notification preferences.
6. Choose a polling interval between 60 and 900 seconds.

## Notifications

The app compares each latest workflow run against the previous snapshot. It sends notifications only when:

- A new workflow run starts.
- A run completes successfully.
- A run fails.
- A run is cancelled.

Repeated polling of the same unchanged run does not notify.

## Build and Run

Run logic tests:

```bash
./scripts/test.sh
```

Build the executable:

```bash
swift build -c release
```

Build a macOS app bundle:

```bash
./scripts/build-app.sh
open "dist/GitHub Actions Notifier.app"
```

The app is configured as `LSUIElement`, so it appears only in the menu bar and not in the Dock.

## Screenshots

Screenshots are not committed yet because this repository was initialized headlessly. See `docs/SCREENSHOTS.md` for the intended capture checklist.

## Security Notes

- GitHub authentication uses device flow, which avoids embedding a client secret in the native app.
- Keychain items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Logout deletes the local Keychain token. To fully revoke access, revoke the OAuth App grant in GitHub account settings.
- Logs use Apple's unified logging and never include tokens.
- API requests use GitHub's current REST API version header.

## References

- [GitHub OAuth App authorization and device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)
- [GitHub Actions workflow runs REST API](https://docs.github.com/v3/actions/workflow-runs/)
