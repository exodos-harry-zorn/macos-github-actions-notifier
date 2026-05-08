# Release Checklist

This project currently produces an ad-hoc signed app bundle and DMG. A GitHub release is created by the **Release DMG** workflow when a `v*` tag is pushed, or when the workflow is run manually.

Create a release from a local checkout:

```bash
git tag v0.1.0
git push origin v0.1.0
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
