# Common Swift testing pitfalls and how to avoid them

### Testing implementation details instead of behavior
```swift
// ❌ Wrong — breaks if internal call count changes, even if behavior is correct
@Test func loadCallsFetchOnce() async {
    let service = MockService()
    let sut = ItemsViewModel(service: service)
    await sut.load()
    #expect(service.fetchCallCount == 1) // brittle: coupled to implementation
}

// ✅ Right — asserts on the observable outcome
@Test func loadPopulatesItems() async {
    let service = MockService(itemsToReturn: [.fixture()])
    let sut = ItemsViewModel(service: service)
    await sut.load()
    #expect(sut.items.count == 1)
}
```
**Avoid:** assert on what the unit under test *produces or exposes*, not on how many times it called a collaborator, unless the call count itself is the contract being tested (e.g. verifying caching/de-duplication).

### Force-unwrapping in test code
```swift
// ❌ Wrong — crashes with an unhelpful trace if nil
@Test func parsesValidJSON() throws {
    let result = parse(json)!
    #expect(result.id == 1)
}

// ✅ Right — clear failure message pointing at the right line
@Test func parsesValidJSON() throws {
    let result = try #require(parse(json))
    #expect(result.id == 1)
}
```
**Avoid:** use `#require` (Swift Testing) or `try XCTUnwrap` (XCTest) anywhere you'd otherwise force-unwrap in a test — it fails the test with a clear message instead of crashing the whole run.

### `XCTestExpectation`/timeout waiting for async code
```swift
// ❌ Wrong — arbitrary timeout, slow and flaky under CI load
func testLoad() {
    let exp = expectation(description: "load")
    sut.load { result in
        XCTAssertEqual(result.count, 3)
        exp.fulfill()
    }
    wait(for: [exp], timeout: 2.0)
}

// ✅ Right — await the actual async call directly
@Test func load() async {
    let result = await sut.load()
    #expect(result.count == 3)
}
```
**Avoid:** once the code under test is `async`, test it with an `async` test function and plain `await` — don't wrap it back into expectation/timeout machinery.

### Shared mutable state between tests
```swift
// ❌ Wrong — tests pass/fail depending on execution order
final class CacheTests: XCTestCase {
    static var cache = Cache() // shared across all tests in the class

    func testInsert() { Self.cache.insert("a") ... }
    func testCount() { XCTAssertEqual(Self.cache.count, 0) } // fails if testInsert ran first
}

// ✅ Right — fresh instance per test
final class CacheTests: XCTestCase {
    func testInsert() {
        let cache = Cache()
        cache.insert("a")
        XCTAssertEqual(cache.count, 1)
    }
}
```
**Avoid:** never share mutable state (`static var`, singletons, shared temp files) across test cases — construct a fresh instance in each test, or reset shared state in `setUp()`/`init()`.

### Sleeping instead of awaiting the real work
```swift
// ❌ Wrong — arbitrary delay, flaky (too short) or slow (too long)
@Test func debouncedSearchFires() async throws {
    sut.search(query: "abc")
    try await Task.sleep(for: .seconds(1))
    #expect(sut.results.count > 0)
}

// ✅ Right — await the actual completion point
@Test func debouncedSearchFires() async throws {
    await sut.searchAndWaitForCompletion(query: "abc")
    #expect(sut.results.count > 0)
}
```
**Avoid:** if you find yourself reaching for `Task.sleep` to "give async work time to finish," the code under test needs an awaitable completion point (an `async` method, or an `AsyncStream` you can consume) instead — sleeping is never a reliable synchronization mechanism.

### Over-mocking simple dependencies
```swift
// ❌ Wrong — mocking a pure, fast, deterministic function for no reason
protocol PriceFormatting { func format(_ cents: Int) -> String }
// ...then a MockPriceFormatter in every test that touches pricing

// ✅ Right — just use the real formatter, it's pure and fast
let sut = CheckoutViewModel(formatter: PriceFormatter())
```
**Avoid:** only mock at real boundaries — network, disk, system clock, randomness. Pure, deterministic, fast collaborators (formatters, mappers, math) should be used for real in tests; mocking them adds indirection without reducing risk.

### Vague test names
```swift
// ❌ Wrong — tells you nothing when it fails in a CI log
func testLogin() { ... }

// ✅ Right — scenario and expected outcome are in the name
func testLoginFailsWithInvalidCredentials() { ... }
@Test func loginFailsWithInvalidCredentials() async { ... }
```
**Avoid:** name every test after the scenario and the expected outcome, so a failure is diagnosable from the test name alone in a CI log, without opening the file.
