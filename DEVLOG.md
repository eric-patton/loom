# DEVLOG — Loom

Running record of decisions, milestone progress, and lessons learned for the Loom kernel. Exists so future sessions — human and AI — can pick up without re-litigating settled questions.

**Update protocol:** every working session ends with at least one entry in the Session Log. Entries are append-only; corrections go in new entries that reference the original. Never edit history. The Current State block at the top is the only section that gets rewritten in place.

---

## Current State

**Active milestone:** M1 — Parse only
**Last touched:** 2026-05-13 — M1 first pass against single-fixture (parser, model, CLI, no-op idempotence test green)
**Blockers:** none
**Next action:** Open M1 corpus-expansion plan — pick 4 more hand-crafted fixtures + 3 real-world Flutter files, grow PropertyValue / catalog as those fixtures demand, decide proto-opaque vs hold-the-line. M1 gate (Eric review) follows that plan.

---

## Settled Decisions

Decisions that have been made and should not be re-opened without explicit cause. Newer entries at the top. Each entry references the open question or design choice it resolves.

### Template for new entries

```
### [YYYY-MM-DD] Short decision title
**Question:** What was at issue.
**Decision:** What was chosen.
**Rationale:** Why this over alternatives. Cite the trade-off explicitly.
**Revisit if:** Conditions under which this should be re-opened.
```

### [2026-05-13] Q1 — Preserve `const` and `new` keywords on the node
**Question:** Should the model carry `const`/`new` keywords as node-level metadata, or recompute them on emit?
**Decision:** Preserve. `StyleHints` on each `WidgetNode` captures `hasConst` and `hasNew` at parse time; emission writes back exactly what was there.
**Rationale:** Round-trip safety. If a user wrote `const Padding(...)` we put back `const`. If they removed `const` because they made an argument non-const-eligible, we must not silently re-add it — a recomputing approach risks exactly that silent revert, which the user would have a hard time diagnosing.
**Revisit if:** Model size becomes a bottleneck and we need to shrink, or a const-evaluation library proves it can match the user's intent in every case (e.g., distinguishing "user removed const deliberately" from "user could have written const but didn't").

### [2026-05-13] Q3 — AST equivalence: structural, trivia-blind, const-aware
**Question:** What counts as "the same AST" for the round-trip property tests' oracle?
**Decision:** Structural equivalence ignoring trivia (whitespace, comments), preserving const-vs-non-const distinctions and explicit `new` keywords. Implementation lives in `lib/src/equivalence/ast_equivalence.dart` and is actually written in M2 (when round-trip stability tests turn on); M1 only ensures the model data captures everything this equivalence will need to compare.
**Rationale:** Strict enough to catch real round-trip bugs (different constant-ness *is* a real bug), loose enough to not flag whitespace or comment normalization as failures. Spec default.
**Revisit if:** Round-trip property tests pass on changes that visibly break the source (false negatives), or fail on changes that didn't actually break the source (false positives).

### [2026-05-13] Q5 — Imports and top-level declarations not modeled
**Question:** Should M1–M5 model imports or other top-level declarations?
**Decision:** No. The parser walks only the first `Widget build(BuildContext)` method body found. Imports, library directives, top-level functions, and other class members are preserved by virtue of nothing ever touching them.
**Rationale:** Spec default. Modeling top-level surface adds work no current milestone needs. The non-touching guarantee is sufficient for round-trip correctness, since edits target ranges inside the modeled subtree only.
**Revisit if:** A future feature needs to read or modify imports (e.g., auto-import on widget insertion) or any other top-level construct.

### [2026-05-13] Package and CLI named `loom`, not `twoway_kernel` / `twoway`
**Question:** PROJECT_SPEC.md names the library `twoway_kernel` and the CLI `twoway`, while the repo and DEVLOG use the project codename "Loom". Two-name story (per spec) or one-name story (rename to `loom` across repo, Dart package, and CLI binary)?
**Decision:** One name. The Dart package is `loom` (`lib/loom.dart`, imports as `package:loom/...`), the CLI binary is `loom` (`bin/loom.dart`).
**Rationale:** Simpler to remember, type at the shell, and grep for. The `twoway`/`twoway_kernel` names in the spec predate "Loom" as the project name; carrying both forward adds friction with no benefit. Trade-off: any future external docs referring to `twoway`/`twoway_kernel` (none yet exist) need updating; reverting later would require a coordinated import-line rewrite across the codebase.
**Revisit if:** A separate Dart package or CLI ever ships under the `twoway` name and the two need to coexist.

---

## Open Questions Status

Mirrors the spec's Open Questions section. Update the status field as each resolves.

1. **`const` and `new` keyword handling** — **Settled** [2026-05-13]: preserve on the node via `StyleHints`. See Settled Decisions.
2. **Trailing comma detection scope** — _Unresolved (spec default: per-list)_ — deferred to M3
3. **AST equivalence definition** — **Settled** [2026-05-13]: structural, trivia-blind, const-aware. See Settled Decisions.
4. **Parse errors in the source** — _Unresolved (spec default: partial model + unparseable flag)_ — deferred to M4
5. **Imports and top-level declarations** — **Settled** [2026-05-13]: not modeled; preserved by non-touching. See Settled Decisions.

