---
name: ios-documentation
description: Writes iOS-specific technical documentation including DocC comments, Swift Package README files, and architecture decision records for migrations like UIKit to SwiftUI. Use when the user asks to document Swift code, write DocC comments, create a README for a Swift Package, write an ADR for an architecture change, or improve code documentation coverage.
---

# iOS Documentation

## Purpose

Produce iOS-specific technical documentation: inline DocC comments for Swift APIs, README files for Swift Packages, and architecture decision records (ADRs) for significant iOS architecture changes (e.g. a UIKit-to-SwiftUI migration, adopting a new concurrency model, modularization). This complements general documentation practices with the conventions specific to Swift/Xcode tooling.

## Step 1: DocC comments for Swift APIs

Use Swift's documentation comment syntax (`///` or `/** */`), which DocC (Xcode's documentation compiler) renders into Quick Help and generated documentation catalogs.

```swift
/// Fetches the profile for a given user identifier.
///
/// This method hits the network on every call and does not cache results;
/// callers that need caching should wrap this at a higher layer.
///
/// - Parameter id: The unique identifier of the user to fetch.
/// - Returns: The fully populated `User` model.
/// - Throws: `NetworkError.notFound` if no user exists with the given id,
///   or any error surfaced by the underlying `URLSession` call.
func fetchUser(id: String) async throws -> User
```

Rules to apply:

- **Document the "why" and constraints, not just a restatement of the signature.** "Fetches the profile for a given user identifier" alone is barely more useful than the function name; the caching/no-caching note is the part a caller actually needs.
- **Every `throws` function should document what it throws and under what conditions**, at least at the category level (`NetworkError.notFound`), not just "Throws: an error."
- **Use `- Parameter`/`- Returns`/`- Throws` fields** for anything with parameters or a return value — DocC renders these into a structured Quick Help popover, which plain prose doesn't.
- **Add a `# Topics` or `## Overview` section** (using Markdown headers inside the doc comment, or a dedicated `.md` documentation file referenced via a DocC catalog) when documenting a type with many related methods, to group them logically rather than leaving readers to scroll through an alphabetical list.
- **Don't document the obvious.** A trivial computed property like `var isEmpty: Bool { items.isEmpty }` doesn't need a doc comment explaining that it returns whether the collection is empty — reserve doc comments for anything with real behavior, side effects, or non-obvious constraints.

## Step 2: DocC documentation catalogs (for a full framework/package)

For a Swift Package or framework meant to be consumed by other developers (internal or public), recommend a `.docc` catalog for a browsable reference:

```
MyFramework.docc/
├── MyFramework.md          # Landing page: overview, getting started
├── Articles/
│   └── MigratingFromV1.md  # Conceptual guides, migration notes
└── Extensions/
    └── UserFetching.md     # Extended docs for a specific type, beyond inline comments
```

Point out that this is worth the setup cost when the package has external consumers (other teams, or an open-source audience) — for a small internal-only utility package touched by 2-3 people who already know the codebase, inline `///` comments alone are usually sufficient and a full `.docc` catalog is more ceremony than value.

## Step 3: Swift Package README

For a Swift Package's root `README.md` (note: this is distinct from a Claude skill's folder, which must never contain a README.md — that rule applies only to skill folders, not to Swift Package repositories), cover:

1. **What the package does** — one or two sentences, concrete, not marketing copy.
2. **Installation** — the exact `Package.swift` dependency snippet:
   ```swift
   dependencies: [
       .package(url: "https://github.com/yourorg/YourPackage.git", from: "1.0.0")
   ]
   ```
3. **Quick start** — the smallest possible working code example, not a comprehensive API tour.
4. **Requirements** — minimum iOS/Swift version, and any platform restrictions (e.g. "iOS only, does not support macCatalyst").
5. **Link to full DocC documentation** if a catalog exists, rather than duplicating full API reference in the README.

Keep the README focused on getting a new consumer to a working integration fast; push exhaustive API details to DocC.

## Step 4: Architecture Decision Records (ADRs) for iOS-specific changes

Use for significant, hard-to-reverse decisions: adopting SwiftUI for new screens, migrating from Combine to async/await, adopting a new architecture pattern, choosing a dependency injection approach, or a major modularization restructuring.

Template:

```markdown
# ADR-00XX: [Short title, e.g. "Adopt SwiftUI for all new screens"]

## Status
Proposed / Accepted / Superseded by ADR-00YY

## Context
[What's the current state, and what problem/opportunity prompted this decision?
Be specific: "Our UIKit screens take ~3 files and 200+ lines of boilerplate per
screen, and onboarding new hires to the Massive View Controller pattern takes
~2 weeks before they're productive."]

## Decision
[The actual decision, stated plainly: "All new screens will be built in
SwiftUI, using MVVM. Existing UIKit screens will not be proactively rewritten,
but will migrate opportunistically when touched for unrelated feature work."]

## Consequences
[Both positive and negative, honestly:
- Positive: faster new-screen development, better preview/iteration loop.
- Negative: hybrid UIKit/SwiftUI navigation complexity during the transition
  period (see the swiftui-uikit-bridge skill for the interop mechanics);
  some UIKit-only APIs still require wrapping.]

## Alternatives Considered
[What else was on the table, and why it wasn't chosen — e.g. "Considered a
full rewrite sprint; rejected because it would freeze feature work for an
estimated 6+ weeks with no user-facing benefit during that time."]
```

Points to enforce:

- **State the decision plainly in one sentence** before the surrounding justification — a reader should get the answer from the "Decision" section alone without reading the whole document.
- **Consequences must include the negatives**, not just the benefits — an ADR that only lists upsides reads as marketing, not a genuine trade-off analysis, and won't help a future reader understand why an alternative was avoided.
- **Reference specific, concrete numbers where possible** (build time, screen count, team size) rather than vague claims like "this will improve velocity."

## Step 5: Inline code comments (non-DocC)

For implementation comments (not public API documentation):

- Explain **why**, not what — the code already shows what it does; a comment repeating that in English adds noise. Reserve comments for non-obvious reasoning: "// Apple's UIKit will call this twice on iOS 17 due to a known layout pass quirk; guard against double-invocation here."
- Flag workarounds explicitly, with a reference if possible: `// Workaround for FB123456 (radar filed); remove once fixed in a future SDK.`
- Avoid commented-out dead code in reviewed/merged code — if it's not needed, delete it; git history preserves it if it's ever needed again.

## Example

**User says:** "Document this networking client for our internal Swift Package."

**Actions:**
1. Add `///` DocC comments to each public method, focusing on non-obvious behavior (retry policy, timeout defaults, thread on which completion is called).
2. Write or update the package's `README.md` with installation snippet and a minimal quick-start example.
3. If the package's error-handling design changed recently in a way other teams depend on, suggest a short ADR documenting the change and its rationale, so consumers understand why error types shifted.

**Result:** A consumer of the package can get a working integration from the README in under five minutes, and can find deeper behavioral detail (retry policy, thread guarantees) via Quick Help/DocC without needing to read the implementation.
