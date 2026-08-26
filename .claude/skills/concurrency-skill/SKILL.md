---
name: concurrency-skill
description: Write or review Swift Concurrency code (async/await, actors, Task, Sendable, AsyncSequence, MainActor isolation) following modern Swift 6-ready best practices. Use when writing new async code, adding actors, fixing data races/isolation errors, migrating from completion handlers or DispatchQueue/GCD, or when the user asks for idiomatic Swift concurrency, or runs /concurrency-skill.
---

Apply these practices when writing or reviewing concurrency code in Swift/iOS projects. Prefer **Swift Concurrency** (`async`/`await`, actors, structured `Task`s) over GCD (`DispatchQueue`) or completion-handler closures for new code. Check the project's Swift language mode (Swift 5 vs Swift 6 strict concurrency, in `Package.swift`/build settings) before assuming full strict-concurrency checking is on — match the codebase's existing mode rather than introducing warnings it isn't configured to catch yet.

## 1. Structured concurrency first

- **Prefer structured over unstructured.** Use `async let` and `TaskGroup`/`withTaskGroup` for concurrent child work whose lifetime is scoped to the calling function. Reach for unstructured `Task { }` only when work must outlive the current scope (e.g. fire-and-forget from a synchronous context, or a view-lifecycle-bound task not already covered by `.task`).
- **`async let` for a fixed, known set of concurrent calls:**
  ```swift
  async let profile = fetchProfile()
  async let posts = fetchPosts()
  let result = try await (profile, posts)
  ```
- **`TaskGroup` for a dynamic/variable number of concurrent children** (e.g. one task per item in an array) — never spin up an array of unstructured `Task`s and manually await them.
- Every child task in a group or `async let` is automatically cancelled if the parent task is cancelled or throws — this is the main safety benefit over manual `Task` bookkeeping.

## 2. Task lifecycle & cancellation

- **In SwiftUI views:** use `.task { }` / `.task(id:)`, not `.onAppear { Task { } }` — `.task` auto-cancels when the view disappears. (See [[swiftui-skill]].)
- **Cooperative cancellation:** long-running async work must check `Task.isCancelled` or call `try Task.checkCancellation()` at reasonable points (loop iterations, before expensive steps) — cancellation is advisory, not preemptive. A cancelled task keeps running until it checks.
- **Don't swallow `CancellationError`.** Let it propagate; catching it to "handle cleanly" and continuing work defeats cancellation. Only catch it where you need cleanup (e.g. `defer`), then rethrow.
- **Unstructured `Task` handles:** if you create a `Task` you might need to cancel (e.g. a search-as-you-type task replaced on each keystroke), store the `Task` handle and call `.cancel()` on the old one before starting a new one — don't let them pile up.
- **Detached tasks (`Task.detached`) are a last resort.** They don't inherit the parent's actor context, priority, or task-local values. Only use when you deliberately need to escape the current context (e.g. a background job that must outlive a cancelled parent); a plain `Task { }` is almost always right instead.

## 3. Actors & isolation

- **Actors protect mutable state.** Wrap shared mutable state accessed from multiple concurrency contexts in an `actor`, not manual locks/`DispatchQueue.sync` — the compiler enforces isolation instead of relying on discipline.
- **`@MainActor` for UI-adjacent state.** View models backing SwiftUI views should be `@MainActor`-isolated (either the whole class with `@MainActor` on the type, or `@Observable @MainActor`) so UI updates never race off the main thread. (See [[swiftui-skill]] for the `@Observable` pairing.)
- **Minimize hops across isolation boundaries.** Every `await` at an actor boundary is a potential suspension point and a context switch. Batch related mutations into one actor method rather than several separate `await actor.setX()` / `await actor.setY()` calls that could interleave with other callers.
- **Non-isolated members** (`nonisolated func`) are for actor methods that don't touch actor-isolated state (e.g. pure computed values, `Sendable` constants) — use them to avoid unnecessary hops for callers that don't need isolation.
- **Global actors beyond `MainActor`:** define a custom `@globalActor` only when a *specific* shared resource (not just "the UI") needs single-owner serialized access across many types — otherwise prefer a plain `actor` instance passed via DI.

## 4. Sendable & data races