Each question moves to Settled Decisions once resolved. Replace the entry here with a one-line summary and a link to the decision.

---

## Milestone Progress

Acceptance criteria pulled directly from PROJECT_SPEC.md. Check items off only when they fully pass — partial credit is not credit.

### M1 — Parse only

- [x] Project scaffold per spec's "Project Structure"
- [x] `analysis_options.yaml` with strict lints, warnings-as-errors
- [x] Dependencies installed: `analyzer`, `dart_style`, `test`, `checks`, `glados`, `path`
- [x] CI workflow runs all three test tiers
- [x] Round-trip property test harness stood up in `test/round_trip_test.dart`
- [~] `loom parse <file>` CLI command implemented — works on the single M1 fixture; pending corpus expansion before this ticks fully
- [~] Passes on 5 hand-crafted fixtures — 1 of 5 done (`test/fixtures/simple_widget.dart`)
- [ ] Passes on 3 real-world Flutter files (record which ones)
- [x] Every leaf node has valid `SourceSpan`
- [x] Style hints captured: trailing comma presence, `const` keyword presence
- [ ] **Gate**: reviewed by Eric before M2 begins

### M2 — Property edit

- [ ] Single literal property change emits valid `SourceEdit`
- [ ] Round-trip property test passes 1,000 random property edits on M1 fixtures
- [ ] `git diff` after any single edit shows exactly one changed line / contiguous range
- [ ] No whitespace, comment, or blank-line changes outside the edited token
- [ ] `apply([], source) == source` byte-equal, always
- [ ] **Gate**: reviewed by Eric before M3 begins

### M3 — Structural edits

- [ ] Insert child into `children:` list
- [ ] Remove child from `children:` list
- [ ] Reorder children
- [ ] Trailing comma style detected per-list and preserved
- [ ] Single-line vs multi-line list style detected and preserved
- [ ] Empty-list ↔ non-empty transitions handled
- [ ] Round-trip property tests pass for 10-edit sequences in arbitrary order
- [ ] **Gate**: reviewed by Eric before M4 begins

### M4 — Opaque blocks

- [ ] `OpaqueNode` type added to model
- [ ] Closures become opaque nodes
- [ ] Conditional expressions become opaque nodes
- [ ] `.map().toList()` patterns become opaque nodes
- [ ] Ternaries become opaque nodes
- [ ] Method calls returning Widget become opaque nodes (deferred to M5 for in-class methods)
- [ ] API throws on attempted mutation of opaque node
- [ ] Opaque content byte-preserved through any sequence of edits to surrounding nodes
- [ ] Parses a complex real-world fixture without crashing
- [ ] **Gate**: reviewed by Eric before M5 begins

### M5 — Helper method following

- [ ] In-class method references represented as `MethodReferenceNode`
- [ ] Navigation into referenced method works
- [ ] Edits to referenced method update the helper's source
- [ ] Cyclic references detected, no infinite recursion
- [ ] Cross-file references explicitly fall back to opaque
- [ ] Round-trip invariants hold across method boundaries
- [ ] **Gate**: reviewed by Eric — kernel ships to UI layer

---

## Fixture Corpus

The pinned 20-file corpus that gates "kernel ships." Add files here as they're added to `test/fixtures/`. Note source, line count, and any notable constructs that exercise specific kernel features.

| File | Source | Lines | Exercises |
|---|---|---|---|
| `test/fixtures/simple_widget.dart` | hand-crafted | 23 | Column-of-Text-and-Padding, mixed `const`/non-`const`, EdgeInsets.all with both int and double literals, single-child vs list-children |

---

## Session Log

Reverse chronological. Each entry: date, what was worked on, what was learned, what's next. Every session ends with at least one entry. Keep entries terse — this is a log, not an essay.

### Template for new entries

```
### [YYYY-MM-DD]
**Worked on:** What you touched, briefly.
**Learned:** Non-obvious things discovered. If a real lesson, also add to Gotchas.
**Decided:** Reference Settled Decisions entry if applicable.
**Next:** Concrete next action for the following session.
```

