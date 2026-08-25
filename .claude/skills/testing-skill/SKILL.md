---
name: testing-skill
description: Write or review unit/UI tests for Swift and SwiftUI code (Swift Testing, XCTest, view models, async code, SwiftUI views). Use when adding tests for new code, improving test coverage, reviewing existing tests, or when the user asks for idiomatic Swift testing, or runs /testing-skill.
---

Apply these practices when writing or reviewing tests in Swift/iOS projects. Prefer the modern **Swift Testing** framework (`import Testing`, `@Test`, `#expect`/`#require`) for new unit tests on Swift 5.9+/Xcode 16+ targets. Use **XCTest** for UI tests (`XCUITest`) and when the project's existing test target is already XCTest-based — check the existing test files first and match the codebase's convention rather than mixing frameworks in the same target.

## 1. Framework choice

- **New unit tests, modern target:** Swift Testing (`@Test`, `#expect(...)`, `#require(...)`, `@Suite`). More expressive failure messages, parameterized tests, no `XCTestCase` subclassing boilerplate.
- **UI tests:** always XCTest (`XCUITest`) — Swift Testing does not replace `XCUIApplication`-based UI automation.
- **Existing XCTest suite:** keep new tests in XCTest for consistency unless the user asks to migrate; don't mix both frameworks in one file.
- **`async`/`await` tests:** both frameworks support `async` test functions directly — no need for `XCTestExpectation` wrappers around modern async code.

## 2. What to test

- **View models / `@Observable` models:** the primary unit-test target in a SwiftUI app — pure state transitions, computed properties, async loading logic. Test these directly; don't route through the view.
- **Pure functions:** formatters, validators, mappers, business logic extracted from views — highest test-value-per-line, no mocking needed.
- **Views themselves:** generally not unit-tested directly (SwiftUI view bodies aren't easily introspectable). Rely on `#Preview` for visual verification and `XCUITest` for behavior that spans the rendered UI (navigation, tap targets, accessibility).
- **Don't test the framework.** Don't write tests asserting that `@State` updates trigger a re-render, or that SwiftUI itself calls `body` — that's Apple's contract, not app logic.

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

- View models/services must take dependencies as **protocol-typed** initializer parameters, never reach for a singleton internally — this is what makes them testable at all. See [[swiftui-skill]] section on `@Environment`/DI for the same principle applied to views.
- Write lightweight hand-rolled mocks/stubs conforming to the same protocol as production code — avoid heavyweight mocking frameworks/macros unless the project already has one.
- Mock at the boundary (network client, persistence layer, clock/date provider), not internal implementation details — tests should survive refactors that don't change behavior.
- Inject a controllable clock/`Date` provider for time-dependent logic instead of calling `Date()` directly in production code.

## 5. Async & concurrency testing

- Prefer `async` test functions over expectation/timeout-based waiting whenever the code under test is itself `async`.
- For `AsyncSequence`/Combine streams, collect emitted values into an array within the test and assert on the full sequence rather than asserting on a single `.sink` callback.
- Use `#require` (Swift Testing) or `XCTUnwrap` (XCTest) to unwrap optionals with a clear failure instead of force-unwrapping (`!`) in test code.
- For code with `@MainActor` isolation, mark the test function `@MainActor` too rather than wrapping calls in `Task { @MainActor in ... }`.

## 6. Parameterized & edge-case coverage

- Use Swift Testing's `@Test(arguments:)` to cover multiple inputs in one test instead of copy-pasting near-identical test functions.
- Cover: the happy path, empty/nil input, boundary values (0, 1, max), and at least one error/failure path per unit under test.
- For collections/lists: test empty, single-item, and multi-item cases explicitly — off-by-one and empty-state bugs cluster here.

## 7. Test doubles for SwiftUI-specific patterns

- **`@Observable`/`ObservableObject` view models:** instantiate directly in the test, call methods, assert on published/observable properties — no view rendering needed.
- **Navigation:** if navigation is driven by a typed path/enum (see [[swiftui-skill]]), test that actions append/mutate the expected path value rather than trying to assert on rendered `NavigationStack` contents.
- **`.task`-driven loading:** trigger the same async method the `.task` calls, directly on the view model, rather than trying to simulate the view lifecycle in a unit test.

## 8. UI tests (XCUITest)

- Keep UI tests few and focused on critical user flows (login, checkout, primary navigation) — they're slow and flaky compared to unit tests; don't try to cover every screen state this way.
- Use accessibility identifiers (`.accessibilityIdentifier("loginButton")`) for element lookup, not visible text that may change with localization.
- Reset app state at the start of each UI test (launch arguments/environment to force a clean state) rather than relying on test execution order.

## 9. Naming & organization

- Test function names describe the scenario and expected outcome: `func loginFailsWithInvalidCredentials()`, not `func testLogin()`.
- Group related tests with `@Suite` (Swift Testing) or one `XCTestCase` subclass per unit under test (XCTest) — mirror the production source structure (`LoginViewModelTests.swift` for `LoginViewModel.swift`).
- One assertion focus per test; multiple `#expect` calls checking facets of the *same* outcome are fine, but don't test unrelated behaviors in one function.

## 10. Common pitfalls

- Testing implementation details (private state, call counts) instead of observable behavior — makes tests brittle to harmless refactors.
- Force-unwrapping (`!`) in test setup instead of `#require`/`XCTUnwrap` — crashes obscure the actual failure.
- Shared mutable state between tests (static vars, singletons) causing order-dependent flakiness — each test should set up its own isolated instance.
- Sleeping (`Task.sleep`) to "wait for" async work instead of `await`-ing the actual call or awaiting a proper async sequence.
- Over-mocking: mocking a pure function or simple data type that would be just as fast to call for real.

**For the failure mode, a ❌/✅ code example, and the fix for each pitfall, read `references/common-pitfalls.md`.**

## When reviewing existing tests

Check for: implementation-detail assertions, force-unwraps in test code, `XCTestExpectation`/timeout-based waiting where `async`/`await` would be simpler, missing edge-case coverage (empty/nil/boundary), tests coupled to singletons, and UI tests that could be unit tests instead. Point out the specific test and the concrete risk (e.g. "this will flake under CI load" or "this breaks on any internal refactor") rather than generic style nitpicks.
