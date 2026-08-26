---
name: apple-testing
description: Write or review unit/UI tests for Apple platform apps (macOS, iOS, iPadOS, watchOS, tvOS, visionOS) in Swift — Swift Testing, XCTest, view models, SwiftUI views, UIKit/AppKit components, async code, XCUITest. Use when adding tests for new code, improving test coverage, reviewing existing tests, or when the user asks for idiomatic Swift testing, or runs /apple-testing.
---

Apply these practices when writing or reviewing tests for Apple platform apps. Prefer the modern **Swift Testing** framework (`import Testing`, `@Test`, `#expect`/`#require`) for new unit tests on Swift 5.9+/Xcode 16+ targets. Use **XCTest** for UI tests (`XCUITest`) and when the project's existing test target is already XCTest-based — check the existing test files first and match the codebase's convention rather than mixing frameworks in the same target. These practices apply across macOS, iOS, iPadOS, watchOS, tvOS, and visionOS — platform differences are called out where they matter.

## 1. Framework choice

- **New unit tests, modern target:** Swift Testing (`@Test`, `#expect(...)`, `#require(...)`, `@Suite`). More expressive failure messages, parameterized tests, no `XCTestCase` subclassing boilerplate.
- **UI tests:** always XCTest (`XCUITest`) — Swift Testing does not replace `XCUIApplication`-based UI automation, on any platform.
- **Existing XCTest suite:** keep new tests in XCTest for consistency unless the user asks to migrate; don't mix both frameworks in one file.
- **`async`/`await` tests:** both frameworks support `async` test functions directly — no need for `XCTestExpectation` wrappers around modern async code.
- **watchOS/tvOS targets:** Swift Testing and XCTest both work, but watchOS test bundles run against the paired simulator/device and are slower to launch — keep the unit-test/UI-test ratio even more heavily weighted toward unit tests than on iOS.

## 2. What to test

