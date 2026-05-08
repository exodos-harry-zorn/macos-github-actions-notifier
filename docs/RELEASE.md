# Release Checklist

This project currently produces an ad-hoc signed app bundle and DMG. A GitHub release is created by the **Release DMG** workflow when a `v*` tag is pushed, or when the workflow is run manually.

After publishing a release, make sure the release notes point users to the README setup flow:

1. Create a GitHub OAuth App.
2. Enable Device Flow.
3. Copy the Client ID into app settings.
4. Sign in with the GitHub device code.
5. Load repositories and add them from the dropdown.

Release artifacts are distributed under the Apache License 2.0. Keep the top-level `LICENSE` file and README license section in sync if licensing ever changes.

Create a release from a local checkout:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Local DMG verification:

```bash
make verify
```

Before distributing outside local development, complete these release steps:

1. Enroll or use an Apple Developer account for Developer ID signing.
2. Replace ad-hoc signing in `scripts/build-app.sh` with a Developer ID Application identity.
3. Add hardened runtime entitlements if future app capabilities require them.
4. Notarize the app with Apple and staple the notarization ticket.
5. Capture the screenshots listed in `docs/SCREENSHOTS.md`.
6. Create a GitHub release and attach the notarized app archive.