### [2026-05-13] M1 first pass — single-fixture parser + CLI + idempotence test green
**Worked on:** M1 implementation against the single 30-line `MyHomePage` fixture per PROJECT_SPEC.md First Task. Implemented `SourceSpan`, `StyleHints`, `PropertyValue` (3 variants), `WidgetNode`, `WidgetTreeModel`, `WidgetCatalog` (Column/Text/Padding), `WidgetVisitor`, `parseWidgetTree`, `SourceEdit` + `applySourceEdits`. Wired up `lib/loom.dart` exports. Implemented `loom parse <file>`. Created the fixture. Added 9 parsing unit tests + flipped the no-op idempotence round-trip skip off. All 10 tests green, `dart analyze` clean.
**Learned:**
  - **Without type resolution, `parseString` returns `MethodInvocation`, not `InstanceCreationExpression`, for constructor calls that lack `const`/`new`.** Bit me on the first CLI smoke test (`Expected widget constructor call, got MethodInvocationImpl`). The visitor now normalizes both AST shapes through a private `_CallInfo` struct — `Foo(...)` (no keyword) lands as `MethodInvocation`, `const Foo(...)` lands as `InstanceCreationExpression`. Added to Gotchas.
  - **`test/fixtures/**` must be excluded from `dart analyze`.** The fixture imports `package:flutter/material.dart` which Loom (pure-Dart kernel) does not depend on. Added an `analyzer.exclude` rule to `analysis_options.yaml`. The parser still operates on the file fine because it reads the source string at test time, not the compile-time analyzer view.
  - The `widget_visitor.dart`'s `_tryExtractCall` also has to handle `Foo.bar()` (MethodInvocation with target=Identifier(Foo)) as a named-constructor call, which is how `EdgeInsets.all(8.0)` arrives.
**Decided:** Q1 / Q3 / Q5 ratified at start of session per process rule #2 — see Settled Decisions [2026-05-13] entries for each. Spec defaults adopted in all three cases.
**Next:** Open M1 corpus-expansion plan: 4 more hand-crafted fixtures + 3 real-world Flutter files, grow `PropertyValue`/catalog as needed, decide proto-opaque vs strict-throw for unmodelable widgets. After that lands and Eric reviews, M1 gate closes and M2 begins.

### [2026-05-13] Project kickoff — scaffolding complete
**Worked on:** PROJECT_SPEC.md "First Task" — project structure, deps, strict lints, GitHub Actions CI workflow, round-trip property-test harness skeleton. No functional kernel code yet; all `lib/src/*` files are stubs with milestone-tagged TODOs.
**Learned:**
  - **analyzer 6.5.0 through 7.2.x are unusable on current Dart SDKs** (3.11.5 here): they pull in the experimental `macros` package, which depends on `_macros` from the SDK — and `_macros` no longer ships. Workaround: pin `analyzer: ^7.3.0` plus `dart_style: ^3.0.0`. Resolved versions: analyzer 7.7.1, dart_style 3.1.1, glados 1.1.7, lints 5.1.1. Added to Gotchas.
  - `package:lints/recommended.yaml` with `strict-casts`/`strict-inference`/`strict-raw-types` plus the four extra rules (`prefer_final_locals`, `prefer_final_in_for_each`, `avoid_dynamic_calls`, `prefer_typing_uninitialized_variables`) passes cleanly on the stub files. No friction to report yet — the real test is when M1 code lands.
  - `dart format` opinionated about cascade indentation in the CLI stub; fixed on first run.
  - `_propertyIterations` and `_loadFixture` in the harness are referenced inside the skipped test bodies so the analyzer sees them as "used". This keeps `unused_element` quiet without a file-level ignore.
**Decided:** `twoway_kernel`/`twoway` renamed to `loom` everywhere — see Settled Decisions [2026-05-13].
**Next:** Propose M1 implementation plan in a new planning round. As part of that plan, propose decisions for Open Questions Q1 (`const`/`new` keyword handling), Q3 (AST equivalence definition), and Q5 (imports/top-level treatment), and pause for ratification before writing code. Q2 (trailing commas, M3 scope) and Q4 (parse errors, M4 scope) wait.

---

## Gotchas and Lessons

Running list of non-obvious things discovered along the way. Reference these in code comments where applicable. Newest at the top.

- **`parseString` does not resolve types, so constructor calls without `const`/`new` come back as `MethodInvocation`, not `InstanceCreationExpression`.** This is the canonical shape: `Column(...)` → `MethodInvocation(methodName=Column)`; `const Column(...)` → `InstanceCreationExpression`. Similarly `EdgeInsets.all(8.0)` → `MethodInvocation(target=EdgeInsets, methodName=all)`. The widget visitor normalizes both AST shapes through `_CallInfo` in `lib/src/parsing/widget_visitor.dart`. If we ever switch to a resolved analyzer context (e.g. for cross-file work in M5+), this normalization can collapse to just the `InstanceCreationExpression` path.
- **`test/fixtures/**` is excluded from `dart analyze`.** Fixtures are Flutter source files we parse from a string at test time. They reference packages (Flutter) Loom deliberately does not depend on, so `dart analyze` would flood with `uri_does_not_exist` and `undefined_class` errors. The exclusion lives in `analysis_options.yaml`. If you add a new fixture directory, exclude it the same way.
- **analyzer 6.5.0–7.2.x are broken on current Dart SDKs.** They pull in `package:macros` which depends on `_macros` from the SDK, which the SDK no longer ships. Use `analyzer: ^7.3.0` (and `dart_style: ^3.0.0` so it picks a compatible analyzer). If you see a `version solving failed` error mentioning `_macros 0.x.y from sdk`, this is what you're looking at.

---

## References Consulted

Things read during the work that turned out useful. Helps future sessions avoid re-discovering the same resources.

- _(none yet)_
