# Common SwiftUI pitfalls and how to avoid them

### Inline `@ObservedObject`/`@StateObject` instantiation
Creating the object in the view's property initializer recreates it (and loses state) every time the parent re-renders.
```swift
// ❌ Wrong — recreated on every parent re-render
struct ProfileView: View {
    @ObservedObject var vm = ProfileViewModel()
}

// ✅ Right — created once, survives re-renders
struct ProfileView: View {
    @StateObject private var vm = ProfileViewModel()
}
// or, if a parent owns it and passes it down:
struct ProfileView: View {
    @ObservedObject var vm: ProfileViewModel // injected via init
}
```
**Avoid:** only use `@StateObject`/`@State` in the view that *creates* the object; every other view that receives it should take it as a plain injected property (`@ObservedObject`, or just `let`/`@Bindable` for `@Observable`).

### Unstable `ForEach`/`List` identity
Using the array index as `id` makes SwiftUI misattribute row state after insert/delete/reorder.
```swift
// ❌ Wrong — index changes when items are added/removed
ForEach(Array(items.enumerated()), id: \.offset) { _, item in
    RowView(item: item)
}

// ✅ Right — stable identity from the model
struct Item: Identifiable { let id: UUID; var title: String }
ForEach(items) { item in
    RowView(item: item)
}
```
**Avoid:** give every model a real, stable `id` (`Identifiable`) generated at creation time, never derived from position in the array.

### Business logic in `body`
```swift
// ❌ Wrong — sorts/filters on every render, hard to test
var body: some View {
    List(items.filter { $0.isActive }.sorted { $0.date > $1.date }) { ... }
}

// ✅ Right — computed once in the model/view model
var body: some View {
    List(vm.activeItemsSortedByDate) { ... }
}
```
**Avoid:** keep `body` declarative; push filtering/sorting/formatting into the view model as a computed property or method, so it's cacheable and unit-testable in isolation.

### `.onAppear` for async work
```swift
// ❌ Wrong — doesn't auto-cancel when the view disappears
.onAppear {
    Task { await vm.load() }
}

// ✅ Right — cancels automatically on disappear
.task {
    await vm.load()
}
// re-runs when `id` changes, cancelling the previous one:
.task(id: query) {
    await vm.search(query)
}
```
**Avoid:** never wrap `Task { }` inside `.onAppear` — use `.task`/`.task(id:)` so lifecycle and cancellation are handled for you.

### Overusing `AnyView`
```swift
// ❌ Wrong — erases type identity, breaks diffing/animations
var body: some View {
    if isLoading { AnyView(ProgressView()) } else { AnyView(ContentView()) }
}

// ✅ Right — @ViewBuilder preserves identity per branch
@ViewBuilder
var body: some View {
    if isLoading {
        ProgressView()
    } else {
        ContentView()
    }
}
```
**Avoid:** reach for `AnyView` only when genuinely mixing unrelated, dynamically-chosen view types (e.g. a plugin registry) — never as a default way to satisfy the type checker.

### `GeometryReader` misuse
```swift
// ❌ Wrong — forces this view to fill all available space just to read a size
GeometryReader { geo in
    Text("Hi").frame(width: geo.size.width * 0.5)
}

// ✅ Right — read size without hijacking layout, via a background + PreferenceKey,
// or just use relative sizing modifiers where available
Text("Hi")
    .frame(maxWidth: .infinity, alignment: .leading)
// or, iOS 17+:
Text("Hi").containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }
```
**Avoid:** don't wrap ordinary layout in `GeometryReader` just to get a width/height — it expands to fill its parent and can break surrounding padding/centering. Reserve it for cases that truly need the container's geometry, and scope it as tightly as possible (wrap just the one subview, not the whole screen).

### `NavigationView` instead of `NavigationStack`
```swift
// ❌ Wrong — deprecated, no typed programmatic navigation
NavigationView {
    List(items) { item in NavigationLink(item.title, destination: DetailView(item: item)) }
}

// ✅ Right
@State private var path = NavigationPath()
NavigationStack(path: $path) {
    List(items) { item in
        NavigationLink(item.title, value: item)
    }
    .navigationDestination(for: Item.self) { item in DetailView(item: item) }
}
```
**Avoid:** always start new screens with `NavigationStack`; only touch `NavigationView` when maintaining old code that can't yet raise its deployment target.

### `.sheet(isPresented:)` with data that can go stale
```swift
// ❌ Wrong — sheet can show stale `selectedItem` if it changes after isPresented flips
.sheet(isPresented: $showDetail) {
    DetailView(item: selectedItem)
}

// ✅ Right — sheet identity is tied directly to the data
.sheet(item: $selectedItem) { item in
    DetailView(item: item)
}
```
**Avoid:** whenever presented content depends on a specific value, drive presentation from that value's identity (`item:`), not a separate `Bool` flag.

### Monolithic views
Symptom: a single `body` mixing header, list, empty/error/loading states, and footer in one 200+ line block.
**Avoid:** extract each logical section into its own `View` struct (`HeaderView`, `ItemListView`, `EmptyStateView`...) as soon as `body` grows past ~30–40 lines or gains a new nesting level — this also gives each section independent re-render/diffing.

### Singletons instead of `@Environment`/DI
```swift
// ❌ Wrong — hardwires the view to a global, untestable/unpreviewable
struct SettingsView: View {
    var body: some View { Text(AuthManager.shared.userName) }
}

// ✅ Right — injected, mockable in previews and tests
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    var body: some View { Text(auth.userName) }
}
#Preview {
    SettingsView().environment(AuthManager.mock)
}
```
**Avoid:** reserve `.shared` singletons for true process-wide facilities with no per-instance state (e.g. `URLSession.shared`); inject everything else via `@Environment` or initializer parameters.

### Non-isolated `@Observable` mutated off the main actor
```swift
// ❌ Wrong — no actor isolation on the model; a background call into it
// races with the view reading the same properties on the main actor
@Observable
class FeedViewModel {
    var items: [Item] = []

    func refresh() async {
        let fresh = try? await api.fetchItems() // may resume off-main
        items = fresh ?? []                      // mutation isolation is unclear
    }
}

// ✅ Right — isolate the whole model to the main actor so every mutation
// and every view read happen on the same actor, with no manual hops
@MainActor
@Observable
class FeedViewModel {
    var items: [Item] = []

    func refresh() async {
        let fresh = try? await api.fetchItems()
        items = fresh ?? []
    }
}
```
**Avoid:** default view models that back a SwiftUI view to `@MainActor @Observable`. Under Swift 5's relaxed checking this mistake often compiles cleanly and only misbehaves at runtime (a dropped UI update, an occasional crash); under Swift 6 strict concurrency it's a compile error, which is the safer failure mode. See [[concurrency-skill]] for the underlying isolation rules.
