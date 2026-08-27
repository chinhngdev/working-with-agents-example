---
name: swift-concurrency-migration
description: Migrates iOS code from completion handlers or Combine to Swift's async/await, actors, and structured concurrency, and helps prepare a codebase for Swift 6 strict concurrency checking. Use when the user asks to migrate to async/await, convert a completion handler, fix a data race warning, resolve a Sendable error, or asks about Task, actor, or @MainActor usage.
---

# Swift Concurrency Migration

## Purpose

Guide the conversion of callback-based or Combine-based code to Swift's modern concurrency model (`async`/`await`, `actor`, structured `Task`s), and help resolve the compiler errors that appear when enabling Swift 6's strict concurrency checking. This is one of the most common sources of confusion for iOS developers right now, since strict concurrency surfaces latent data races that previously compiled silently.

## Step 1: Assess the starting point

Ask or determine:

- Swift language mode currently in use (Swift 5 with minimal concurrency, Swift 5 with `-strict-concurrency=complete`, or Swift 6 mode).
- What's being migrated: a single completion-handler function, a whole networking layer, a Combine pipeline, or the entire app.
- Whether this is a "make it compile" pass (fixing Swift 6 errors) or a "make it correct" pass (actually finding and fixing real data races the compiler now reveals).

These are different jobs. Slapping `@unchecked Sendable` everywhere makes Swift 6 compile but doesn't fix anything — flag this distinction to the user early if they seem to be aiming for a quick fix rather than a real migration.

## Step 2: Convert completion handlers to async/await

Basic pattern using `withCheckedContinuation` / `withCheckedThrowingContinuation` for APIs that aren't already async:

```swift
// Before
func fetchUser(id: String, completion: @escaping (Result<User, Error>) -> Void) {
    session.dataTask(with: url) { data, _, error in
        if let error { completion(.failure(error)); return }
        // ...
        completion(.success(user))
    }.resume()
}

// After
func fetchUser(id: String) async throws -> User {
    try await withCheckedThrowingContinuation { continuation in
        session.dataTask(with: url) { data, _, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            // ...
            continuation.resume(returning: user)
        }.resume()
    }
}
```

Rules to enforce during this conversion:

- **The continuation must be resumed exactly once**, on every code path. Missing a resume hangs the calling `Task` forever; resuming twice is a runtime crash. Walk every branch (success, failure, early return) explicitly.
- Prefer `URLSession`'s native `async` API (`try await session.data(for: request)`) over wrapping the completion-handler API in a continuation, when available — it's simpler and avoids the resume-discipline problem entirely.
- For Apple frameworks that already ship an `async` overload (most of `URLSession`, `CLLocationManager` in recent SDKs, etc.), migrate to the native async API rather than hand-rolling a continuation wrapper.

## Step 3: Convert Combine pipelines

Combine and async/await interop, but full removal of Combine is often not worth it in one pass. Guidance:

- A `Future` publisher wrapping a single async value is often better expressed directly as an `async` function — recommend removing the `Future` wrapper if nothing downstream specifically needs Combine's operators.
- `AsyncSequence`/`AsyncStream` is the async/await equivalent of a Combine stream (`@Published`, `PassthroughSubject`) for ongoing sequences of values. Convert a `PassthroughSubject`-based event stream to `AsyncStream` when the only consumer is `async` code and no Combine operators (`.debounce`, `.combineLatest`, etc.) are actually being used — if those operators are load-bearing, keep Combine for that pipeline.
- `@Published` properties on an `ObservableObject` can coexist with async/await — no need to convert these just because other code in the file uses async; only convert what benefits from it.

## Step 4: Actors and @MainActor

- **Use `actor`** to protect mutable shared state accessed from multiple tasks/threads (caches, in-memory stores, connection pools). The compiler enforces that access happens through `await`, serializing mutations automatically.
  ```swift
  actor ImageCache {
      private var storage: [URL: UIImage] = [:]

      func image(for url: URL) -> UIImage? { storage[url] }
      func store(_ image: UIImage, for url: URL) { storage[url] = image }
  }
  ```