- **View models / `@Observable` models:** the primary unit-test target in a SwiftUI app — pure state transitions, computed properties, async loading logic. Test these directly; don't route through the view. See [[swiftui-skill]].
- **UIKit/AppKit view controllers and views:** test the controller's *logic*, not its rendering. Instantiate the controller (`loadViewIfNeeded()` on iOS/tvOS to force `viewDidLoad` without a window; on AppKit, access `.view` once to trigger `viewDidLoad`), then assert on outlet state, exposed properties, or delegate callbacks — not on rendered pixels. Extract business logic into a plain, DI-friendly type the controller merely calls, and unit-test that type directly wherever possible, same as with a SwiftUI view model. See [[uikit-skill]].
- **Pure functions:** formatters, validators, mappers, business logic extracted from views/controllers — highest test-value-per-line, no mocking needed.
- **Views themselves:** generally not unit-tested directly (SwiftUI view bodies aren't introspectable; UIKit/AppKit view layout is expensive and brittle to test directly). Rely on `#Preview`/Interface Builder previews for visual verification, snapshot tests for regression-catching on rendered output, and `XCUITest` for behavior that spans the rendered UI (navigation, tap targets, accessibility).
- **Platform-conditional code (`#if os(...)`):** test each compiled variant on its own platform test target — code inside an `#if os(watchOS)` block is only exercised by a test plan that actually runs on a watchOS destination.
- **Don't test the framework.** Don't write tests asserting that `@State` updates trigger a re-render, that SwiftUI itself calls `body`, or that UIKit calls `viewDidLoad` — that's Apple's contract, not app logic.

## 3. Structure — Arrange/Act/Assert

Keep every test in three clear parts: set up inputs and dependencies, perform the one action under test, assert the outcome. One logical behavior per test — split "and" in a test name into two tests.

```swift
@Test func loginFailsWithInvalidCredentials() async throws {
    // Arrange
    let sut = LoginViewModel(authService: MockAuthService(shouldSucceed: false))

    // Act
    await sut.login(email: "a@b.com", password: "wrong")

    // Assert
    #expect(sut.errorMessage == "Invalid credentials")
}
```

## 4. Dependency injection & mocking

- View models/services/controllers must take dependencies as **protocol-typed** initializer parameters, never reach for a singleton internally — this is what makes them testable at all. See [[swiftui-skill]] section on `@Environment`/DI, and the equivalent DI-via-initializer pattern for UIKit/AppKit in [[uikit-skill]].
- Write lightweight hand-rolled mocks/stubs conforming to the same protocol as production code — avoid heavyweight mocking frameworks/macros unless the project already has one.
- Mock at the boundary (network client, persistence layer, clock/date provider, `WCSession`/HealthKit/other platform frameworks), not internal implementation details — tests should survive refactors that don't change behavior.
- Inject a controllable clock/`Date` provider for time-dependent logic instead of calling `Date()` directly in production code.
- For platform-specific singletons that resist DI (`UIApplication.shared`, `WKExtension.shared`, `NSApplication.shared`), wrap the specific calls you need behind a small protocol the app owns, and inject that instead of the framework singleton directly.

## 5. Async & concurrency testing

- Prefer `async` test functions over expectation/timeout-based waiting whenever the code under test is itself `async`. See [[concurrency-skill]] for the underlying async/actor patterns being tested.
- For `AsyncSequence`/Combine streams, collect emitted values into an array within the test and assert on the full sequence rather than asserting on a single `.sink` callback.
- Use `#require` (Swift Testing) or `XCTUnwrap` (XCTest) to unwrap optionals with a clear failure instead of force-unwrapping (`!`) in test code.
- For code with `@MainActor` isolation, mark the test function `@MainActor` too rather than wrapping calls in `Task { @MainActor in ... }`.
- When testing an `actor`, call its methods with plain `await` from the test function — no special handling needed beyond normal async test structure.

## 6. Parameterized & edge-case coverage

- Use Swift Testing's `@Test(arguments:)` to cover multiple inputs in one test instead of copy-pasting near-identical test functions.
- Cover: the happy path, empty/nil input, boundary values (0, 1, max), and at least one error/failure path per unit under test.
- For collections/lists: test empty, single-item, and multi-item cases explicitly — off-by-one and empty-state bugs cluster here.

```swift
@Test(arguments: [
    ("", false),
    ("a@b.com", true),
    ("not-an-email", false),
])
func emailValidation(input: String, expected: Bool) {
    #expect(EmailValidator.isValid(input) == expected)
}
```

## 7. Test doubles for SwiftUI-specific patterns

- **`@Observable`/`ObservableObject` view models:** instantiate directly in the test, call methods, assert on published/observable properties — no view rendering needed.
- **Navigation:** if navigation is driven by a typed path/enum (see [[swiftui-skill]]), test that actions append/mutate the expected path value rather than trying to assert on rendered `NavigationStack` contents.
- **`.task`-driven loading:** trigger the same async method the `.task` calls, directly on the view model, rather than trying to simulate the view lifecycle in a unit test.

## 8. Test doubles for UIKit/AppKit patterns

- **Delegate/data source callbacks:** test the delegate-conforming type directly by calling its delegate methods with fixture inputs, rather than driving a real table/collection view — e.g. call `tableView(_:didSelectRowAt:)` on the controller directly and assert on the resulting state.
- **Target-action:** call the `@objc` action method directly (`sut.saveButtonTapped(sender)`), not by simulating a tap through the responder chain.
- **`loadViewIfNeeded()` (iOS/tvOS) / triggering `viewDidLoad` (AppKit):** force lifecycle methods to run before asserting on outlet-wired state, without needing a real window or presenting the controller.
- **Storyboard/XIB-instantiated controllers:** instantiate via `UIStoryboard(name:bundle:).instantiateViewController(identifier:)` (or the NSStoryboard/NSNib equivalent) in tests that must exercise the real IB wiring; prefer programmatic init + injected dependencies for everything else so tests don't need a storyboard at all.

## 9. Snapshot testing

- Use snapshot testing (e.g. `swift-snapshot-testing` or an equivalent) to catch unintended visual regressions in views/cells that are expensive to describe with plain assertions — layout, complex custom drawing, `UICollectionViewCell`/`NSTableCellView` configurations.
- Record snapshots on a fixed simulator/OS version and pin it in CI — fonts and rendering can shift subtly across OS versions, causing false failures unrelated to the code change.
- Snapshot tests are a complement to, not a replacement for, behavior unit tests — a snapshot catches "this looks different," not "this is correct"; still assert on view-model/controller state directly for logic correctness.
- Keep snapshot test count proportional to visual complexity — don't snapshot every trivial view; reserve it for views with real layout/rendering risk.

## 10. UI tests (XCUITest)

- Keep UI tests few and focused on critical user flows (login, checkout, primary navigation) — they're slow and flaky compared to unit tests; don't try to cover every screen state this way.
- Use accessibility identifiers (`.accessibilityIdentifier("loginButton")`) for element lookup, not visible text that may change with localization — this applies equally to SwiftUI, UIKit, and AppKit elements.
- Reset app state at the start of each UI test (launch arguments/environment to force a clean state) rather than relying on test execution order.
- **Platform differences:** `XCUIApplication` drives iOS/iPadOS/tvOS/macOS apps; watchOS UI testing runs through the paired iPhone's Watch app context and is materially slower and flakier — keep watchOS UI test coverage minimal and favor unit-testing the watch app's view models instead.
- On tvOS, interact via focus-engine navigation (`XCUIRemote.shared.press(.right)` etc.), not taps — tvOS has no touch surface on the actual device.

## 11. Multi-platform test organization

- **Shared logic, separate UI:** for apps targeting multiple Apple platforms from one codebase, put platform-agnostic logic (models, view models, networking, persistence) in a shared framework/package target with one shared test target — don't duplicate the same view-model tests per platform.
- **Xcode Test Plans:** use a `.xctestplan` per platform (or per configuration) when a multi-platform app needs different test target combinations, environment variables, or code coverage settings per destination — avoids hand-picking schemes/targets on every run.
- **Swift Package Manager targets:** when logic lives in an SPM package (see how [[swiftui-skill]] and [[uikit-skill]] recommend structuring shared UI code), give it its own test target (`Tests/<ModuleName>Tests`) that runs via `swift test` independent of any Xcode project — this is usually the fastest test loop and should run in CI without needing a simulator at all for pure-logic packages.
- **Platform-specific test targets:** UI tests and any test that touches `UIKit`/`AppKit`/`WatchKit`/platform frameworks directly must live in a platform-specific test target with the matching destination — they cannot run in a cross-platform SPM `swift test` invocation.

## 12. Naming & organization

- Test function names describe the scenario and expected outcome: `func loginFailsWithInvalidCredentials()`, not `func testLogin()`.
- Group related tests with `@Suite` (Swift Testing) or one `XCTestCase` subclass per unit under test (XCTest) — mirror the production source structure (`LoginViewModelTests.swift` for `LoginViewModel.swift`).
- One assertion focus per test; multiple `#expect` calls checking facets of the *same* outcome are fine, but don't test unrelated behaviors in one function.

## 13. Common pitfalls

- Testing implementation details (private state, call counts) instead of observable behavior — makes tests brittle to harmless refactors.
- Force-unwrapping (`!`) in test setup instead of `#require`/`XCTUnwrap` — crashes obscure the actual failure.
- Shared mutable state between tests (static vars, singletons) causing order-dependent flakiness — each test should set up its own isolated instance.
- Sleeping (`Task.sleep`) to "wait for" async work instead of `await`-ing the actual call or awaiting a proper async sequence.
- Over-mocking: mocking a pure function or simple data type that would be just as fast to call for real.
- Unit-testing through a real `UIViewController`/`NSViewController` lifecycle and window when the logic under test doesn't need a rendered view at all.
- Snapshot tests recorded on one OS/simulator version and run against another, causing false failures from font/rendering drift.

**For the failure mode, a ❌/✅ code example, and the fix for each pitfall, read `references/common-pitfalls.md`.**

## When reviewing existing tests

Check for: implementation-detail assertions, force-unwraps in test code, `XCTestExpectation`/timeout-based waiting where `async`/`await` would be simpler, missing edge-case coverage (empty/nil/boundary), tests coupled to singletons, UI tests that could be unit tests instead, view-controller tests that instantiate a full window/lifecycle when a plain-object test would do, and snapshot tests with no pinned OS/simulator version. See [[code-reviewer-skill]] for the general review posture this pairs with. Point out the specific test and the concrete risk (e.g. "this will flake under CI load" or "this breaks on any internal refactor") rather than generic style nitpicks.
