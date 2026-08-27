# App Store Review Guidelines — Detailed Pre-Submission Checklist

Detailed reference for `ios-deploy-checklist`. Load this for a thorough pass before a significant release, or when the user wants documentation to share with their team. Section numbers reference Apple's App Store Review Guidelines structure as of early 2026 — always cross-check against the current published guidelines for any recent changes, since Apple updates them periodically.

## 1. Safety

- [ ] No user-generated content features (comments, chat, profiles) without a way to filter objectionable content, block abusive users, and report content — required if UGC is present at all.
- [ ] No content that could be reasonably read as encouraging self-harm, and appropriate resources/handling if the app touches mental health topics.
- [ ] Age rating in App Store Connect accurately reflects the most mature content in the app (violence, mature themes, gambling mechanics, unrestricted web access, etc.).
- [ ] Kids category apps (if applicable): no third-party analytics/advertising SDKs that don't comply with the Kids Category's stricter data rules.

## 2. Performance

- [ ] **2.1 App Completeness:** app has been tested on a real device, all features referenced in the description/screenshots are functional in this build, no placeholder ("Lorem ipsum," "Coming Soon" on core features) content.
- [ ] Demo account credentials provided in App Review Information if login is required, and confirmed still valid (not expired or reset).
- [ ] **2.2 Beta Testing:** no beta/trial features implying instability submitted to the main App Store track (that's what TestFlight is for).
- [ ] **2.3 Accurate Metadata:** screenshots reflect actual current UI; keywords aren't stuffed with unrelated competitor names; description doesn't promise functionality not present in this build.
- [ ] **2.5 Software Requirements:** no use of private APIs (checked via static analysis or `otool`/App Store Connect's automated binary scan — a rejection here cites the specific private symbol used).
- [ ] Background modes declared in `Info.plist`/capabilities are actually used for their stated purpose (e.g. `background-fetch` used for genuine periodic refresh, not to keep the app alive indefinitely for unrelated reasons).

## 3. Business

- [ ] **3.1.1 In-App Purchase:** any unlock of digital content, subscription, or virtual currency uses Apple's IAP, not an external payment link or "email us to unlock" scheme — narrow exceptions exist for physical goods, person-to-person services, and approved "reader" apps, but assume IAP is required unless the app clearly fits an exception.
- [ ] Subscription terms, pricing, and auto-renewal disclosure are present in the app (not just in App Store Connect metadata) before purchase, per Apple's subscription guidelines.
- [ ] **3.1.3 Reader Apps** exception (if claimed): app must let users access previously purchased content without requiring in-app purchase for that same content again.
- [ ] No mention of pricing being cheaper on another platform, and no direct links out to a website to complete a purchase that should go through IAP (this is a very commonly cited rejection).

## 4. Design

- [ ] **4.2 Minimum Functionality:** app is not simply a repackaged website with no native functionality (WebView-only apps are frequently rejected unless they provide genuine native value).
- [ ] **4.8 Sign in with Apple:** if any third-party or social login (Google, Facebook, X, etc.) is offered, Sign in with Apple must also be offered as an equivalent option, positioned with equal prominence.
- [ ] UI follows basic Human Interface Guidelines conventions — standard navigation patterns, no custom gestures that conflict with system gestures (e.g. a custom edge-swipe that fights the system back-swipe).
- [ ] App doesn't mimic the iOS system UI in a way that could confuse users (e.g. fake system alerts, fake "Settings" screens).

## 5. Legal

- [ ] **5.1.1 Privacy — Data Collection and Storage:** a privacy policy URL is provided in App Store Connect and the linked page is live, specific to this app (not a generic placeholder), and accurately describes what data is collected.
- [ ] **5.1.2 Data Use and Sharing:** App Privacy "nutrition label" answers in App Store Connect match what the app and its third-party SDKs actually collect — mismatches between declared and actual data collection are increasingly scrutinized and can result in rejection or removal.
- [ ] **Privacy manifest (`PrivacyInfo.xcprivacy`)** present at the app level and for any third-party SDK that requires one, declaring:
  - Required reason API usage (e.g. `UserDefaults`, `NSFileSystemFreeSize`, active keyboard APIs, system boot time) with a valid declared reason code.
  - Tracking domains, if any.
  - Data types collected and linked/not linked to the user's identity.
- [ ] **App Tracking Transparency:** if IDFA or cross-app/cross-site tracking is used, the ATT prompt is implemented and tracking-dependent code paths correctly branch on the user's response (no tracking before consent is granted).
- [ ] Export compliance (`ITSAppUsesNonExemptEncryption` / App Store Connect questionnaire) answered correctly for the encryption actually used (standard HTTPS/TLS is typically exempt; custom or non-standard encryption is not).

## Common cross-cutting review flags

- [ ] No hardcoded API keys or secrets visible in a decompiled/strings scan of the binary (Apple's automated scanning and independent researchers both check for this; it's a security issue even if not itself a Guideline violation).
- [ ] No test/debug menus or internal tooling reachable in a production build (hidden debug screens triggered by a gesture or tap sequence have been flagged in past reviews).
- [ ] Any app extension (widget, share extension, notification service extension) has its own valid provisioning profile and matching bundle identifier suffix.

## Pre-submission smoke test (do this on a real device, not just simulator)

1. Fresh install (delete any existing build first) → first launch → every permission prompt appears with the correct, specific usage description.
2. Complete the core user flow the app exists for, start to finish, with no crashes.
3. Background the app mid-flow and return — state is preserved or gracefully reset, no crash.
4. Airplane mode toggle mid-network-call — app handles the failure without crashing or hanging indefinitely.
5. Rotate device (if the app supports multiple orientations) — layout doesn't break.
6. If login is required, log out and log back in with the exact test credentials that will be given to the reviewer.
