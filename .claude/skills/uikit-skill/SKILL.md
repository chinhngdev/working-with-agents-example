---
name: uikit-skill
description: Write, review, or refactor UIKit (iOS/iPadOS/tvOS) and AppKit (macOS) code — view controllers, Auto Layout, table/collection views, delegation, and interop with SwiftUI — following modern Apple-recommended best practices. Use when creating new UIKit/AppKit screens, reviewing existing imperative UI code, migrating from older patterns, or when the user asks for idiomatic UIKit/AppKit, or runs /uikit-skill.
---

Apply these practices when writing or reviewing imperative UI code with UIKit (iOS/iPadOS/tvOS) or AppKit (macOS). The two frameworks share most concepts (Auto Layout, target-action, delegation, `UIView`/`NSView` hierarchies) — differences are called out explicitly below. Check whether the project's screens are UIKit/AppKit or SwiftUI-hosted-in-UIKit before assuming a pattern; match the existing convention in the file you're touching rather than mixing paradigms in one screen.

## 1. View controller lifecycle & memory management

- **Know the lifecycle order.** `viewDidLoad` runs once — do one-time setup (subview hierarchy, constraints, data source wiring) there, not in `viewWillAppear`/`viewDidAppear`, which run every time the screen becomes visible. Put per-appearance work (refreshing data, starting timers/observers) in `viewWillAppear`/`viewDidAppear`+`viewWillDisappear`/`viewDidDisappear` pairs, and tear down what you started (invalidate timers, remove observers) in the matching disappear callback.
- **`[weak self]` in closures and long-lived callbacks.** Any closure stored or escaping beyond the current call (completion handlers, `DispatchQueue.main.async`, animation completion blocks, Combine sinks) that captures `self` must use `[weak self]` if `self` is a view controller/view holding that closure — otherwise it's a retain cycle: the object keeps the closure alive, the closure keeps a strong `self`, neither deallocates.
- **Delegates are `weak`.** Declare delegate properties `weak var delegate: SomeDelegate?` (protocol must be `AnyObject`-constrained) — a strong delegate reference back to an owning view controller is a guaranteed retain cycle.
- **NotificationCenter/KVO observers.** Remove observers you add manually (`removeObserver`) in `deinit` or the matching lifecycle teardown — modern block-based `addObserver(forName:...)` returns a token that must also be removed; only the pre-iOS 9 `#selector`-based API auto-removes on dealloc, and even then only for `NSObject` targets, not modern Swift-only types.
- **AppKit difference: no `viewDidAppear`/`viewWillDisappear` guarantee on window close the way UIKit guarantees on dismiss.** `NSViewController` lifecycle is tied to the view being added to a window; watch `viewDidDisappear` behavior differs for windows vs. UIKit's guaranteed navigation-driven disappear — verify teardown actually fires for your presentation style (sheet, popover, tab) rather than assuming UIKit semantics port over.

## 2. Auto Layout

- **Activate constraints via `NSLayoutConstraint.activate([...])`**, not one-by-one `.isActive = true` calls scattered through a method — one batch activation is clearer and avoids intermediate unsatisfiable-constraint states.
- **Set `translatesAutoresizingMaskIntoConstraints = false`** on every view you constrain programmatically — forgetting this is the most common "my constraints do nothing" bug, because the auto-generated frame-based constraints conflict with yours.
- **Prefer `UIStackView`/`NSStackView`** for linear layouts (rows/columns of views) over hand-written leading/trailing/top/bottom constraints between siblings — far less code, and insertion/removal/hiding (`isHidden` on an arranged subview animates the stack) is handled for you.
- **Avoid layout thrashing.** Don't read a layout-dependent property (`.frame`, `.bounds`) immediately after changing constraints without forcing layout (`layoutIfNeeded()`) first — you'll read stale geometry. Conversely, don't call `layoutIfNeeded()`/`setNeedsLayout()` in a loop or on every scroll/draw callback; batch constraint changes and let one layout pass happen.
- **Animating constraint changes:** change the constant/constraint, then wrap `self.view.layoutIfNeeded()` in the animation block — not the constraint mutation itself:
  ```swift
  heightConstraint.constant = 200
  UIView.animate(withDuration: 0.3) {
      self.view.layoutIfNeeded()
  }
  ```
- **Interface Builder vs. code:** storyboards/XIBs are fine for static, designer-collaborative screens; prefer programmatic Auto Layout for highly dynamic screens, reusable components, or when merge conflicts on IB's XML have been a recurring problem — don't relitigate an existing project's established choice mid-feature.
- **AppKit difference — flipped coordinates.** `NSView` defaults to a bottom-left origin (non-flipped) unlike `UIView`'s top-left origin; override `var isFlipped: Bool { true }` on custom `NSView` subclasses doing manual drawing/layout math to get UIKit-like top-down coordinates, or account for the flip explicitly if you don't.

## 3. Table & collection views

