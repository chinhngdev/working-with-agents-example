# Common Swift Concurrency pitfalls and how to avoid them

### `Task.detached` used by default
```swift
// ❌ Wrong — loses parent priority, task-local values, and actor context for no reason
func refresh() {
    Task.detached {
        await self.loadData()
    }
}

// ✅ Right — inherits caller's context/priority; still unstructured but scoped correctly
func refresh() {
    Task {
        await self.loadData()
    }
}
```
**Avoid:** reach for `Task { }` by default. Only use `Task.detached` when you deliberately need to escape the current actor/priority/task-local context — e.g. a background job that must keep running even if the triggering task is cancelled.

### Manual locks/`DispatchQueue` instead of an actor
```swift
// ❌ Wrong — easy to forget a lock somewhere, deadlock risk, no compiler enforcement
final class Cache {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    func set(_ key: String, _ value: Data) {
        lock.lock(); storage[key] = value; lock.unlock()
    }
}

// ✅ Right — compiler-enforced isolation, no manual locking
actor Cache {
    private var storage: [String: Data] = [:]
    func set(_ key: String, _ value: Data) {
        storage[key] = value
    }
}
```
**Avoid:** whenever mutable state is touched from more than one concurrency context, model it as an `actor` rather than guarding it by hand — the compiler rejects unsynchronized access instead of you finding it in a crash report.

### `.onAppear { Task { ... } }` instead of `.task`
```swift
// ❌ Wrong — doesn't cancel when the view disappears, can leak work / race a dismissed view
.onAppear {
    Task { await viewModel.load() }
}

// ✅ Right — cancels automatically on disappear
.task {
    await viewModel.load()
}
```
**Avoid:** never wrap `Task { }` inside `.onAppear` for view-lifecycle-bound async work — use `.task`/`.task(id:)` so cancellation is automatic. (See [[swiftui-skill]].)

### Ignoring cancellation in long-running work
```swift
// ❌ Wrong — keeps processing all 10,000 items even after the task is cancelled
func process(_ items: [Item]) async {
    for item in items {
        await expensiveWork(item)
    }
}

// ✅ Right — stops promptly when cancelled
func process(_ items: [Item]) async throws {
    for item in items {
        try Task.checkCancellation()
        await expensiveWork(item)
    }
}
```
**Avoid:** in any loop or multi-step async function that might run for more than a few milliseconds, check `Task.isCancelled`/`Task.checkCancellation()` between steps — cancellation is cooperative and does nothing unless the code checks for it.

### Continuation resumed zero or multiple times
```swift
// ❌ Wrong — resumes twice if the legacy API calls back on both success and error paths
func fetch() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        legacyAPI.fetch { data, error in
            if let error { continuation.resume(throwing: error) }
            if let data { continuation.resume(returning: data) } // can double-resume
        }
    }
}

// ✅ Right — exactly one resume on every path
func fetch() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        legacyAPI.fetch { data, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: FetchError.emptyResponse)
            }
        }
    }
}
```
**Avoid:** audit every callback path (success, failure, and any "impossible" case like both nil) to guarantee the continuation resumes exactly once — zero resumes hangs the awaiting task forever, more than one is a runtime trap in debug builds.

### `@Sendable` closures capturing mutable state
```swift
// ❌ Wrong — mutating a captured var from a concurrently-invoked closure is a data race
var total = 0
await withTaskGroup(of: Int.self) { group in
    for n in numbers {
        group.addTask { n * 2 }
    }
    for await value in group {
        total += value // captured mutable var, unsafe if this pattern is copied elsewhere
    }
}

// ✅ Right — accumulate on the single consuming context (this pattern is actually safe
// because `for await` runs serially on the calling task), but for state touched from
// *multiple* concurrent closures, isolate it in an actor instead:
actor Accumulator {
    private(set) var total = 0
    func add(_ value: Int) { total += value }
}
```
**Avoid:** never mutate a captured `var` from inside a `@Sendable` closure (task group child tasks, detached tasks) that could run concurrently with other mutators — route the mutation through an actor, or restructure so accumulation happens on one serial context.

### Polling instead of using `AsyncSequence`
```swift
// ❌ Wrong — wastes CPU, adds latency up to the poll interval, arbitrary sleep duration
func waitForConnection() async {
    while !connectionManager.isConnected {
        try? await Task.sleep(for: .milliseconds(100))
    }
}

// ✅ Right — event-driven, no polling
func waitForConnection() async {
    for await state in connectionManager.stateChanges {
        if state == .connected { break }
    }
}
```
**Avoid:** if you're writing `while` + `Task.sleep` to wait for a condition, model the underlying event source as an `AsyncStream` (or find the existing one) instead — polling burns resources and adds up to a full interval of latency.

### Inconsistent `@MainActor` isolation
```swift
// ❌ Wrong — some methods isolated, others not; callers get surprise `await`s and
// it's unclear which methods are safe to call from a background context
final class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    @MainActor func refresh() async { items = await fetch() }
    func fetch() async -> [Item] { ... } // not isolated — can this run anywhere?
}

// ✅ Right — isolate the whole type; every method is consistently on the main actor
@MainActor
final class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    func refresh() async { items = await fetch() }
    private func fetch() async -> [Item] { ... }
}
```
**Avoid:** isolate at the type level (`@MainActor` on the class) for view models where "everything touches UI state," rather than sprinkling `@MainActor` on individual methods — mixed isolation makes it hard to reason about which calls hop actors and creates unnecessary suspension points.

### `@unchecked Sendable`/`@preconcurrency` as a reflex fix
```swift
// ❌ Wrong — silences the compiler without proving thread-safety; the underlying
// race (if any) still exists, it's just no longer caught
final class ImageCache: @unchecked Sendable {
    private var storage: [URL: UIImage] = [:] // still unsynchronized!
}

// ✅ Right — either make it genuinely safe and document why, or fix the real issue
actor ImageCache {
    private var storage: [URL: UIImage] = [:]
}

// If truly unavoidable (e.g. verified internal locking), justify it explicitly:
final class LegacyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL: UIImage] = [:] // guarded by `lock` on every access — safe
}
```
**Avoid:** treating `@unchecked Sendable` or a blanket `@preconcurrency import` as the fast way past a Swift 6 compiler error. `@unchecked Sendable` is only safe when you've manually verified synchronization (and left a comment saying how); `@preconcurrency import` should scope to one specific un-migrated dependency, not paper over an isolation bug in your own code.
