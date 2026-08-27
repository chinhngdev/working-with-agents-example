---
name: ios-code-review
description: Reviews Swift and Objective-C code for iOS-specific bugs including retain cycles, thread safety violations, force unwraps, memory leaks in closures, and Swift concurrency misuse. Use when the user asks to review a Swift file, pull request, or diff, or says "review this code", "check for retain cycles", "is this thread safe", or pastes Swift code asking for feedback.
disable-model-invocation: false
user-invocable: false
context: fork
---

# iOS Code Review

## Purpose

Review Swift/Objective-C code for the specific classes of bugs that are common in iOS development and easy to miss in a generic code review: retain cycles, thread-safety violations, unsafe unwrapping, and concurrency misuse. This complements general code review practices with iOS-specific expertise.

## Review checklist

Work through these categories in order. Quote the exact line(s) in question when flagging an issue, and always explain *why* it's a problem (what user-visible bug or crash it causes), not just that it violates a rule.

### 1. Memory management and retain cycles

- **Closures capturing `self` strongly** in a property that `self` also owns (e.g. a completion handler stored on a long-lived object, a `Timer` closure, a Combine `sink`). Flag if `[weak self]` or `[unowned self]` is missing.
  ```swift
  // Flag this:
  networkService.fetch { data in
      self.updateUI(with: data)   // strong capture, retain cycle if networkService holds this closure
  }
  // Prefer:
  networkService.fetch { [weak self] data in
      guard let self else { return }
      self.updateUI(with: data)
  }
  ```
- **`unowned` used defensively "just in case"** — `unowned` crashes if the reference is deallocated before use. Only recommend `unowned` when the capturing object's lifetime is provably shorter than or equal to the captured object's (e.g. a child that cannot outlive its parent). Default to `weak` unless there's a clear reason.
- **Delegate properties declared `strong`/without `weak`.** Delegate references should almost always be `weak var delegate: SomeDelegate?` to avoid owner/delegate retain cycles.
- **NotificationCenter observers not removed**, or added repeatedly (e.g. in `viewWillAppear` without a matching removal in `viewWillDisappear`) — causes duplicate handling and potential crashes on deallocated objects with pre-iOS 9 style observers.
- **Combine `Cancellable`/`AnyCancellable` not stored**, or stored in a set that's never cleared — subscriptions may be released immediately (bug) or never released (leak), depending on which side is missing.

### 2. Thread safety and concurrency

- **UI updates off the main thread.** Any `UIView`/`UIViewController`/SwiftUI state mutation must happen on the main actor. Flag `DispatchQueue.global().async { self.label.text = ... }` or similar without hopping back to `.main`.
- **Mutable shared state accessed from multiple queues/tasks without synchronization** — look for class properties mutated both inside `Task { }` blocks and from synchronous code, or from multiple `DispatchQueue.global()` calls, without a lock, actor, or serial queue protecting them.
- **`@MainActor` misapplied or missing.** If a class talks to UIKit/SwiftUI, it likely needs `@MainActor` on the class or the specific methods that touch UI. Check that `@MainActor` isn't slapped on a class that also does heavy synchronous work that should be off the main thread (that defeats concurrency benefits).
- **`Sendable` violations.** In Swift 6 strict concurrency (or when preparing for it), flag types crossing actor/task boundaries that aren't `Sendable` and aren't obviously safe (immutable, value types). A class with mutable stored properties passed into a `Task` closure is a red flag.
- **Race conditions from `async let` or `TaskGroup`** writing to the same variable without isolation — even structured concurrency doesn't protect shared mutable state automatically.

### 3. Force unwrapping and unsafe operations

- **`!` on optionals from external input** (network responses, user input, `UserDefaults`, JSON decoding) — this is the single most common cause of production crashes. Flag any force unwrap whose value isn't guaranteed non-nil by the immediately preceding code.
  ```swift
  // Flag this:
  let user = try! JSONDecoder().decode(User.self, from: data)
  let name = response["name"] as! String

  // Prefer:
  guard let user = try? JSONDecoder().decode(User.self, from: data) else {
      // handle decode failure explicitly
      return
  }
  ```
- **`try!` on any I/O, decoding, or network-adjacent call.** Same reasoning as force unwrap — the environment is not fully in the developer's control.
- **Force casts (`as!`)** where the type isn't provably guaranteed (e.g. casting a generic `Any` from a dictionary, a `UITableViewCell` dequeue without confirming the registered class).
- **Array/dictionary subscript access assumed safe** (`array[0]` without checking `isEmpty`, `dictionary["key"]!`) — flag unless bounds are checked immediately above.
- Force unwraps that are *actually fine* (e.g. `@IBOutlet` properties, which Interface Builder guarantees are connected before use, or a literal `URL(string: "https://known-valid.com")!`) do not need to be flagged — don't create noise by objecting to every `!` reflexively.

### 4. Structural and stylistic issues (secondary priority)

- Massive View Controllers / God ViewModels doing too much (defer to `ios-architecture-review` for a full architecture discussion, but flag it briefly here if egregious).
- Missing `deinit` logging/cleanup where a resource (timer, observer, file handle) needs explicit teardown.
- Inconsistent error handling — some paths use `Result`, others throw, others silently swallow errors with `try?` and no fallback logic.

## Output format for a review

For each finding, report:

1. **File and line** (or code excerpt if no file path given).
2. **The problem**, stated concretely — not "this could be an issue" but "this closure captures `self` strongly while `self` owns `networkService`, creating a retain cycle that will leak this view controller."
3. **Concrete fix** — show the corrected code, not just a description of the fix.
4. **Severity** — flag whether this is a likely crash (force unwrap on untrusted input, thread-safety violation causing an EXC_BAD_ACCESS), a leak (retain cycle), or a maintainability concern (style/structure).

Rank findings most severe first: crashes and data races before leaks, leaks before style issues.

## What NOT to flag

- `@IBOutlet` force unwraps — these are a standard, safe iOS pattern.
- `unowned`/force unwraps in test code or `#if DEBUG` blocks, unless the user is specifically asking about test code quality.
- Style preferences that don't affect correctness (e.g. trailing closure syntax choices) unless the user asks for a style review specifically.

## Example

**User pastes:**
```swift
class ProfileViewModel {
    var onUpdate: (() -> Void)?
    let session: URLSession

    func load() {
        session.dataTask(with: url) { data, _, _ in
            self.user = try! JSONDecoder().decode(User.self, from: data!)
            self.onUpdate!()
        }.resume()
    }
}
```

**Review output:**
1. **Retain cycle (leak), line 5:** The closure captures `self` strongly, and `self` doesn't obviously own this closure long-term here — but if `onUpdate` or the dataTask closure is stored anywhere retained by `self`, this leaks. Recommend `[weak self] data, _, _ in guard let self else { return }`.
2. **Crash risk, line 6:** `data!` will crash if the network call fails (no data). `try!` will crash on any decode failure (malformed JSON, schema mismatch). Both are on untrusted network input — replace with `guard let data, let user = try? JSONDecoder().decode(User.self, from: data) else { /* handle error */ return }`.
3. **Crash risk, line 7:** `onUpdate!` force-unwraps an optional closure that may legitimately be nil (e.g. before the view is set up). Use `onUpdate?()` instead.
4. **Thread safety, line 6:** `dataTask` completion runs on a background queue; if `self.user` triggers UI updates (e.g. via `didSet` or Combine publishing to a SwiftUI view), this must be dispatched to the main actor.
