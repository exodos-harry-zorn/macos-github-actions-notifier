# Release Checklist

This project currently produces an ad-hoc signed app bundle, DMG, and Sparkle appcast. A GitHub release is created by the **Release DMG** workflow when a `v*` tag is pushed, or when the workflow is run manually.

After publishing a release, make sure the release notes point users to the README setup flow:

1. Create a GitHub OAuth App.
2. Enable Device Flow.
3. Copy the Client ID into app settings.
4. Sign in with the GitHub device code.
5. Load repositories and add them from the dropdown.

Release artifacts are distributed under the Apache License 2.0. Keep the top-level `LICENSE` file and README license section in sync if licensing ever changes.

## Sparkle Update Signing

Sparkle updates require EdDSA signatures. The app embeds the public key in `Packaging/Info.plist` under `SUPublicEDKey`; the private key must never be committed.

The current public key is:

```text
Wdmu1tI1+D+I/4LNb64I6wrNZHPWWyq0SeLxLTgJEMU=
```

The matching private key is stored in the repository secret `SPARKLE_PRIVATE_KEY`. The release workflow passes that secret to `scripts/create-appcast.sh`, which signs the update archive and writes `dist/appcast.xml`.

If you need to rotate keys:

1. Generate a new Sparkle EdDSA key with `generate_keys`.
2. Update `SUPublicEDKey` in `Packaging/Info.plist`.
3. Replace the `SPARKLE_PRIVATE_KEY` GitHub Actions secret with the exported private key.
4. Publish a new release and verify that `appcast.xml` contains a `sparkle:edSignature` enclosure attribute.

Local appcast generation:

```bash
PRIVATE_KEY_FILE="$(mktemp -u)"
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.exodoslabs.MacGHActionsNotifier -x "$PRIVATE_KEY_FILE"
export SPARKLE_PRIVATE_KEY="$(cat "$PRIVATE_KEY_FILE")"
./scripts/create-appcast.sh
rm -f "$PRIVATE_KEY_FILE"
```

The temporary private-key file is sensitive. Delete it immediately after use.

Create a release from a local checkout:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Local DMG verification:

```bash
make verify
```

Release workflow verification:

1. Push a `v*` tag.
2. Wait for **Release DMG** to finish.
3. Confirm the release contains:
   - `GitHub-Actions-Notifier-<version>.dmg`
   - `GitHub-Actions-Notifier-<version>.dmg.sha256`
   - `appcast.xml`
4. Download `appcast.xml` and confirm it is valid XML and contains `sparkle:edSignature`.

Before distributing outside local development, complete these release steps:

1. Enroll or use an Apple Developer account for Developer ID signing.
2. Replace ad-hoc signing in `scripts/build-app.sh` with a Developer ID Application identity.
3. Add hardened runtime entitlements if future app capabilities require them.
4. Notarize the app with Apple and staple the notarization ticket.
5. Capture the screenshots listed in `docs/SCREENSHOTS.md`.
6. Create a GitHub release and attach the notarized app archive.
