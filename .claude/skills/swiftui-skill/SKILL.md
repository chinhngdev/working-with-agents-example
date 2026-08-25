---
name: swiftui-skill
description: Write, review, or refactor SwiftUI code (views, state management, navigation, data flow, performance, testing) following modern Apple-recommended best practices. Use when creating new SwiftUI views/features, reviewing existing SwiftUI code, or when the user asks for idiomatic/clean SwiftUI, or runs /swiftui-skill.
---

Apply these best practices when writing or reviewing SwiftUI code. Prefer the modern Observation-based approach (iOS 17+/Swift 5.9+) unless the project's deployment target requires `ObservableObject`/Combine — check the Xcode project's deployment target or existing code style first, and match whatever the codebase already uses rather than mixing paradigms.

## 1. State management

- **Own state at the right level.** Use `@State` only for view-local, transient state (toggles, text field input, animation flags). Never make `@State` hold shared/business data.
- **Modern observation (iOS 17+).** Use `@Observable` (from `Observation`) on plain classes for view models/data models instead of `ObservableObject` + `@Published`. In the view, hold it with `@State` (if the view owns/creates it) or plain `let`/property (if injected), not `@ObservedObject`.
- **Legacy target (pre-iOS 17).** Use `ObservableObject` classes with `@Published` properties, referenced via `@StateObject` (view owns/creates it — created once) vs `@ObservedObject` (injected from a parent — never instantiate directly in a view's property initializer, which recreates it on every parent re-render).
- **Shared/app-wide state.** Use `@Environment` (custom `@Observable` types or `EnvironmentKey`) instead of singletons threaded through initializers. Avoid global mutable singletons for testability.
- **Bindings.** Use `@Binding` for two-way child-to-parent communication. Don't pass a whole observable object down just to mutate one field — pass a `Binding` to that field, or a closure callback for one-shot events.
- **Avoid over-observing.** Don't put every piece of state in one giant `@Observable`/`ObservableObject` — split by feature/screen so unrelated views don't re-render on unrelated changes.

## 2. View structure

- **Small, single-purpose views.** Extract subviews into their own `View` structs (not just computed properties) when a body grows past ~30–40 lines or nests more than 2–3 levels of logic. Separate structs get their own diffing/identity and re-render independently — computed `var` properties don't.
- **No business logic in `body`.** Views should describe UI declaratively. Move formatting, calculations, and decisions into the view model or small pure helper functions/extensions.
- **Composition over configuration.** Prefer small composable views and view modifiers over one view with many boolean/enum flags controlling its rendering.
- **Custom `ViewModifier` / extensions** for repeated styling (e.g. `.cardStyle()`) instead of copy-pasting modifier chains.
- **Avoid `AnyView`.** It erases type identity and hurts diffing/performance. Use `@ViewBuilder`, generics, or `some View` instead. Use `@ViewBuilder` for conditional view composition in initializers/functions.

## 3. Identity & lists

- Every `ForEach`/`List` item needs a **stable, unique `id`** (prefer `Identifiable` conforming models with a real ID, not array index) — index-based IDs cause state to leak between rows on insert/delete/reorder.
- Use `List` or `LazyVStack`/`LazyHStack` inside `ScrollView` for long/dynamic collections; a plain `VStack` in a `ScrollView` eagerly renders all children.

## 4. Navigation

- Use `NavigationStack` with a typed navigation path (`NavigationPath` or `[Route]` enum) for programmatic/deep-linkable navigation — avoid the deprecated `NavigationView`.
- Drive navigation from state (`navigationDestination(for:)`, `.sheet(item:)`, `.fullScreenCover(item:)`) rather than imperative pushes, so navigation state is testable and restorable.
- Prefer `.sheet(item:)`/`.fullScreenCover(item:)` (identity-driven) over `.sheet(isPresented:)` when the presented content depends on a specific data value — avoids stale-data bugs.

## 5. Data flow & side effects

- **Async work:** use `.task { }` (auto-cancels when the view disappears) instead of `.onAppear { Task { ... } }`. Use `.task(id:)` when the work should restart when a dependency changes.
- Keep networking/persistence out of views — call into a service/repository from the view model, inject dependencies (protocol-typed) so they're mockable in tests/previews.
- Use `async/await` over completion-handler closures for new code.
- Debounce/cancel in-flight work on rapid input changes (e.g. search-as-you-type) using `.task(id:)` cancellation rather than manual `Task` bookkeeping.

## 6. Performance

- Keep `body` cheap — no heavy computation, sorting, or filtering inline; compute once and cache, or do it in the model layer.
- Use `.equatable()` / `Equatable` conformance or split into subviews to prevent unnecessary re-renders of expensive children.
- Avoid unnecessary `GeometryReader` — it forces the child to fill all available space and can cause layout thrashing; prefer `.frame`, alignment guides, or the newer `containerRelativeFrame`/layout protocols where possible.
- Use `drawingGroup()` only for genuinely complex Core Animation-heavy views (offscreen rendering has a cost of its own).

## 7. Previews & testability

- Add `#Preview` blocks for every non-trivial view, including relevant states (empty, loading, error, populated) using mock data/dependencies.
- Design view models around protocols/dependency injection so they can be previewed and unit-tested without hitting real network/disk.
- Prefer pure functions for formatting/derived values so they're independently testable.

## 8. Accessibility & polish

- Provide `.accessibilityLabel`/`.accessibilityHint`/`.accessibilityValue` for icon-only controls and custom components.
- Group related elements with `.accessibilityElement(children:)` where it improves VoiceOver flow.
- Support Dynamic Type — avoid fixed pixel font sizes for body text; use `.font(.body)`/semantic text styles or `@ScaledMetric` for custom sizing.
- Respect Dark Mode via semantic/asset colors, not hardcoded RGB.

## 9. Code style

- Use `some View` return types, not concrete types, for view-building functions.
- Prefer `let` over `var` wherever the value doesn't change.
- Keep access control explicit at module boundaries (`private`/`fileprivate` for implementation details).
- Group modifiers logically and keep chains readable — break long modifier chains across lines.

## 10. Common pitfalls

The most frequent SwiftUI mistakes, in short:

- Inline `@ObservedObject`/`@StateObject` instantiation (recreated on every parent re-render)
- Unstable `ForEach`/`List` identity (index-based `id`)
- Business logic inside `body` instead of the view model
- `.onAppear { Task { ... } }` instead of `.task`
- Overusing `AnyView`
- `GeometryReader` misuse (hijacks parent layout)
- `NavigationView` instead of `NavigationStack`
- `.sheet(isPresented:)` with data that can go stale (use `.sheet(item:)`)
- Monolithic views that should be decomposed
- Singletons instead of `@Environment`/DI

**For the failure mode, a ❌/✅ code example, and the fix for each one, read `references/common-pitfalls.md`.**

## When reviewing existing code

Check for the pitfalls in section 10 above — read `references/common-pitfalls.md` for the exact patterns to grep for. Point out the specific line and the concrete failure mode (e.g. "state will reset on parent re-render") rather than generic style nitpicks.
