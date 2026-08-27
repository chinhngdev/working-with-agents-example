---
name: ios-deploy-checklist
description: Runs a pre-submission checklist for iOS app releases covering code signing, provisioning profiles, TestFlight builds, Info.plist permissions, and App Store Review Guidelines compliance. Use when the user asks to prepare a release, submit to TestFlight or the App Store, review before submission, or asks about code signing errors, provisioning profile issues, or App Store rejection risks.
---

# iOS Deploy Checklist

## Purpose

Walk through pre-submission verification before an iOS build goes to TestFlight or App Store Review, catching the issues that cause rejected builds, failed archive uploads, or App Store Review rejections. Load `references/app-store-checklist.md` for the full guideline-by-guideline checklist when doing a thorough pre-submission pass.

## Step 1: Version and build number

- Confirm `CFBundleShortVersionString` (marketing version, e.g. `2.3.0`) has been bumped if this is a public release, and `CFBundleVersion` (build number) is strictly higher than the last uploaded build for this version — App Store Connect rejects a build number that doesn't increase.
- Confirm the version follows the app's existing versioning scheme (semantic versioning is common but not required by Apple).

## Step 2: Code signing and provisioning

- **Automatic signing:** confirm Xcode's "Automatically manage signing" is checked and the correct Team is selected, if the project uses this mode.
- **Manual signing:** confirm the provisioning profile is not expired (`profile.mobileprovision` has an expiration date — check via `security cms -D -i profile.mobileprovision` or Xcode's profile inspector) and that it matches the exact bundle identifier and includes the correct entitlements (Push Notifications, App Groups, Associated Domains, etc. — any entitlement used in code must be present in both the profile and the `.entitlements` file).
- **Distribution certificate:** confirm it hasn't expired and is present in the keychain used for the archive/export step (common CI failure: certificate present locally but not imported into the CI machine's keychain).
- If archiving fails with a signing error, check: correct Team ID selected, App ID capabilities in the Apple Developer portal match the entitlements file, and the provisioning profile was regenerated after any capability was added or changed.

## Step 3: Info.plist and permissions

- Every system capability the app uses at runtime needs a corresponding usage description string, or the app crashes immediately on first use (not just gets rejected — it crashes for users). Check for all that apply:
  - Camera → `NSCameraUsageDescription`
  - Photo library → `NSPhotoLibraryUsageDescription` (and `NSPhotoLibraryAddUsageDescription` if only writing)
  - Location → `NSLocationWhenInUseUsageDescription` and/or `NSLocationAlwaysAndWhenInUseUsageDescription`
  - Microphone → `NSMicrophoneUsageDescription`
  - Contacts → `NSContactsUsageDescription`
  - Calendar → `NSCalendarsUsageDescription`
  - Bluetooth → `NSBluetoothAlwaysUsageDescription`
  - Face ID → `NSFaceIDUsageDescription`
  - Tracking (IDFA) → `NSUserTrackingUsageDescription`, and confirm `App Tracking Transparency` prompt logic is implemented if tracking is used
- **The description strings must be specific and honest** — "This app needs camera access" is the kind of vague copy Apple's review has flagged in the past; a description like "Used to scan receipts for expense tracking" is much safer and also better UX.
- Confirm `ITSAppUsesNonExemptEncryption` is set correctly in `Info.plist` (or answered correctly in App Store Connect's export compliance step) if the app uses any encryption beyond standard HTTPS — a wrong answer here can delay or block release.

## Step 4: App icons and launch screen

- Confirm all required app icon sizes are present in the asset catalog with no missing slots (Xcode will warn, but double check before archiving) and that the icon has no transparency or rounded corners baked in (iOS applies the mask automatically; a pre-rounded icon looks wrong on the home screen).
- Confirm the launch screen doesn't contain placeholder text, "Lorem ipsum," or debug-only content.

## Step 5: TestFlight-specific checks

- **Export compliance:** answered in App Store Connect for every build before external testers can access it.
- **What to test note:** provide clear notes for external testers, especially for features gated behind flags or requiring specific test accounts.
- **Test account credentials:** if the app requires login, provide a working demo/test account in the App Review notes (App Store Connect → version → App Review Information) — missing test credentials is one of the most common causes of review delay, since the reviewer cannot proceed past a login wall.
- **Build processing time:** note that a build can take anywhere from a few minutes to a few hours to finish processing after upload before it's available to add to a TestFlight group — don't assume a failed availability check means the upload failed.

## Step 6: App Store Review Guidelines quick pass

Full detail in `references/app-store-checklist.md`. The highest-frequency rejection causes to check first:

1. **Crashes and bugs (Guideline 2.1)** — confirm the build has been smoke-tested on a real device, not just the simulator (some bugs, especially around permissions, camera, and push notifications, only appear on device).
2. **Incomplete metadata (Guideline 2.3)** — screenshots match the actual current app UI, description doesn't reference features not present in this build, age rating matches actual content.
3. **Broken links** — support URL, privacy policy URL, and marketing URL (if provided) in App Store Connect all resolve, and the privacy policy is genuinely accessible (not a placeholder page).
4. **Sign in with Apple (Guideline 4.8)** — if the app offers any third-party login (Google, Facebook, etc.), confirm "Sign in with Apple" is also offered, or Apple will reject it.
5. **In-app purchase compliance (Guideline 3.1.1)** — any digital content/subscription must use Apple's In-App Purchase system, not an external payment link, with narrow exceptions (e.g. "reader" apps) that don't apply to most apps.
6. **Privacy manifest and required reason APIs** — confirm `PrivacyInfo.xcprivacy` is present and declares approximate/precise location, tracking domains, and any "required reason" API usage (e.g. `UserDefaults`, disk space APIs) that Apple now requires be declared, or the build can be rejected at ingestion before a human reviewer even sees it.

## Step 7: Rollback plan

Before submitting, confirm:

- The previous stable build/version can still be reinstated (e.g. via a phased rollout pause or a fast-follow patch plan) if the new release has a critical bug.
- Any server-side feature flags gating new functionality in this build are documented, so a bad feature can be disabled remotely without needing a new app submission.

## Common errors and fixes

### "No matching provisioning profiles found"
**Cause:** The provisioning profile doesn't include the device (for ad-hoc) or doesn't match the bundle ID/entitlements exactly.
**Solution:** Regenerate the profile in the Apple Developer portal after confirming the App ID's capabilities match the entitlements file, then re-download and select it explicitly in Xcode's signing settings.

### "Invalid Binary" after upload, citing missing Info.plist keys
**Cause:** A usage description string is missing for a capability actually used in code (see Step 3).
**Solution:** Add the missing `NS*UsageDescription` key with a specific, honest description, then re-archive and re-upload — this requires a new build number.

### App rejected for "Guideline 2.1 - App Completeness" citing a crash on launch
**Cause:** Most commonly a missing usage description crash (see Step 3), or reviewer using a test account that doesn't exist.
**Solution:** Reproduce on a clean device install with the exact test credentials provided to review; check crash logs in App Store Connect's "Crashes" reporting under Trends/Diagnostics if the rejection includes one.

### Build stuck in "Processing" for many hours
**Cause:** Usually normal App Store Connect processing delay, occasionally an issue with the binary (e.g. invalid entitlement combination).
**Solution:** Wait — typical processing is under an hour but can take longer during peak periods. If it exceeds ~24 hours or an email arrives citing an issue, address the specific issue cited and re-upload with an incremented build number.
