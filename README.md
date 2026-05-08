# GitHub Actions Notifier for macOS

![GitHub Actions Notifier logo](assets/AppIcon.png)

A small native macOS menu bar app that watches GitHub Actions activity across selected repositories and only interrupts you when workflow runs meaningfully change state.

The app is built with Swift, SwiftUI, and AppKit menu bar integration. It stores GitHub tokens in macOS Keychain, keeps configuration separate from secrets, and polls conservatively so it behaves like a calm background assistant instead of another noisy dashboard.

## Features

- Menu bar only app with native status icon states: idle, running, succeeded, failed, and configuration/authentication problem.
- Compact SwiftUI popover showing overall status, configured repositories, latest workflow states, refresh, settings, and GitHub links.
- GitHub OAuth device flow authentication for native-app friendly sign-in.
- Keychain-backed token storage.
- Configurable repositories, notification preferences, and polling interval.
- Native macOS notifications only for workflow start, success, failure, or cancellation changes.
- GitHub REST API workflow polling with API error and rate-limit handling.

## Requirements

- macOS 14 or newer. The project builds cleanly with current Apple Swift command line tools targeting macOS 26.
- A GitHub OAuth App client ID with Device Flow enabled.
- Swift 6 toolchain only if you are building from source.

## Install

1. Open the latest GitHub release.
2. Download `GitHub-Actions-Notifier-<version>.dmg`.
3. Open the DMG.
4. Drag **GitHub Actions Notifier** into **Applications**.
5. Launch the app. It appears in the macOS menu bar, not in the Dock.

Current development builds are ad-hoc signed and not notarized. macOS may show a Gatekeeper warning the first time you open the downloaded app. See `docs/RELEASE.md` for the signing and notarization plan.

## GitHub Authentication Setup

First create a GitHub OAuth App:

1. Go to GitHub.
2. Click your profile photo.
3. Click **Settings**.
4. Scroll down and click **Developer settings**.
5. Click **OAuth Apps**.
6. Click **New OAuth App**.
7. Fill in the app details:
   - **Application name:** `MacOS GitHub Actions Notifier` or another name you recognize.
   - **Homepage URL:** use your real app/site URL, or this GitHub repository URL.
   - **Authorization callback URL:** any valid URL is fine for device flow, for example the same URL as the homepage.
8. Check **Enable Device Flow**.
9. Click **Register application**.
10. Copy the **Client ID**.
11. Open GitHub Actions Notifier settings.
12. Paste the Client ID into the app settings.

Then sign in inside the app:

1. Click **Sign in with GitHub**.
2. GitHub should show a short code.
3. Open the GitHub device page, usually [https://github.com/login/device](https://github.com/login/device).
4. Enter the code.
5. Approve the app.
6. Go back to GitHub Actions Notifier.
7. Click **I authorized in browser**.

## Required Scopes

Public repositories can be monitored with no requested OAuth scopes.

Private repositories require GitHub's classic OAuth `repo` scope because the GitHub Actions workflow-runs REST endpoint needs repository read access for private repositories. The settings screen makes this explicit before sign-in.

Tokens are stored only in macOS Keychain under `com.exodoslabs.MacGHActionsNotifier`. Tokens are never written to UserDefaults, logs, or config files.

## Configure Repositories

Open settings from the menu bar popover:

1. Sign in with GitHub.
2. Enter the GitHub account or organization, for example `exodos-labs`.
3. Click **Load repositories**.
4. Choose a repository from the dropdown.
5. Click **Monitor selected repository**.
6. Repeat for every repository you want to watch.
7. Choose notification preferences.
8. Choose a polling interval between 60 and 900 seconds.
9. Click **Done**.

Each selected repository monitors all GitHub Actions workflow runs. You do not need to configure `ci.yml` files or individual workflows.

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

Build a local DMG:

```bash
make dmg
```

The app is configured as `LSUIElement`, so it appears only in the menu bar and not in the Dock.

Or run the full local verification path:

```bash
make verify
```

The repository also includes a GitHub Actions workflow that runs tests, builds the release executable, packages the `.app`, validates bundle metadata, and uploads the bundle as a CI artifact.

Release DMGs are built by GitHub Actions when a `v*` tag is pushed, or by manually running the **Release DMG** workflow. The workflow uploads `GitHub-Actions-Notifier-<version>.dmg` and its SHA-256 checksum to the GitHub release.

## Screenshots

Screenshots are not committed yet because this repository was initialized headlessly. See `docs/SCREENSHOTS.md` for the intended capture checklist.

## Security Notes

- GitHub authentication uses device flow, which avoids embedding a client secret in the native app.
- Keychain items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Logout deletes the local Keychain token. To fully revoke access, revoke the OAuth App grant in GitHub account settings.
- Logs use Apple's unified logging and never include tokens.
- API requests use GitHub's current REST API version header.
- Local development bundles are ad-hoc signed. See `docs/RELEASE.md` for Developer ID signing and notarization steps.

## License

GitHub Actions Notifier is open source under the [Apache License 2.0](LICENSE).

Apache-2.0 is a permissive license: you can use, modify, distribute, and build on this project, including commercially, as long as you follow the license terms. The license also includes an explicit patent grant and standard warranty disclaimer.

## References

- [GitHub OAuth App authorization and device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)
- [GitHub Actions workflow runs REST API](https://docs.github.com/v3/actions/workflow-runs/)
