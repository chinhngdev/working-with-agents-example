---
name: ios-debug-session
description: Runs a structured debugging session for iOS crashes and bugs, covering crash log symbolication, Xcode Organizer diagnostics, and Instruments (Time Profiler, Leaks, Allocations). Use when the user has a crash log, stack trace, ".ips" crash file, or asks to debug a crash, symbolicate a crash log, find a memory leak, or investigate unexpected app behavior.
---

# iOS Debug Session

## Purpose

Provide a structured reproduce-isolate-diagnose-fix workflow for iOS-specific bugs and crashes, with concrete guidance on reading crash logs, symbolicating them, and using Instruments to find root causes that aren't obvious from a stack trace alone.

## Step 1: Classify the problem

Ask or determine which category this is — the approach differs significantly:

- **Crash with a stack trace / `.ips` file** → go to Step 2 (crash log analysis).
- **Reported crash with no trace available** (e.g. "users say it crashes sometimes") → go to Step 3 (reproduction).
- **Memory growth / leak suspected** → go to Step 4 (Instruments: Allocations/Leaks).
- **Performance issue, not a crash** (slow, janky) → recommend the `ios-performance-audit` skill instead, which covers Time Profiler and launch time in depth.
- **Wrong behavior, no crash** (logic bug) → go to Step 5 (general isolation approach).

## Step 2: Reading and symbolicating a crash log

A `.ips` crash report has these key sections — check each:

1. **Exception Type** — tells you the crash class:
   - `EXC_BAD_ACCESS` — invalid memory access, usually a use-after-free (dangling pointer/reference) or a data race.
   - `EXC_BREAKPOINT` (often `SIGTRAP`) — commonly a Swift runtime trap: force unwrap of `nil`, array out-of-bounds, integer overflow, or a fatal `precondition`/`fatalError`.
   - `EXC_CRASH (SIGABRT)` — often an uncaught Objective-C/Swift exception, or an explicit `abort()` (e.g. from a failed `assert`).
   - `0xdead10cc` — the app was killed for holding a file lock/SQLite lock while suspended in the background — check for a database or file handle not released before backgrounding.
   - `0x8badf00d` — watchdog termination: the app took too long to launch, respond to a state transition, or return from a background task. Check `applicationDidEnterBackground`/launch-time work.
2. **Crashed thread's backtrace** — find the thread marked `Crashed:`. If the symbols show hex addresses/offsets instead of function names, the log needs symbolication (see below).
3. **Binary Images section** — confirms the exact build (UUID) that produced this crash, which must match the `.dSYM` used for symbolication.

### Symbolicating a crash log

If Xcode Organizer (Window → Organizer → Crashes) already shows the crash for a build uploaded via App Store Connect/TestFlight, it auto-symbolicates as long as the matching `.dSYM` was uploaded (Xcode does this automatically for archives, unless `DEBUG_INFORMATION_FORMAT` was misconfigured).

For a raw `.ips` file symbolicated manually:

```bash
# Confirm the dSYM's UUID matches the crash log's binary image UUID
dwarfdump --uuid YourApp.app.dSYM

# Symbolicate
xcrun atos -o YourApp.app.dSYM/Contents/Resources/DWARF/YourApp \
  -arch arm64 \
  -l <slide_address_from_crash_log> \
  <hex_address_from_backtrace>
```

Or drag the `.ips` file into Xcode Organizer directly — if the matching archive (with its `.dSYM`) is still present in Xcode's Organizer, it symbolicates automatically without manual `atos` calls.

**Common blocker:** dSYM UUID mismatch — this means the crash came from a different build than the dSYM being used. Verify the build number in the crash log matches the build being investigated; if using Bitcode-adjacent or App Thinning variants, the "slice" (arch/variant) also needs to match.

## Step 3: Reproducing an intermittent crash

When no crash log is available yet, or the trace alone isn't enough to identify the cause:

1. Ask for the exact steps the user (or their bug reporter) took — device model, iOS version, and whether it's reproducible on demand or only occasionally.
2. Check whether it correlates with a specific condition: low memory (background app refresh + heavy foreground app), poor network (airplane mode toggling mid-request), backgrounding mid-operation, or a specific device (older hardware, different screen size).
3. Enable relevant Xcode diagnostics for the next reproduction attempt:
   - **Address Sanitizer + Undefined Behavior Sanitizer** (Edit Scheme → Diagnostics) — catches memory corruption and undefined behavior that might not otherwise crash reliably.
   - **Thread Sanitizer** — catches data races; essential if `EXC_BAD_ACCESS` is suspected to come from concurrent mutation (see `swift-concurrency-migration` skill for the underlying fix once identified).
   - **Zombie Objects** (Objective-C interop code only) — turns a use-after-free into an immediate, readable crash message identifying the deallocated object's class, instead of a generic `EXC_BAD_ACCESS`.
4. If it only reproduces in production/TestFlight and not under Xcode's debugger, check whether it's a release-only issue: `-O` optimization changing timing-sensitive behavior, or a `#if DEBUG` code path masking the bug locally.

## Step 4: Instruments — Leaks and Allocations

Use when a memory leak or unexpected memory growth is suspected:

1. **Allocations instrument**: record a session that includes the suspected leaking flow performed several times in a loop (e.g. push/pop the same screen 10 times). Use the "Mark Generation" button between each cycle — if memory from a generation never gets collected, everything allocated in that generation and never freed is a leak candidate.
2. **Leaks instrument**: runs alongside Allocations and flags objects with no remaining references but not deallocated (true retain cycles) — but note it only catches leaks it can prove structurally; not all memory growth is a "leak" in this strict sense (see: caches that just grow unbounded, which Leaks won't flag but Allocations growth will show).
3. In the Allocations detail view, use "Call Trees" grouped by "Invert Call Tree" to find which line of code is responsible for the retained allocations — trace back to the actual `class`/closure holding the reference.
4. Cross-reference with the `ios-code-review` skill's retain-cycle patterns (missing `[weak self]`, undeleted `NotificationCenter` observers, uncancelled Combine subscriptions) once Instruments identifies the specific type that's leaking.

## Step 5: Isolating a non-crashing logic bug

1. Reproduce with the minimum steps possible — strip away unrelated app state until the bug still occurs with the fewest preconditions.
2. Add targeted logging (or breakpoints with "Log Message" actions that don't halt execution) at each stage of the suspected code path, rather than scattering `print` statements that then need manual removal.
3. Bisect: if the bug is a regression (worked before, broken now), use `git bisect` against a range of commits with a scripted repro if possible, to find the exact commit that introduced it.
4. Check for platform-version-specific behavior — an API's documented behavior sometimes changes between iOS versions; check the "Deprecated"/"Changes" notes for any API in the suspected code path against the specific OS version where the bug reproduces.

## Common errors and their usual causes

### `EXC_BAD_ACCESS` in release only, not in debug
**Likely cause:** A data race that debug builds' slower execution/extra checks happen to avoid triggering, or an optimizer-dependent timing issue. Enable Thread Sanitizer and try to reproduce; review any recently touched concurrent code.

### App killed with `0x8badf00d` right after backgrounding
**Likely cause:** Long-running work in `applicationDidEnterBackground` or a background task that isn't properly ended (missing `endBackgroundTask`). Check every `beginBackgroundTask` has a matching `endBackgroundTask` on all code paths, including error paths.

### Crash log shows symbols from a system framework only, nothing from the app's own code
**Likely cause:** The app is calling into the framework in a way that violates its contract (e.g. calling a UIKit API off the main thread, mutating a collection while iterating it). Check the frame just above the system frames in the app's own code for what triggered the call.

### Leaks instrument shows nothing, but Allocations memory keeps climbing
**Likely cause:** Not a structural leak — likely an unbounded cache, growing array, or a subscription/delegate list that's never pruned. Look for `append`/insert calls without a corresponding removal anywhere in the suspected type.