- **Use `@MainActor`** on any type or method that touches UIKit/SwiftUI/AppKit — this is not optional under strict concurrency; UI frameworks are main-actor-isolated.
- **Don't mark an entire heavy-computation class `@MainActor`** just to silence a warning — this forces all its work onto the main thread, which can cause UI jank. Instead, isolate only the UI-touching pieces, and let the computation happen off-actor, then hop to `@MainActor` only to publish the result.
- **Global mutable state (`static var`) needs an actor or `@MainActor`** under strict concurrency — this is one of the most common sources of new compiler errors when migrating. If it was a plain `static var` before, decide whether it's UI-related (`@MainActor`) or general shared state (wrap in an `actor` or make it a `let` if it can be immutable).

## Step 5: Resolving `Sendable` errors

When the compiler complains a type crossing a `Task`/actor boundary isn't `Sendable`:

1. **Best fix: make it actually safe.** If the type is a value type (`struct`/`enum`) with only `Sendable` stored properties, add `: Sendable` — the compiler verifies it.
2. **If it's a class that's genuinely immutable** (all `let` properties, no mutation after init), mark it `final class Foo: Sendable` — the compiler will verify all properties are `Sendable` too.
3. **If it's a class with mutable state that's actually protected** by a lock or is only ever accessed from one actor context in practice, and refactoring to an `actor` is too large a change right now: `@unchecked Sendable` is the escape hatch, but the reviewer must confirm the safety claim manually — don't apply this without verifying the type really is protected. Flag this to the user as technical debt to revisit, not a real fix.
4. **If the type is a delegate/callback that crosses boundaries by design** (e.g. a completion handler stored and called from a background queue), consider whether the closure itself needs to be marked `@Sendable`.

## Step 6: Validate the migration

After converting a section of code:

- Confirm no `withCheckedContinuation` resumes are missing or duplicated (walk every return path again).
- Run the app under Xcode's Thread Sanitizer at least once after any concurrency migration touching shared mutable state — the compiler catches many races statically, but TSan catches runtime ones the type system can't express.
- If migrating a whole module to Swift 6 language mode, do it incrementally — enable strict concurrency checking (`-strict-concurrency=complete`) under Swift 5 first, fix warnings, *then* flip the language mode to Swift 6, rather than doing both at once.

## Common errors and fixes

### "Call to main actor-isolated instance method in a synchronous nonisolated context"
**Cause:** Calling a `@MainActor` method from a non-isolated context (e.g. a background `Task` or a plain synchronous function).
**Fix:** Either mark the calling context `@MainActor` too (if it belongs on the main actor), or explicitly hop: `await MainActor.run { self.updateUI() }`.

### "Sending 'x' risks causing data races"
**Cause:** A value that isn't `Sendable` is being passed into a `Task` or across an actor boundary.
**Fix:** See Step 5 — make the type `Sendable`, wrap the mutable state in an `actor`, or use `@unchecked Sendable` only after manually verifying safety.

### Continuation leak — task hangs forever
**Cause:** A code path inside `withCheckedContinuation` never calls `resume`.
**Fix:** Audit every branch of the wrapped completion handler; add an explicit `resume` on error/early-return paths that were previously implicit `return`s in the callback style.

### "Actor-isolated property cannot be mutated from a non-isolated context"
**Cause:** Trying to mutate an actor's stored property directly from outside the actor without `await`.
**Fix:** Add a method on the actor that performs the mutation, and call it with `await actorInstance.method()` — external code cannot poke an actor's internals directly by design.

## Example

**User says:** "I'm getting a Sendable error on my ImageDownloader class when I try to use it inside a Task."

**Actions:**
1. Ask to see the class — check if it has mutable stored properties (a cache dictionary, a counter) or is otherwise stateful.
2. If stateful and accessed from multiple tasks: recommend converting `class ImageDownloader` to `actor ImageDownloader`, and updating call sites to `await downloader.image(for: url)`.
3. If stateless (just holds a `URLSession` and has no mutable state): mark it `final class ImageDownloader: Sendable` — the compiler will confirm `URLSession` (already `Sendable`) is the only stored property.

**Result:** The Sendable error is resolved with a fix that matches the actual concurrency safety of the type, not a blanket suppression.