- **Prefer diffable data sources** (`UITableViewDiffableDataSource`/`UICollectionViewDiffableDataSource`, `NSTableViewDiffableDataSource`/`NSCollectionViewDiffableDataSource`) over manual `numberOfRows`/`cellForRow` + `reloadData()`/`beginUpdates`/`endUpdates` bookkeeping. Apply a new `NSDiffableDataSourceSnapshot` and let the framework compute and animate the diff — manual `insertRows(at:)`/`deleteRows(at:)` index math is a frequent source of "attempt to delete row 3, but only 2 rows exist" crashes from state drift.
- **Compositional layout** (`UICollectionViewCompositionalLayout`) for anything beyond a uniform grid — sections with different layouts, orthogonal scrolling, adaptive sizing — instead of subclassing `UICollectionViewFlowLayout` or hand-rolling `UICollectionViewLayout`.
- **Cell reuse pitfalls:** reset any cell state that isn't set unconditionally by your configuration code — image views, accessory state, in-flight image loads — in `prepareForReuse()`, or a recycled cell shows stale content from its previous item while a new async load is in flight. Cancel/discard the previous cell's in-flight image task in `prepareForReuse()` before configuring the new one.
- **Register cells with their reuse identifier once** (`register(_:forCellReuseIdentifier:)`/class-based registration) and dequeue with `dequeueReusableCell(withIdentifier:for:)` — never conditionally instantiate a fresh cell in `cellForRow` "as a fallback"; that defeats reuse and masks registration bugs.
- **Row/item height:** use self-sizing (`UITableView.automaticDimension` + a correctly-constrained cell) over manually computing heights, unless profiling shows a real performance need for fixed/estimated heights on very large lists.
- **AppKit difference:** `NSTableView`/`NSCollectionView` use a view-based (not cell-based) model by default and separate the data source (`NSTableViewDataSource`) from the delegate (`NSTableViewDelegate`) more strictly than UIKit's combined patterns in older APIs — use `NSTableCellView` reuse via `makeView(withIdentifier:owner:)`, analogous to `dequeueReusableCell`.

## 4. Delegation, target-action, and notifications — when to use each

