# GitHub Tests and Local Releases

GitHub Actions runs tests, an ad-hoc build and a synthetic session smoke test on
pushes and pull requests to main. No signing certificate, private key, Apple ID
password or model API key is uploaded to GitHub. No signing Secrets are needed.

## Build a Release Locally

```bash
bash Scripts/build-app.sh
SIGNING_IDENTITY="YOUR_EXISTING_CERTIFICATE_FINGERPRINT" \
  bash Scripts/package-dmg.sh "$HOME/Downloads/EnglishCompass.dmg"
shasum -a 256 "$HOME/Downloads/EnglishCompass.dmg"
```

The signing identity remains in the local macOS Keychain. The `.p12` private key
is never exported. Standard installers target `/Applications`; personal builds
may set `APPLICATIONS_TARGET="$HOME/Applications"`.

Before publishing, mount the DMG read-only and validate the enclosed app with
`codesign --verify --deep --strict`. Inspect the bundle version and icon, and
run the app's `--ui-test --self-test` path. Never include real drafts or keys in
test logs or release assets.

## Upload Only the Finished Installer

Create a GitHub Release using a tag identifying the source revision and build.
Upload only the DMG and optional SHA-256 file. With an authenticated GitHub CLI:

```bash
gh release create YOUR_TAG /absolute/path/EnglishCompass.dmg \
  --repo evangerlions/EnglishCompass --target SOURCE_COMMIT \
  --title "English Compass development build" --prerelease \
  --notes "Apple Development signed; not notarized."
```

Developer-signed test builds should be clearly labelled prereleases. Apple
Development signing is not Developer ID distribution or notarization, and
Gatekeeper/privacy/Keychain prompts can still occur on another Mac.

If signing Secrets were already added for an older proposed CI flow, the owner
may remove them; this workflow does not use them.
