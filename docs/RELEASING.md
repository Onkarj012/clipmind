# Releasing ClipMind

ClipMind is distributed directly outside the Mac App Store. The app needs
Accessibility and global shortcuts, so this release path intentionally does
not use the App Sandbox.

## Prerequisites

- An Apple Developer Program team with a **Developer ID Application** identity.
- App Store Connect API credentials or an app-specific password configured in
  the local keychain for `notarytool`.
- A clean working tree and a successful CI run.

## Release checklist

1. Merge through a PR with CI passing.
2. Run the manual `Release` workflow from `main` and choose `patch`, `minor`,
   or `major`. The workflow bumps `ClipMind/Info.plist`, runs tests, builds a
   Release app, commits `chore(release): vX.Y.Z`, creates an annotated tag, and
   opens a draft GitHub Release with the unsigned CI artifact attached.
3. Run the unit suite locally before cutting a signed artifact:

   ```sh
   xcodebuild -project ClipMind.xcodeproj -scheme ClipMind -configuration Debug -destination 'platform=macOS,arch=arm64' test
   ```

4. Archive with the Developer ID identity and your team ID. The Release
   configuration enables Hardened Runtime.
5. Validate the exported application before upload:

   ```sh
   codesign --verify --deep --strict --verbose=2 ClipMind.app
   codesign -dvvv --entitlements :- ClipMind.app
   spctl -a -vv ClipMind.app
   ```

6. Submit the signed archive with `xcrun notarytool submit ... --wait`, staple
   the accepted ticket with `xcrun stapler staple ClipMind.app`, then repeat
   the validation command above.
7. Test on a clean macOS user account: initial launch, Accessibility prompt,
   global shortcuts, capture/paste, local Ollama fallback, and history
   retention/deletion.

Never commit signing certificates, private keys, notarization credentials, or
Groq API keys.