- **Delegation (protocol + `weak var delegate`):** one-to-one, synchronous, often needs a return value (`shouldSelect`, `numberOfRows`) or fine-grained callback sequencing. Default choice for a component reporting to its owner.
- **Target-action (`addTarget(_:action:for:)` / `NSButton`'s `target`/`action`):** simple one-to-one UI event → handler for controls (buttons, sliders, switches). Don't reach for a full delegate protocol for a single button tap.
- **Closures/callbacks (`var onTap: (() -> Void)?`)** as a lighter-weight alternative to single-method delegate protocols, especially for reusable cells/components — avoids boilerplate protocol declarations for a one-callback contract. Still needs `[weak self]` discipline where captured.
- **NotificationCenter:** one-to-many broadcast, or when sender and observer have no direct reference to each other (e.g. system events like `keyboardWillShow`, cross-module communication). Don't use it as a substitute for direct delegation between two objects that already hold references to each other — it's harder to trace and type-unsafe (`userInfo` is `[AnyHashable: Any]`).
- **KVO** — mostly legacy at this point; prefer Combine publishers or plain closures/delegation for new code unless observing an Objective-C/AppKit API that only exposes KVO (e.g. some `NSOperation`/`NSViewAnimation` properties).

## 5. Interfacing with SwiftUI

- **Hosting SwiftUI inside UIKit/AppKit:** `UIHostingController`/`NSHostingController` wraps a SwiftUI view for use in a UIKit/AppKit hierarchy — add it as a child view controller (`addChild`, `didMove(toParent:)`) like any other, not just its `.view` alone, or lifecycle events won't propagate correctly.
- **Hosting UIKit/AppKit inside SwiftUI:** implement `UIViewRepresentable`/`UIViewControllerRepresentable` (`NSViewRepresentable`/`NSViewControllerRepresentable` on macOS) — `makeUIView`/`makeCoordinator` for setup, `updateUIView` for SwiftUI-driven state changes flowing in, and a `Coordinator` conforming to the UIKit delegate protocol to flow UIKit events back out to SwiftUI via bindings/closures.
- **Don't fight the boundary.** Keep the wrapped surface as small and self-contained as possible (one control, one specific view) rather than wrapping an entire screen "because it's easier" — that forfeits most of SwiftUI's declarative benefits. See [[swiftui-skill]] for the SwiftUI-side state/data-flow conventions the wrapper should respect.

## 6. Concurrency & main-thread UI updates

- **All UIView/NSView/UIViewController/NSViewController API is main-thread-only.** Mark view controllers/custom views `@MainActor` (or rely on `UIViewController`/`NSViewController`'s implicit main-actor isolation on modern SDKs) so the compiler catches accidental background-thread UI mutation instead of it surfacing as a flaky crash or visual glitch in production.
- **Use `async`/`await` for network/disk work triggered from a view controller**, hopping back with the type-level `@MainActor` isolation rather than manual `DispatchQueue.main.async` — see [[concurrency-skill]] for structured-concurrency and actor-isolation patterns that apply identically here.
- **Cancel in-flight work on teardown/reuse:** store the `Task` for a view controller's async load and `.cancel()` it in `viewDidDisappear`/`deinit` (or a cell's `prepareForReuse()`) so a slow response doesn't mutate a dismissed/recycled view after the fact.

## 7. Testability of view controllers

- **Push logic out of the view controller** into a view model/presenter the view controller merely observes and forwards user actions to — this is what makes the logic testable without instantiating `UIViewController`/`NSViewController` or touching the view hierarchy at all. See [[apple-testing]] for how to structure and test that extracted layer.
- **Inject dependencies** (networking, persistence, formatters) through the initializer as protocols, not `AppDelegate`/singleton reach-through from inside the view controller — same DI principle as SwiftUI view models.
- **Test lifecycle-triggered behavior** by explicitly calling `loadViewIfNeeded()` (forces `viewDidLoad` without presenting the controller) in unit tests rather than trying to simulate a real presentation.

## 8. Performance

- **Never do layout work in `draw(_:)`.** `draw(_:)`/custom `NSView` drawing should only draw — no constraint changes, no subview additions. Layout belongs in `layoutSubviews()` (UIKit) / `layout()` (AppKit), and even there, avoid triggering another layout pass by reading geometry you just invalidated.
- **Avoid unnecessary offscreen rendering.** Rounded corners + `masksToLayer` + shadow together force offscreen rendering per layer; for lists/grids with many cells, this compounds. Pre-render rounded/shadowed images where possible, or use `shouldRasterize` deliberately (with a matched `rasterizationScale`) rather than accidentally paying the cost every scroll frame.
- **Image loading/caching:** decode and resize images off the main thread (`UIGraphicsImageRenderer`/`NSImage` work in a background task) before assigning to an image view, and cache decoded images (not just raw data) to avoid repeated decode cost on reuse. Cancel a cell's outstanding image task in `prepareForReuse()` (see section 3).
- **Batch UI updates.** Coalesce multiple state changes into a single `layoutIfNeeded()`/table-view update per run-loop tick rather than triggering layout on every individual property change.

## 9. Accessibility

- **Every meaningful control needs `isAccessibilityElement`, `accessibilityLabel`, and where relevant `accessibilityTraits`/`accessibilityValue`** — icon-only buttons and custom-drawn controls are invisible to VoiceOver without these.
- **`accessibilityIdentifier`** on interactive elements for UI test lookup (see [[apple-testing]]) — stable, localization-independent, unlike matching on visible text.
- **Group related elements** with a container's `accessibilityElements` array (UIKit) or `accessibilityChildren`/grouping (AppKit) when a compound view (e.g. a custom cell with icon + title + subtitle) should read as one VoiceOver stop instead of three.
- **Respect Dynamic Type** for any custom-drawn or manually-sized text — use `UIFontMetrics`/scalable text styles rather than fixed point sizes, and make sure Auto Layout constraints can grow to accommodate larger text instead of clipping.

## 10. Architecture patterns

- **"Massive View Controller" is the default failure mode of MVC in UIKit** — a view controller that owns networking, business logic, data source methods, and layout all in one file. The fix isn't necessarily a named architecture; it's consistently extracting non-UI logic out (see section 7) regardless of what you call the result.
- **MVVM** (view controller binds to an observable view model) works well when paired with Combine or closures for the binding — keep it pragmatic: a view model doesn't need to exist for a static screen with no state.
- **Coordinator pattern** (a separate object owns navigation/flow decisions, view controllers just request "go to X") is worth it once a flow spans more than 2-3 screens with branching, or multiple entry points need the same flow — don't introduce it for a single push.
- **Don't over-engineer a one-screen feature.** Match the architecture's ceremony to the screen's actual complexity; a settings screen with three static rows doesn't need the same scaffolding as a multi-step checkout flow.

## 11. Common pitfalls

- Strong `delegate` property instead of `weak` — retain cycle between component and owner.
- Missing `[weak self]` in an escaping closure held by a view controller — retain cycle, `deinit` never called.
- Forgetting `translatesAutoresizingMaskIntoConstraints = false` — programmatic constraints silently ignored.
- Manual `reloadData()`/index-based `insertRows`/`deleteRows` bookkeeping drifting from actual data — crash on row count mismatch.
- Not resetting/cancelling per-cell async state in `prepareForReuse()` — stale image/content flashes on scroll.
- Layout or subview mutation inside `draw(_:)`/`layoutSubviews()` triggering repeated layout passes.
- Business/networking logic living directly in the view controller — untestable, "Massive View Controller."
- Manually removing NotificationCenter/KVO observers forgotten — crash or leak when the removed object is later notified.

**For the failure mode, a ❌/✅ code example, and the fix for each pitfall, read `references/common-pitfalls.md`.**

## When reviewing existing code

Check for the pitfalls in section 11 above — read `references/common-pitfalls.md` for the exact patterns to grep for. Point out the specific line and the concrete failure mode (e.g. "this delegate is strong — retain cycle with the presenting view controller" or "this cell doesn't cancel its image task in prepareForReuse — will show the wrong image after fast scrolling") rather than generic style nitpicks. Flag view controllers accumulating networking/parsing/business logic directly rather than delegating to a testable view model/presenter (see [[apple-testing]]), and flag manual UIKit/AppKit state mutation from off the main thread (see [[concurrency-skill]]).
