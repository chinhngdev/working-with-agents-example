---
name: code-reviewer-skill
description: Review Swift/Apple-platform code changes (macOS, iOS, iPadOS, watchOS, tvOS, visionOS) — a holistic review process and checklist that routes to specialist skills for deep dives. Use when reviewing a PR/diff, reviewing Swift code, when the user asks for a code review of Apple-platform code, or runs /code-reviewer-skill.
---

Apply this process when reviewing Swift/Apple-platform code changes. This skill is an **orchestrator**: it frames how to scope and prioritize a review and gives a checklist organized by concern, but defers to the specialist skills — [[swiftui-skill]], [[uikit-skill]], [[concurrency-skill]], [[apple-testing]] — for the deep, pattern-level detail on their respective domains. Read this skill top-to-bottom for the process; follow the links when a finding falls into a specialist's territory.

## 1. Scope the review before critiquing

- **Read the whole diff first, then re-read with context.** Don't comment line-by-line on a first pass — understand what the change is trying to do (read the PR description/commit messages, and the surrounding unchanged code) before judging whether it does it well.
- **Diff-only vs whole-file.** A diff view hides context above/below the changed hunks. When a change touches state, control flow, or a type's invariants, open the full file — a "correct" 3-line diff can still break an invariant defined 40 lines away.
- **Understand intent before critiquing.** If the approach seems wrong, first ask/consider whether there's a constraint you're missing (existing API shape, platform minimum, performance requirement) rather than assuming the author overlooked something obvious.
- **Match the review depth to the change.** A one-line config tweak doesn't need a concurrency audit; a new actor or a rewritten view model does. Spend review effort proportional to risk and blast radius, not diff size.

## 2. Review checklist by concern

Work through these in rough priority order — correctness and safety first, style last.