- **`Sendable` conformance is the contract for crossing isolation boundaries.** Types passed into `Task { }`, actor methods, or `TaskGroup` closures must be `Sendable` (or the compiler flags them under strict concurrency). Prefer value types (`struct`/`enum`) — they're `Sendable` for free when their members are.
- **Reference types crossing boundaries** need `final class ... : Sendable` with all-`let` immutable storage, or actor isolation, or explicit `@unchecked Sendable` — only use `@unchecked` when you've manually verified thread-safety (e.g. internal locking) and leave a comment on *why* it's safe, since the compiler can't check it for you.
- **Don't capture mutable var state in a `@Sendable` closure** (`Task { }`, `TaskGroup` child closures are implicitly `@Sendable`) — capture immutable copies or route through actor-isolated state instead.
- **Closures crossing into async contexts:** completion handlers stored for later async invocation should be `@Sendable` and capture only `Sendable` values.
- **Swift 6 language mode enables full data-race safety checking at compile time** (vs. Swift 5's opt-in warnings via `-strict-concurrency=complete`). If the project targets Swift 6 (`swiftLanguageMode(.v6)` in `Package.swift`, or the Xcode build setting), isolation/`Sendable` violations are **errors**, not warnings — don't suggest `@unchecked Sendable` or `@preconcurrency` as a quick silence-the-warning fix; treat them as a deliberate, documented escape hatch only.
- **Region-based isolation** (SE-0414) lets the compiler pass some non-`Sendable` values across isolation boundaries safely when it can prove the sender doesn't retain access afterward (e.g. handing off a locally-created, uniquely-referenced object into a `Task`). This is why some Swift 6 code compiles without explicit `Sendable` conformance — don't add unnecessary conformances or copies when the compiler already accepts the transfer; only reach for `Sendable`/actor isolation when it actually rejects it.
- **Sendable inference changed in Swift 6:** many standard library and SDK types gained implicit `Sendable` conformance, and public structs/enums in your own modules with all-`Sendable` members are now inferred `Sendable` without an explicit conformance in many contexts — but a type's inferred conformance is only visible to callers in the same module unless you declare it explicitly, so add an explicit `: Sendable` on public types you expect other modules to pass across boundaries.
- **`@preconcurrency import`** silences `Sendable`/isolation errors from a specific un-migrated dependency (older Objective-C-based UIKit/AppKit APIs, a third-party module without concurrency annotations) without disabling strict checking project-wide. Scope it to the one import that needs it rather than weakening the whole target's language mode; remove it once that dependency ships concurrency annotations. See [[uikit-skill]] for the specific UIKit/AppKit APIs this commonly applies to.

## 5. Migrating from GCD / completion handlers

- Replace `DispatchQueue.main.async { }` with `@MainActor` isolation or `await MainActor.run { }` (prefer isolating the whole function/type over one-off `MainActor.run` calls).
- Replace `DispatchQueue.global().async { }` + completion closure with a plain `async` function; callers `await` it instead of nesting a closure.
- Replace `DispatchSemaphore`/manual locks guarding shared state with an `actor`.
- Wrap legacy completion-handler APIs you can't yet rewrite using `withCheckedThrowingContinuation` (or `withCheckedContinuation` if it can't fail) — always resume the continuation on **every** path exactly once; resuming zero or multiple times is a runtime crash/undefined behavior in debug builds. The same technique bridges callback- and delegate-based UIKit/AppKit APIs into `async` code — see [[uikit-skill]] for imperative-UI-specific concerns (main-thread update requirements, delegate lifetime).
  ```swift
  func legacyWrapped() async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
          legacyFetch { data, error in
              if let error { continuation.resume(throwing: error) }
              else { continuation.resume(returning: data!) }
          }
      }
  }
  ```

## 6. AsyncSequence & streams

- Use `AsyncStream`/`AsyncThrowingStream` to bridge callback-based/event-driven APIs (delegates, notifications, KVO) into `async for` consumption, instead of manually managing a buffer of callback results.
- Consume with `for try await value in stream { }`; the loop exits cleanly on stream finish and propagates cancellation to the producer via the stream's `onTermination`.
- Set `onTermination` on `AsyncStream.Continuation` to clean up the underlying event source (remove observer, close connection) when the consumer stops iterating.
- Don't build a hand-rolled polling loop (`while true { await Task.sleep(...); check() }`) where an `AsyncSequence`/notification-driven stream would eliminate the polling and the sleep entirely.

## 7. Error handling in async code

- `async throws` functions propagate normally with `try`/`catch` — no special handling needed beyond ordinary Swift error handling.
- In a `TaskGroup`, a child task's thrown error surfaces at the next `await group.next()`/iteration — other children keep running unless you explicitly cancel the group (`group.cancelAll()`) on first failure if that's the desired semantics.
- Don't silently discard errors from fire-and-forget `Task { }` blocks — at minimum log them; a bare `try?` that hides a failure the user needed to see is a bug, not error handling.
- **Testing async code:** both Swift Testing and XCTest support `async` test functions directly — no `XCTestExpectation` wrapper needed for structured `async`/`await`. See [[apple-testing]] for framework choice and patterns.

## 8. Common pitfalls

- Wrapping every async call in `Task.detached` "to be safe" — breaks context/priority inheritance for no reason.
- Manual `DispatchQueue`/locks guarding state that should be an `actor`.
- `.onAppear { Task { ... } }` instead of `.task` — no auto-cancellation.
- Forgetting to check `Task.isCancelled` in long loops — cancelled work keeps burning CPU/network.
- Resuming a `withCheckedContinuation` zero times (hangs forever) or more than once (crash).
- Capturing `self` or mutable vars in a `@Sendable` closure without isolation, causing compiler errors or (under relaxed checking) real data races.
- Polling with `Task.sleep` in a loop instead of using `AsyncSequence`/actual completion signals.
- Mixing `@MainActor` isolation inconsistently — some methods isolated, others not, causing surprise hops or compiler-inserted `await`s that mask a design issue.
- Reaching for `@unchecked Sendable` or `@preconcurrency import` as the first fix for a Swift 6 compiler error instead of understanding and addressing the actual isolation/data-race issue — these silence the checker without proving safety.

**For the failure mode, a ❌/✅ code example, and the fix for each pitfall, read `references/common-pitfalls.md`.**

## When reviewing existing code

Check for the pitfalls in section 8 above — read `references/common-pitfalls.md` for the exact patterns to grep for. Point out the specific line and the concrete failure mode (e.g. "this closure captures mutable state without isolation — data race under concurrent access" or "this task is never cancelled when the view disappears") rather than generic style nitpicks.
