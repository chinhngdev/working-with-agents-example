# iOS Architecture Pattern Comparison

Detailed reference for `ios-architecture-review`. Load this when the user wants a deeper comparison than the summary table in SKILL.md, or wants documentation to share with their team.

## MVC (Model-View-Controller, Apple's default)

- **Files per screen:** 2-3 (View/XIB, ViewController, Model).
- **Testability:** Poor — business logic tends to live in the ViewController, which is hard to instantiate and test in isolation.
- **Best for:** Very small apps, prototypes, single-developer throwaway projects.
- **Common failure mode:** "Massive View Controller" — a single file accumulates networking, formatting, and navigation logic.

## MVVM (Model-View-ViewModel)

- **Files per screen:** 3 (View, ViewModel, Model).
- **Testability:** Good — ViewModel is a plain object (or `@Observable` class) that can be unit tested without instantiating UI.
- **Best for:** Most SwiftUI apps by default, and UIKit apps that want better testability without heavy ceremony.
- **Common failure mode:** "God ViewModel" that absorbs everything the View doesn't do — mitigate by extracting Repository/UseCase layers for business logic.
- **SwiftUI fit:** Very natural — `@Observable` ViewModel + SwiftUI View is close to the framework's own mental model.

## MVVM + Coordinator

- **Adds:** A Coordinator object owns navigation (push/pop/present), so Views and ViewModels never reference `UINavigationController` or other screens directly.
- **Best for:** Apps with non-trivial navigation flows, deep linking, or multiple entry points into the same screen.
- **Trade-off:** One more object per flow to maintain, but navigation becomes testable and reusable.

## VIPER (View-Interactor-Presenter-Entity-Router)

- **Files per screen:** 5+ (View, Interactor, Presenter, Entity, Router).
- **Testability:** Excellent — every layer is a protocol, easy to mock.
- **Best for:** Large teams, long-lived apps, strict separation of concerns required (e.g. regulated industries, large enterprise apps).
- **Trade-off:** Significant boilerplate; slower to onboard new developers; often needs code generation templates to stay sane at scale.

## Clean Architecture (Use Case / Interactor layer)

- **Files per screen:** Varies — typically View + ViewModel + UseCase(s) + Repository protocol.
- **Testability:** Excellent, similar to VIPER but less rigid about the exact layer names.
- **Best for:** Teams that want VIPER-level testability without VIPER's prescriptive structure. Business logic lives in UseCase objects independent of any UI framework.
- **Trade-off:** Requires discipline — without a formal template, "Clean Architecture" can drift into whatever the last person who touched the file preferred.

## The Composable Architecture (TCA)

- **Files per screen:** Reducer + State + Action (often one file, can be split).
- **Testability:** Best-in-class — deterministic state transitions, exhaustive testing of every action, time-travel debugging.
- **Best for:** Teams willing to invest in the learning curve, apps where state consistency and testability are critical (e.g. finance, complex multi-step flows).
- **Trade-off:** Steep learning curve, adds a third-party dependency (or Apple's own Swift structured concurrency wrapping), can feel heavyweight for simple screens.

## Decision heuristic

1. **1-2 devs, <20 screens:** MVVM, plain and simple. Don't over-engineer.
2. **3-8 devs, 20-60 screens, navigation is getting messy:** MVVM + Coordinator.
3. **8+ devs, 60+ screens, multiple feature teams:** VIPER or Clean Architecture, paired with Swift Package modularization.
4. **State correctness is mission-critical and team is willing to invest:** TCA, regardless of size.

## Modularization file layout reference

```
MyApp.xcworkspace
├── App/                        # Composition root, thin
├── Packages/
│   ├── Core/                   # Networking, persistence, shared models — no UI
│   ├── DesignSystem/           # Colors, typography, shared components
│   ├── FeatureOnboarding/      # Depends only on Core + DesignSystem
│   ├── FeatureCheckout/        # Depends only on Core + DesignSystem
│   └── FeatureProfile/         # Depends only on Core + DesignSystem
```

Rule: a `Feature*` package must never import another `Feature*` package. If two features need to share logic, extract that logic into `Core` or a new shared package.
