---
name: ios-performance-audit
description: Audits iOS app performance covering launch time, memory footprint, energy impact, and UI responsiveness using Instruments (Time Profiler, App Launch, Energy Log). Use when the user asks to improve app launch time, reduce memory usage, fix jank or dropped frames, investigate battery drain, or asks for a performance review of an iOS app.
---

# iOS Performance Audit

## Purpose

Provide a structured approach to auditing and improving iOS app performance across the dimensions users and App Review both care about: launch time, runtime responsiveness (frame drops/jank), memory footprint, and energy impact. Use Instruments as the primary measurement tool — don't guess at bottlenecks; profile first.

## Step 1: Identify the specific complaint

Performance is not one thing — ask which of these applies before picking a tool:

- "App feels slow to open" → Step 2 (Launch Time).
- "Scrolling/animation is janky" → Step 3 (Time Profiler + Core Animation).
- "Memory grows over time / app gets killed in background" → Step 4 (Allocations, and cross-reference `ios-debug-session` for leak-specific investigation).
- "Battery drains fast when using this app" → Step 5 (Energy Log).

## Step 2: Launch time

Apple's guidance targets under ~400ms to first frame for a responsive-feeling launch; anything users describe as "slow to open" is usually well beyond that.

1. Use Instruments' **App Launch** template (or Xcode's own launch time logging: set the `DYLD_PRINT_STATISTICS` environment variable on the scheme, or use `os_signpost` around suspected slow initializers) to break launch into phases:
   - **Static linking / dyld time** — time to load the binary and its dynamic libraries. Grows with binary size and number of embedded frameworks.
   - **`didFinishLaunchingWithOptions` / `App.init` time** — app-level setup code.
   - **First frame render time** — time until the first screen is actually drawn.
2. Common causes of slow launch, ranked by frequency seen in practice:
   - Synchronous network calls or disk I/O in `didFinishLaunchingWithOptions` (or a SwiftUI `App`'s init) — defer anything not required for the first frame to after launch, using `Task` or a post-launch hook.
   - Third-party SDK initialization (analytics, crash reporting, ad SDKs) done synchronously and serially — audit whether each SDK's init can be deferred or made async, and whether all of them are even necessary at launch versus lazily on first use.
   - Excessive number of dynamically linked frameworks — each adds dyld overhead; consider static linking or consolidating small internal frameworks.
   - Heavy `Codable`/JSON parsing of a large bundled resource (e.g. a big local config or seed database) done synchronously before the first screen appears.
3. Fix by moving non-essential work off the launch critical path: show the first screen with a lightweight/placeholder state, then perform heavier initialization in the background and update the UI once ready — rather than blocking the first frame on it.

## Step 3: Time Profiler and frame drops

For jank (dropped frames, stuttering scroll, laggy animations):

1. Record with the **Time Profiler** instrument while performing the janky interaction (scrolling a list, triggering the animation).
2. Check the **Core Animation** instrument's frame rate graph alongside Time Profiler to correlate exactly which frames dropped with what the CPU was doing at that moment.
3. In Time Profiler's call tree, use "Separate by Thread" and check whether the heavy work is on the **main thread** — main-thread work during scrolling is the most common direct cause of dropped frames, since UIKit/SwiftUI rendering itself needs the main thread.
4. Common causes:
   - Expensive layout/formatting work done synchronously in `cellForRowAt`/a SwiftUI `View`'s `body` (e.g. date formatting, image decoding, or text layout calculations not cached) — recommend caching formatted values or moving decode/format work off the main thread with results published back.
   - Image decoding at full resolution when only a thumbnail is displayed — decode/downsample images to the target display size (`UIGraphicsImageRenderer` downsampling, or a library that decodes at the target size) instead of decoding a full-resolution image and letting the view scale it down, which wastes both CPU and memory.
   - Nested/complex Auto Layout constraint graphs recalculated on every scroll frame — check for layout thrashing (reading a layout property then writing one, alternating, repeatedly).
   - SwiftUI: a `View`'s `body` doing non-trivial computation directly instead of deriving it once and storing/caching — SwiftUI recomputes `body` often, so expensive work inside it runs far more often than authors expect.

## Step 4: Memory footprint

1. Use the **Allocations** instrument to get a baseline of resident memory for the app's main flows, and check whether memory returns to baseline after navigating back out of a heavy screen (a screen visited and dismissed repeatedly should not accumulate memory).
2. Check the **VM Tracker** or Allocations' summary for the largest categories of memory use — commonly image caches, `NSCache`/custom caches without size limits, or a database layer's in-memory row cache.
3. Cross-check with `ios-debug-session`'s Instruments guidance if a true leak (not just a large-but-legitimate cache) is suspected — a growing cache with no eviction is a design issue to fix here; a true retain-cycle leak is a bug to fix there.
4. For image-heavy apps, check the image cache's memory limit is set relative to device capability (`NSCache.totalCostLimit`) rather than unbounded, and that a memory warning (`didReceiveMemoryWarning` / `UIApplication.didReceiveMemoryWarningNotification`) actually triggers cache eviction rather than being ignored.

## Step 5: Energy impact

1. Use Instruments' **Energy Log** template while performing a typical session of the app's core flow, on a real device (energy measurements on Simulator are not representative).
2. Check which subsystem dominates: CPU, networking radio usage, GPS, or display brightness/backlight-adjacent factors the app might indirectly cause (e.g. keeping the screen from dimming via `isIdleTimerDisabled` when not actually needed).
3. Common causes of high energy impact:
   - **Frequent, small network requests** instead of batching — each radio wake-up has a fixed energy cost regardless of payload size, so many small requests cost more than fewer larger ones.
   - **Polling instead of push** — a timer that polls a server every few seconds for updates should usually be replaced with push notifications or a long-lived connection with proper backoff.
   - **Location updates at unnecessarily high accuracy/frequency** — `kCLLocationAccuracyBest` with continuous updates when the feature only needs city-level accuracy or periodic checks is a common and easily fixed energy cost. Use the lowest accuracy and update frequency the feature actually needs, and stop updates when the relevant screen isn't visible.
   - **`isIdleTimerDisabled = true` left set** after a flow that needed the screen to stay awake (e.g. a video playback screen) has ended — this keeps the display on and drains battery until explicitly reset to `false`.

## Reporting the findings

Structure the audit output as:

1. **Symptom investigated** (what the user reported).
2. **Instrument used and what it showed** — be concrete: "Time Profiler showed 60% of main-thread time during scroll was spent in `DateFormatter.string(from:)`, called once per cell per frame."
3. **Root cause** — the actual mechanism, not just "it's slow."
4. **Recommended fix**, with the expected improvement mechanism explained (e.g. "caching the formatted date string per model object removes the per-frame formatting cost entirely").
5. **How to verify the fix** — re-run the same Instruments recording after the change and compare, rather than assuming the fix worked.

## Common pitfalls in the audit itself

- **Profiling in Debug configuration.** Debug builds are unoptimized and can be dramatically slower than Release in ways that don't reflect real user experience — always profile a Release-configuration build (Xcode: Product → Profile, which uses the Release configuration by default) unless specifically investigating a debug-only issue.
- **Profiling on Simulator only.** Simulator runs on Mac hardware and doesn't reflect real device CPU/GPU/thermal characteristics, especially for older/lower-end iPhones. Confirm findings on at least one representative real device, ideally an older supported model, not just the latest flagship.
- **Chasing a metric without a user-facing symptom.** A launch time improvement from 450ms to 400ms is not worth much engineering effort if no user has complained and it's already within Apple's general guidance — prioritize audits by actual reported pain points, not by chasing every number lower.
