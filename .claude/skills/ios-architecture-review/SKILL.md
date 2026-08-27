---
name: ios-architecture-review
description: Reviews and designs iOS app architecture (MVVM, MVC, VIPER, TCA, Clean Architecture, Coordinator pattern, Swift Package modularization). Use when the user asks to review app structure, choose an architecture pattern, plan modularization, decide between UIKit and SwiftUI for a feature, or refactor a large ViewController/View. Mention specific patterns like "MVVM", "VIPER", "Coordinator", "modularize", or "which architecture" as triggers.
disable-model-invocation: false
user-invocable: false
context: fork
---

# iOS Architecture Review

## Purpose

Help evaluate, choose, or refactor the architecture of an iOS codebase. Acts as a senior iOS architect: identify the current pattern, surface its weaknesses in context, and recommend a concrete path forward with trade-offs, not just theory.

## Step 1: Understand the current state

Before recommending anything, gather:

1. App size — rough number of screens/features, team size.
2. Current pattern in use (if any) — ask the user or infer from file structure (`*ViewModel.swift`, `*Presenter.swift`, `*Interactor.swift`, `*Reducer.swift` are strong signals).
3. UI framework mix — pure SwiftUI, pure UIKit, or hybrid.
4. Pain points — what prompted the review (slow builds, hard-to-test code, tangled navigation, merge conflicts, onboarding friction for new devs).

If the user hasn't stated these, ask directly rather than assuming. A recommendation for a 5-screen prototype and a 200-screen enterprise app are not the same.

## Step 2: Match the pattern to the context

Use this decision guide, not as dogma but as a starting point to discuss trade-offs:

| Context | Recommended starting point | Why |
|---|---|---|
| Small app / prototype, 1-2 devs | MVVM (SwiftUI native) | Least ceremony, SwiftUI's `@Observable`/`@State` already implies MVVM |
| Medium app, mixed UIKit/SwiftUI | MVVM + Coordinator | Coordinator extracts navigation out of ViewControllers/Views, keeps VMs UI-agnostic |
| Large app, many teams, need strict testability | VIPER or Clean Architecture (use case/interactor layer) | Enforces boundaries via protocols, easier to parallelize across teams, though more boilerplate |
| Need deterministic, testable state + time-travel debugging | The Composable Architecture (TCA) | Centralizes state and side effects, strong testing story, has a learning curve and dependency on the library |
| Legacy MVC codebase, incremental improvement only | Extract ViewModels first, defer full rewrite | Full rewrites rarely ship; strangler-fig migration screen by screen is lower risk |

Always explain **why**, not just **what**: e.g. "VIPER adds ceremony, but on a 15-person team touching the same module, the strict interface boundaries prevent silent coupling — that's worth the extra files."

## Step 3: Modularization guidance

When the app crosses roughly 20-30 screens or multiple feature teams start colliding in git:

1. Identify vertical feature boundaries first (e.g. `Onboarding`, `Checkout`, `Profile`) before horizontal layer boundaries (`Networking`, `DesignSystem`).
2. Propose a Swift Package layout:
   - `Core/` — shared models, networking, no UI.
   - `DesignSystem/` — shared UI components, colors, typography.
   - `Feature<X>/` — one package per feature, depends on Core + DesignSystem only, never on another Feature package directly.
   - `App/` — the composition root that wires features together (often via a Coordinator or a router protocol).
3. Flag any feature package that imports another feature package directly — this is the most common modularization violation and defeats the purpose (parallel builds, isolated testing).
4. Note build-time trade-offs: more modules can mean slower clean builds but much faster incremental builds and better parallelization in CI.

## Step 4: SwiftUI vs. UIKit decision

For a specific feature or screen, weigh:

- **Choose SwiftUI** when: the screen is new, state-driven, doesn't need deep custom scroll/gesture behavior, and the team is comfortable with the declarative model.
- **Choose UIKit** when: the screen needs fine-grained control (complex collection view layouts, precise animation timing, `UIViewController` lifecycle hooks that SwiftUI doesn't expose cleanly), or must match an existing UIKit navigation stack without a rewrite.
- **Hybrid is normal**, not a failure state. Most production apps interop via `UIHostingController` (SwiftUI inside UIKit) or `UIViewControllerRepresentable` (UIKit inside SwiftUI). See the `swiftui-uikit-bridge` skill for the mechanics.

## Step 5: Deliver the recommendation

Structure the output as:

1. **Current state summary** — one paragraph, plain assessment (no sugar-coating a genuinely tangled MVC).
2. **Recommended pattern** — with the specific reasoning tied to what the user told you in Step 1.
3. **Migration path** — concrete, incremental steps. Never recommend "rewrite everything." Suggest a strangler-fig approach: new features in the new pattern, old screens migrated opportunistically.
4. **Trade-offs acknowledged** — one honest paragraph on what gets harder with this choice (e.g. "VIPER means ~5 files per screen instead of 2; onboarding a new hire takes longer").

If useful, load `references/pattern-comparison.md` for a deeper side-by-side comparison table to share with the user or their team.

## Common mistakes to flag during review

- **God ViewModels**: a ViewModel that owns networking, persistence, business logic, and formatting all at once. Recommend splitting into a ViewModel + a Repository/UseCase layer.
- **Massive View Controller** in UIKit: business logic embedded directly in `viewDidLoad`/delegate callbacks. Recommend extracting to a ViewModel or Interactor even without a full pattern migration.
- **Singleton overuse** (`Manager.shared` everywhere): makes testing hard and hides dependencies. Recommend dependency injection via initializers or an environment/container.
- **Navigation logic inside Views/ViewControllers**: couples screens together and makes deep-linking hard. Recommend a Coordinator or Router.

## Example

**User says:** "We have 40 screens, 3 iOS devs, everything is MVC, and adding a feature always breaks another one."

**Actions:**
1. Ask about test coverage and how navigation currently works.
2. Recommend MVVM + Coordinator as the target pattern (not VIPER — team is small, VIPER's ceremony isn't justified yet).
3. Propose starting the migration with the most-changed screen (usually where the "breaks another feature" pain is worst).
4. Suggest introducing a `Core` Swift Package for shared networking/models as the first modularization step, since 40 screens in one target is already large enough to benefit from separate compilation units.

**Result:** A concrete, staged plan instead of "just rewrite it in SwiftUI," which the team could not realistically execute given 3 devs and a live app.
