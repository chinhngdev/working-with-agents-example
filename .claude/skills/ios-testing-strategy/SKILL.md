---
name: ios-testing-strategy
description: Designs testing strategy for iOS apps covering XCTest unit tests, ViewModel testing, XCUITest UI automation, snapshot testing, and mocking network layers. Use when the user asks how to test a ViewModel, write a UI test, set up snapshot testing, mock a network call, improve test coverage, or plan a test strategy for an iOS feature.
---

# iOS Testing Strategy

## Purpose

Help plan and implement a test strategy for iOS features — choosing the right test type for the right layer, writing testable code, and setting up mocking/snapshot infrastructure. Not every layer needs the same kind of test; picking the wrong one wastes effort and still misses bugs.

## Step 1: Map the testing pyramid to iOS layers

| Layer | Test type | Tooling | Speed |
|---|---|---|---|
| Business logic, ViewModels, UseCases | Unit tests | XCTest | Fast (ms) |
| Networking/data layer | Unit tests with mocked responses | XCTest + `URLProtocol` stub or a mock client | Fast |
| Visual regression of a single screen/component | Snapshot tests | `swift-snapshot-testing` or similar | Fast-medium |
| Full user flows across screens | UI tests | XCUITest | Slow (seconds-minutes) |

Recommend the heaviest weight at the bottom (unit tests, cheap and numerous) and the lightest weight at the top (UI tests, few and targeted at critical flows only — checkout, login, onboarding). A common anti-pattern is an app with dozens of slow XCUITest flows and almost no unit tests; flag this if you see it and suggest inverting the ratio.

## Step 2: Making ViewModels testable

Testability starts with how the code is written, not just how it's tested. Before writing tests, check:

- **Dependencies are injected**, not hardcoded singletons. A ViewModel that calls `NetworkManager.shared.fetch(...)` directly cannot be tested without a real network call. It should take a protocol-typed dependency in its initializer:
  ```swift
  protocol UserFetching {
      func fetchUser(id: String) async throws -> User
  }

  @Observable
  final class ProfileViewModel {
      private let userFetcher: UserFetching
      var user: User?
      var errorMessage: String?

      init(userFetcher: UserFetching) {
          self.userFetcher = userFetcher
      }

      func load(id: String) async {
          do {
              user = try await userFetcher.fetchUser(id: id)
          } catch {
              errorMessage = "Could not load profile."
          }
      }
  }
  ```
- If the existing ViewModel uses a singleton, recommend introducing a protocol and injecting it — this is usually a small, low-risk refactor that unlocks testing.

## Step 3: Writing the unit test

```swift
final class ProfileViewModelTests: XCTestCase {
    func test_load_success_setsUser() async {
        let mockFetcher = MockUserFetcher(result: .success(User(id: "1", name: "Ada")))
        let viewModel = ProfileViewModel(userFetcher: mockFetcher)

        await viewModel.load(id: "1")

        XCTAssertEqual(viewModel.user?.name, "Ada")
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_load_failure_setsErrorMessage() async {
        let mockFetcher = MockUserFetcher(result: .failure(URLError(.notConnectedToInternet)))
        let viewModel = ProfileViewModel(userFetcher: mockFetcher)

        await viewModel.load(id: "1")

        XCTAssertNil(viewModel.user)
        XCTAssertEqual(viewModel.errorMessage, "Could not load profile.")
    }
}
```

Test both the happy path and the failure path for every ViewModel method that can fail — a ViewModel test suite that only covers success cases misses exactly the scenarios most likely to reach production as bugs.

## Step 4: Mocking the network layer

For code still using `URLSession` directly rather than an injected protocol, use `URLProtocol` stubbing:

```swift
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("Set MockURLProtocol.requestHandler before use")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

Configure a `URLSession` with `MockURLProtocol` in its `URLSessionConfiguration.protocolClasses` for tests. Prefer this over hitting real network endpoints in unit tests — real network calls make tests slow, flaky, and dependent on external services being up.

For a codebase already using an injected protocol (per Step 2), a plain mock/stub struct implementing that protocol is simpler than `URLProtocol` stubbing — recommend whichever matches the existing dependency injection style.

## Step 5: Snapshot testing

Use snapshot testing for visual regression on SwiftUI views or UIKit screens where pixel-level correctness matters (design system components, complex layouts):

```swift
import SnapshotTesting

final class ProfileViewSnapshotTests: XCTestCase {
    func test_profileView_withData() {
        let view = ProfileView(viewModel: .preview(withUser: true))
        assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))
    }

    func test_profileView_emptyState() {
        let view = ProfileView(viewModel: .preview(withUser: false))
        assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))
    }
}
```

Points to flag:

- Snapshot tests are sensitive to the exact simulator/OS version used to record the reference image — recommend pinning CI to a specific simulator runtime, or snapshot mismatches will be constant false positives across different machines.
- Snapshot tests catch *that* something changed, not *whether* the change is correct — a genuine visual redesign requires re-recording snapshots (usually a `record: true` flag or deleting and regenerating references), which is expected, not a failure to fix.

## Step 6: UI tests (XCUITest)

Reserve these for critical end-to-end flows only, since they're slow and comparatively brittle:

```swift
final class LoginFlowUITests: XCTestCase {
    func test_successfulLogin_navigatesToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]  // trigger a test-mode config in the app, e.g. mock backend
        app.launch()

        app.textFields["emailField"].tap()
        app.textFields["emailField"].typeText("user@example.com")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("password123")
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.staticTexts["welcomeMessage"].waitForExistence(timeout: 5))
    }
}
```

Points to flag:

- **Use accessibility identifiers** (`.accessibilityIdentifier("emailField")` in the view code), not text-based lookups, for elements a UI test targets — text can change with localization or copy edits and silently break tests that rely on matching label text.
- **Never hit a real backend in UI tests.** Use a launch argument/environment variable to switch the app into a test mode backed by a mock server or fixture data, or the test suite will be flaky and slow.
- **Add explicit waits** (`waitForExistence(timeout:)`) rather than fixed `sleep()` calls — fixed sleeps make the suite slower than necessary and still flaky under load.

## Deciding what to test for a given feature

When the user describes a new feature and asks "how should I test this":

1. Identify the ViewModel/UseCase layer — always unit test this, happy path + failure paths + edge cases (empty data, nil, boundary values).
2. Identify whether the screen has significant custom visual layout — if yes, add a snapshot test for at least the default and empty/error states.
3. Ask whether this feature is on a critical path (payment, login, core action of the app) — if yes, add one XCUITest covering the full happy-path flow. If it's a minor feature, skip UI tests and rely on unit + snapshot coverage.

## Common issues

### Flaky UI tests
**Cause:** Fixed sleeps, race conditions with animations, or hitting a real (variable-latency) backend.
**Fix:** Use `waitForExistence`, disable animations in UI test mode (`UIView.setAnimationsEnabled(false)` behind a launch argument), and mock the backend.

### Async test hangs / times out
**Cause:** An `await` inside the test never completes because the mock never resolves, or a continuation is never resumed (see `swift-concurrency-migration` skill).
**Fix:** Verify the mock actually returns/throws on every path the test exercises.

### Snapshot tests fail only in CI, pass locally
**Cause:** Different simulator OS version or hardware rendering differences (font hinting, GPU) between local machine and CI runner.
**Fix:** Pin the exact simulator device and OS version in CI configuration to match the machine that recorded the reference snapshots.
