# Common code-review anti-patterns and how to avoid them

Each pitfall below is a mistake a *reviewer* makes, not a code mistake. The examples show the same underlying issue caught two ways: a vague/unhelpful comment vs. a specific, actionable one.

### Nitpicking style while missing a real bug
```
❌ "Nit: I'd put a blank line before this closure."

   (Meanwhile, three lines below:)
   let firstItem = results[0]
```
The reviewer spent their comment budget on formatting and never flagged that `results` can be empty (it's the result of a filter above), so `results[0]` will trap.
```
✅ "BLOCKING results/SearchViewModel.swift:58 — `results` can be empty here (it's
   post-filter on line 52), so `results[0]` traps on any query with zero matches.
   Guard with `results.first` and handle the nil case, e.g. show the empty state."
```
**Avoid:** triage correctness/safety issues first; only spend comments on style once you've confirmed there's no blocking issue nearby. If you catch yourself commenting on formatting before you've read the whole file, stop and re-scan for logic bugs first.

### Approving without reading the whole diff
```
❌ "LGTM!"
   (on a PR that changed 6 files; the reviewer's comments only reference file 1)
```
The reviewer's comments never mention the other five files, and one of them introduces an unguarded force-unwrap.
```
✅ "Reviewed all 6 files. Approving NetworkClient.swift and the tests as-is.
   One BLOCKING item in ProfileView.swift:31 (see comment) — please fix before merge,
   the rest is good to go."
```
**Avoid:** state (to yourself and in the review) that you've read every changed file before approving. If a diff is large, say which files you reviewed thoroughly vs. skimmed, rather than implying uniform coverage with a blanket approval.

### Requesting changes that duplicate what CI/linters already catch
```
❌ "Please add a trailing comma here and move the opening brace to the next line."
```
This is exactly what SwiftFormat/SwiftLint auto-fixes on save or in CI — the reviewer is manually re-deriving a rule the project already automates.
```
✅ (no comment — trust the configured `swiftformat`/`swiftlint` CI check to catch this;
   if the project has no such check, then: "CONSIDER: this file isn't covered by our
   SwiftFormat config — worth adding it to the target list so formatting nits like
   brace placement get caught automatically instead of in review.")
```
**Avoid:** check whether the project has a linter/formatter config before commenting on pure style. If it does, trust it and don't restate its rules by hand. If it doesn't, raise the gap (add the tool) rather than manually enforcing style comment-by-comment forever.

### Being vague instead of citing file:line
```
❌ "This function feels overly complicated, might want to clean it up."
```
The author doesn't know which function, which part of it, or what "clean up" means — this comment can't be acted on without asking a follow-up question.
```
✅ "CONSIDER OrderProcessor.swift:104-132 — `applyDiscount(to:)` nests four levels of
   `if` (tier check → date check → region check → override check). Consider extracting
   each condition into a named boolean (e.g. `isEligibleTier`, `isPromoActive`) or
   early-returning on the disqualifying cases — as written, tracing which combination
   of conditions leads to the 20%-off branch requires holding all four in your head."
```
**Avoid:** always name the file, line range, and the *specific* thing that makes it hard to follow (nesting depth, a misleading name, a non-obvious side effect) — "cleaner" and "complicated" are conclusions, not observations the author can act on.

### Demanding a rewrite instead of describing the problem
```
❌ "Just use an actor here."
```
This hands the author a solution without the reasoning, so they can't judge whether it's actually the right one for their constraints (and can't push back if it isn't).
```
✅ "BLOCKING ImageCache.swift:22 — `storage` is a plain `var` dictionary mutated from
   both `loadImage(for:)` (called from view code, main thread) and `prefetch(urls:)`
   (called from a background `Task.detached` in PrefetchController.swift:40). Concurrent
   writes here are a data race. Wrapping `storage` in an `actor` would give compiler-
   enforced isolation instead of relying on callers to remember to hop threads — see
   [[concurrency-skill]] for the pattern. Open to another fix if there's a constraint
   I'm missing (e.g. needing synchronous access somewhere)."
```
**Avoid:** state the concrete failure mode (what races with what, under what call path) and *offer* a fix rather than mandating one — leave room for the author to propose an alternative that satisfies the same constraint.

### Ignoring stated intent/constraints
```
❌ "Why are you catching and swallowing this error instead of letting it propagate?"
   (posted on a line directly below a comment that reads
   `// Known SDK bug: throws spuriously on iOS 17.0-17.1, safe to ignore — rdar://12345`)
```
The reviewer flagged something the author already explained inline, which reads as not having read the surrounding context.
```
✅ (no comment — the existing code comment already justifies the swallowed error with
   a filed radar; if the justification looks thin, ask rather than assert:
   "Is the rdar://12345 workaround still needed for the platforms this app now
   supports, or can we narrow the `#available` check now that the minimum target
   moved to iOS 17.2?")
```
**Avoid:** read adjacent comments, the PR description, and commit messages before flagging something as a mistake — if a justification exists, engage with it (challenge it if it seems stale) rather than repeating the objection it already answers.

### Reviewing in isolation from the specialist skills
```
❌ "This closure looks like it might cause a retain cycle, maybe use weak self?"
   (on a `Task { }` inside a SwiftUI `.task` modifier, scoped to the view's lifetime)
```
Generic, hedged concurrency/memory advice applied reflexively without checking whether it actually applies to this specific pattern.
```
✅ "This `Task` is created inside `.task { }`, which SwiftUI already scopes to the
   view's lifecycle and auto-cancels on disappear — `[weak self]` isn't needed here
   since the closure doesn't outlive the view. (Contrast with the `Task` in
   AuthManager.swift:88, which is fired from a singleton and *does* need `[weak self]`
   since it can outlive its creator.) See [[concurrency-skill]] and [[swiftui-skill]]
   for when the capture actually matters."
```
**Avoid:** pull in the relevant specialist skill's actual rules ([[swiftui-skill]], [[uikit-skill]], [[concurrency-skill]], [[apple-testing]]) before flagging a pattern-level concern, rather than applying a generic rule of thumb that may not fit the specific lifecycle/ownership at hand.