- **Correctness / logic bugs.** Does the code do what it claims? Trace edge cases: empty collections, nil/optional paths, off-by-one bounds, first/last item in a loop, error paths that fall through silently. This is the category most worth your attention — see [[#3-prioritizing-findings]] below.
- **State management & data flow.** For SwiftUI, check ownership (`@State` vs `@Observable`/`@StateObject` vs injected), unstable list identity, business logic leaking into `body` — see [[swiftui-skill]]. For UIKit/AppKit, check delegate/outlet wiring, view controller lifecycle ordering, and MVC/MVVM boundary leaks — see [[uikit-skill]].
- **Concurrency & data races.** Any new `Task`, actor, or code crossing an isolation boundary needs scrutiny: missing `Sendable` conformance, `@MainActor` consistency, unstructured `Task`s that outlive their scope, un-cancelled work, continuations resumed the wrong number of times. See [[concurrency-skill]].
- **Test coverage of the change.** Does new logic have tests, and do they test behavior (not the framework)? Are view models/pure functions tested in isolation rather than only through UI? See [[apple-testing]]. A correctness fix without a regression test is an incomplete fix — flag it.
- **API design & Swift idioms.**
  - Value vs reference types: is a `class` used where a `struct` would avoid shared-mutation bugs, or vice versa where identity/reference semantics are actually needed?
  - Optionals: is `Optional` used to mean "absent," not overloaded to also mean "error" or "not yet loaded" (which should be an enum state)?
  - Error handling: does the function throw a specific, typed error (or at least a project-defined `Error` enum) rather than a generic `NSError`/`String`-message error where callers need to branch on failure kind? Typed throws (`throws(SpecificError)`) are worth calling out as an option on Swift 6+ targets when a function's callers need to exhaustively handle failure cases.
  - Access control: is everything `internal` (the default) when it should be `private`/`fileprivate` to protect invariants, and is anything needlessly `public`/`open` in a module boundary?
- **Memory management.** Look for retain cycles: `self` captured strongly in a closure stored by an object that `self` also owns (UIKit delegate closures, Combine `.sink`, async closures passed to a repository). `[weak self]` is needed wherever the closure is stored/escapes and the owner could plausibly outlive the closure's use — but flag *unnecessary* `[weak self]` too (e.g. a `Task` in `.task {}` that's inherently scoped to the view's lifetime often doesn't need it — judge case by case, don't apply it reflexively).
- **Naming and readability.** Names should say what a thing *is*/*does* without needing the diff for context. Flag abbreviations, misleading names (a `get`-prefixed method with side effects), and control flow that requires re-reading to follow (deeply nested conditionals, long boolean expressions without an intermediate named variable).
- **Performance red flags.** O(n²) work in a loop over a collection that's expected to grow, synchronous I/O/heavy computation on the main thread, repeated work that could be cached/computed once, SwiftUI `body` doing sort/filter/format inline (see [[swiftui-skill]]).
- **Security concerns specific to Apple apps.**
  - Secrets (tokens, passwords, API keys) stored in `UserDefaults` or plist/hardcoded in source — must use Keychain instead.
  - Any `NSAllowsArbitraryLoads`/ATS exceptions added to `Info.plist` — should be scoped to a specific domain with justification, never a blanket opt-out.
  - Hardcoded secrets/credentials/API keys in source, even in "test" or "debug" code.
  - Sensitive data (PII, tokens, health/financial data) written to disk unencrypted, logged via `print`/`os_log` at a level that reaches device logs, or included in crash reports/analytics payloads.
  - User input used to build a file path, URL, or predicate without validation (path traversal, unintended `NSPredicate` injection).

## 3. Prioritizing findings

Not every finding deserves equal weight, and burying a real bug under ten style nits makes the review less useful, not more.

- **Blocking (must fix before merge):** correctness bugs, data races/concurrency-safety violations, security issues (secrets in the wrong place, ATS exceptions, unencrypted sensitive data), crashes (force-unwrap on a value that can be nil, array out-of-bounds), and missing tests for genuinely risky new logic.
- **Consider (worth raising, not a blocker):** API design improvements, readability, minor performance concerns without a demonstrated real-world impact, naming.
- **Skip or defer to tooling:** pure style (brace placement, trailing commas, import ordering) that SwiftLint/SwiftFormat already enforces or could enforce — see [[#6-buildlint-signal-awareness]].
- **When in doubt, don't let style crowd out substance.** If you found one real bug and fifteen style nits, lead with the bug. A review that reads as fifteen nits with the bug buried in the middle will get the bug missed.

## 4. Giving feedback

- **Cite `file:line`.** Every finding should point at exactly where it applies, not "somewhere in the networking code."
- **State the concrete failure scenario, not a vague concern.** "This could be an issue" tells the author nothing actionable. "If `items` is empty, `items[0]` traps" tells them exactly what breaks and when.
- **Suggest a fix**, even a rough one — a diff snippet, a named alternative API, or a pointer to the pattern used elsewhere in the codebase.
- **Distinguish "must fix" from "consider"** explicitly in the comment (see severity tags in [[#review-output-format]]) so the author can triage without guessing your intent.
- **Ask, don't assume, when intent is unclear.** If a pattern looks wrong but might be deliberate (e.g. working around a known SDK bug), phrase it as a question rather than a command.

## 5. Swift-specific code smells

- **Force-unwrapping (`!`) outside tests/previews/`#Preview` blocks.** Any `!` on a value that can plausibly be nil at runtime (network response, user input, array access, dictionary lookup) is a crash waiting to happen — flag with the concrete input that would trigger it.
- **Implicitly unwrapped optionals (`T!`) as long-lived properties.** Legitimate only for a handful of framework-mandated patterns (`@IBOutlet`, a two-phase-init dependency set immediately after `init`); anywhere else it's deferring a crash to first use instead of modeling the state honestly with a real `Optional` or restructuring initialization.
- **Stringly-typed APIs where an `enum` fits.** Notification names, cell/segue identifiers, state flags, and API endpoints passed around as raw `String` invite typos that only fail at runtime — flag when a small closed set of values would be a natural `enum` or `RawRepresentable` type.
- **Massive types doing too much.** A view controller, view model, or manager class that owns networking, persistence, formatting, and navigation is a sign responsibilities should be extracted into collaborators — this is the Apple-platform version of God Object; call it out when a type's growth is making the diff you're reviewing harder to reason about, not as a standalone nitpick on unrelated code.
- **Singleton overuse.** `.shared` used for anything with per-instance-meaningful state (not just "the network layer" but a cache, a session, anything with config) works against testability — see [[swiftui-skill]] and [[uikit-skill]] for the DI/`@Environment` alternative.
- **`@objc`/`dynamic` without an actual Objective-C interop need.** These opt the member out of whole-module optimization and defeat some compiler safety checks; only justified when the member is genuinely exposed to Objective-C runtime machinery (KVO, `#selector`, an Objective-C-based framework callback) — flag when added defensively/out of habit on pure-Swift code.

## 6. Build/lint signal awareness

- **Check for compiler warnings** introduced or left unresolved by the diff — a warning silently accepted today is a bug report waiting to happen, and the compiler already did the work of finding it for you.
- **Respect the project's existing SwiftLint/SwiftFormat config** if one exists (`.swiftlint.yml`, `.swiftformat`) — don't request a style change the project's own configured rules explicitly disable or don't flag, even if it's not your personal preference. If the project has no linter config, personal style requests are still lower-priority than anything in [[#3-prioritizing-findings]]'s blocking tier.
- If CI runs the linter/formatter automatically, don't duplicate its output by hand in review comments — link to or defer to that signal instead of restating rule-level nits it already caught.

## 7. Review anti-patterns

Mistakes a reviewer makes, not code mistakes:

- **Nitpicking style while missing a real bug.** Spending the review budget on brace placement while a force-unwrap or a race condition goes unflagged.
- **Approving without reading the whole diff.** Skimming the first file and rubber-stamping the rest, or reviewing only the files GitHub shows by default when more were changed.
- **Requesting changes that duplicate what CI/linters already catch.** Restating a SwiftLint rule by hand instead of trusting the automated signal, or blocking on something a formatter will fix on save.
- **Being vague instead of citing `file:line`.** "This function feels complicated" without naming which function, which line, or what specifically makes it hard to follow.
- **Demanding a rewrite instead of describing the problem.** Telling the author to "just use an actor here" without explaining what race the actor would prevent — state the failure mode and let the author choose the fix unless the fix is genuinely the only reasonable option.
- **Ignoring stated intent/constraints.** Flagging a pattern as wrong without checking whether the PR description or a code comment already explains why it's there.
- **Reviewing in isolation from the specialist skills.** Giving shallow, generic concurrency or SwiftUI feedback instead of pulling in [[concurrency-skill]]/[[swiftui-skill]]/[[uikit-skill]]/[[apple-testing]] for the deep pattern-level check.

**For a ❌/✅ example pairing of vague vs. specific, actionable feedback for each anti-pattern, read `references/common-pitfalls.md`.**

## Review output format

Structure each finding so it drops into a PR review comment or inline-comment thread as-is:

```
[SEVERITY] file/path/Example.swift:42
Summary: One-line statement of the problem.
Scenario: The concrete input/sequence that triggers the failure (or, for non-bugs, the concrete cost — e.g. "re-sorts the full array on every keystroke").
Fix: Suggested change — a snippet, a named API/pattern, or a pointer to precedent elsewhere in the codebase.
```

- **SEVERITY** is one of `BLOCKING` (correctness/security/data-race/crash — see [[#3-prioritizing-findings]]), `CONSIDER` (worth raising, not required), or `NIT` (pure style, mention only if asked or if no linter covers it).
- Group findings by file, blocking first within each file, so the author sees the must-fix items before the nice-to-haves.
- Open with a one-line overall verdict (e.g. "Approve with one blocking fix" / "Needs changes: two blocking, three consider") so the author doesn't have to infer it from comment count.
- End with anything genuinely good about the change worth calling out — reviews that are 100% criticism read as harsher than intended and bury the signal.
