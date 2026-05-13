# DEVLOG — Loom

Running record of decisions, milestone progress, and lessons learned for the Loom kernel. Exists so future sessions — human and AI — can pick up without re-litigating settled questions.

**Update protocol:** every working session ends with at least one entry in the Session Log. Entries are append-only; corrections go in new entries that reference the original. Never edit history. The Current State block at the top is the only section that gets rewritten in place.

---

## Current State

**Active milestone:** M2 — Property edit
**Last touched:** 2026-05-13 — M2 acceptance hit. Both spec invariants enforced: idempotence on every fixture, stability over 1,000 random property edits with minimal-diff verification (10,000-iter mode also passes locally). 48 tests green, no skips remain.
**Blockers:** none
**Next action:** **Eric review gate for M2.** Spot-check spans/serialization, then M3 implementation plan (structural edits — child insert/remove/reorder).

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

### [2026-05-13] Q2 — Trailing-comma detection scope is per-list
**Question:** PROJECT_SPEC.md Open Question 2 — should trailing-comma detection happen per-list, per-file, or per-line?
**Decision:** Per-list. Each `WidgetNode.styleHints.hasTrailingComma` reflects the trailing-comma state of that specific constructor call's argument list, captured at parse time from the token immediately preceding the `rightParenthesis`.
**Rationale:** Spec default. Implicit since M1 first-pass landed — the visitor's `_hintsFromCall` already reads the per-list state. Per-list naturally preserves heterogeneous style across a file: M3's structural edits can grow a list while honoring its own established trailing-comma style without disturbing siblings that disagree.
**Revisit if:** A future Flutter style consensus shifts toward project-wide enforcement and our per-list memory becomes load-bearing in a way that resists style migrations.

### [2026-05-13] Q3 — Equivalence oracle implemented at the model level
**Question:** PROJECT_SPEC.md Open Question 3 was ratified earlier at "structural, trivia-blind, const-aware" and pointed to `lib/src/equivalence/ast_equivalence.dart`. Implement at the analyzer `CompilationUnit` level or at the `WidgetTreeModel` level?
**Decision:** Model level. Implement `StructuralEquivalence.equal(WidgetTreeModel, WidgetTreeModel)` in `lib/src/equivalence/model_equivalence.dart` and leave `ast_equivalence.dart` deleted / unused. The model already excludes trivia by construction (no whitespace, no comments) and captures `const`/`new` keywords in `StyleHints`, so the spec's described equivalence is exactly what recursive field-comparison gives.
**Rationale:** Less code, faster, sufficient for the M2 round-trip property test's oracle role. Going through the analyzer AST would mean re-implementing trivia-skipping and structural normalization that our model already inherently provides. The spec's file path `ast_equivalence.dart` reflected the spec author's mental model of the comparison sitting at the analyzer layer; in practice that layer doesn't earn its keep.
**Revisit if:** Some future invariant needs to distinguish two ASTs that produce the same model (e.g. semantically-equivalent restructurings that the model collapses).

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
2. **Trailing comma detection scope** — **Settled** [2026-05-13]: per-list (captured per-`WidgetNode` in `StyleHints.hasTrailingComma`). See Settled Decisions.
3. **AST equivalence definition** — **Settled** [2026-05-13]: structural, trivia-blind, const-aware, implemented at the model level. See Settled Decisions.
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
- [x] `loom parse <file>` CLI command implemented
- [x] Passes on 5 hand-crafted fixtures (`simple_widget`, `nested_widget`, `no_trailing_commas`, `mixed_const`, `enum_and_bool`)
- [x] Passes on 3 real-world Flutter files (see fixture corpus table)
- [x] Every leaf node has valid `SourceSpan`
- [x] Style hints captured: trailing comma presence, `const` keyword presence
- [x] **Gate**: reviewed by Eric before M2 begins — approved 2026-05-13

### M2 — Property edit

- [x] Single literal property change emits valid `SourceEdit`
- [x] Round-trip property test passes 1,000 random property edits on M1 fixtures (also passes at 10,000 locally)
- [x] `git diff` after any single edit shows exactly one changed line / contiguous range (verified per-iteration via prefix+suffix byte-equality)
- [x] No whitespace, comment, or blank-line changes outside the edited token
- [x] `apply([], source) == source` byte-equal, always
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
| `test/fixtures/nested_widget.dart` | hand-crafted | 20 | 5-level Padding nesting; spans must remain valid through deep recursion |
| `test/fixtures/no_trailing_commas.dart` | hand-crafted | 14 | No trailing commas anywhere; `hasTrailingComma` must be `false` on every node |
| `test/fixtures/mixed_const.dart` | hand-crafted | 23 | Siblings with varying `const` presence; explicit `const` on inner widgets inside non-`const` outer; inherited `const` not promoted to inner `hasConst` |
| `test/fixtures/enum_and_bool.dart` | hand-crafted | 36 | `BoolLiteralValue` (`debugShowCheckedModeBanner: false`), `NullLiteralValue` (`onPressed: null`), `ColorValue` (`Color(0xFF112233)`), `EnumReferenceValue` (`MainAxisAlignment.center`, `TextDirection.ltr`, `Icons.menu`); MaterialApp/Column/IconButton/FloatingActionButton |
| `test/fixtures/real_world_layout_starter.dart` | flutter/website @ `e927ec21`, `examples/layout/base/lib/main_starter.dart` | 22 | MaterialApp + Scaffold (appBar + body) + AppBar + Center; canonical "Welcome to Flutter" |
| `test/fixtures/real_world_widgets_intro_tutorial.dart` | flutter/website @ `e927ec21`, `examples/ui/widgets_intro/lib/main_tutorial.dart` | 39 | Multi-slot Scaffold (appBar + body + floatingActionButton); AppBar with leading + title + actions (list); IconButton + Icon + FloatingActionButton; `onPressed: null` style |
| `test/fixtures/real_world_cookbook_tabs.dart` | flutter/website @ `e927ec21`, `examples/cookbook/design/tabs/lib/main.dart` | 39 | MaterialApp → DefaultTabController → Scaffold → AppBar.bottom = TabBar(tabs: [Tab×3]) + body = TabBarView(children: [Icon×3]); deep list-of-widgets nesting |

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

### [2026-05-13] M2 — property edits, round-trip stability green
**Worked on:** Eric approved the M1 gate; opened M2. Implemented the property-edit write path end-to-end:
  - `StructuralEquivalence` (model-level oracle for Q3) in `lib/src/equivalence/model_equivalence.dart`
  - `NodePath` / `nodeAt` / `withProperty` / `walk` extensions in `lib/src/model/node_path.dart`
  - `PropertySerializer.serialize(PropertyValue)` in `lib/src/emission/property_serializer.dart`
  - `EditPlanner.propertyEdit(oldValue, newValue) -> SourceEdit` in `lib/src/emission/edit_planner.dart`
  - `lib/loom.dart` exports updated
  - Full unit tests in `test/equivalence_test.dart` (13 cases) and `test/emission_test.dart` (17 cases)
  - The round-trip stability test in `test/round_trip_test.dart` is now off-skip: deterministic `Random(0x10AD)` drives 1,000 random property edits across the 8-fixture corpus, verifying both Q3 equivalence and the minimal-diff invariant (prefix and suffix byte-equality) per iteration. Local default raised to 1,000 from 100. CI's `LOOM_PROPERTY_ITERATIONS=10000` also passes locally in well under a second.
**Learned:**
  - **Glados wasn't the right hammer.** It's designed for type-driven generators where the input type doesn't depend on the fixture. Random property edits are fundamentally fixture-bound (you pick a node IN a fixture, then a property OF that node), so a hand-rolled loop with a deterministic seed is simpler and gives better failure reproduction. Kept the `glados` dep for the day a M3+ test fits the type-driven pattern (e.g., generated `EditSequence`s).
  - **`prefer_final_locals` flags pattern variables in switch-expression arms.** `(StringLiteralValue a, StringLiteralValue b) => ...` triggers the lint; `(final StringLiteralValue a, final StringLiteralValue b) => ...` is required. The Dart team's guidance is that pattern-bound names are locals like any other.
  - **The minimal-diff invariant is best checked at byte level, not line level.** The spec says "git diff shows one changed line"; in practice asserting `source[0..editOffset] == newSource[0..editOffset]` and the analogous suffix is strictly stronger and catches issues a line-level check would miss (e.g., whitespace creeping in just past the edit boundary).
  - **Cross-variant property replacement parses cleanly.** A randomly-generated `NullLiteralValue` replacing an `EdgeInsetsAllValue` produces a Dart file that still parses — the analyzer's `parseString` doesn't type-check, so `padding: null` is syntactically valid even if semantically a type error. The property test exercises every variant against every modeled property, and round-trip stability holds throughout.
**Decided:** Q2 — trailing-comma per-list (already implicit, now logged). Q3 — equivalence at the model level in `model_equivalence.dart`, with `ast_equivalence.dart` left vestigial (could be deleted). Both as Settled Decisions.
**Next:** **Eric review gate for M2.** After approval, open M3 implementation plan: structural edits (insert/remove/reorder children), trailing-comma style preservation per Q2's resolution, list-style detection (single-line vs multi-line — new territory).

### [2026-05-13] M1 corpus expansion — 5+3 fixtures, multi-slot refactor, full PropertyValue surface
**Worked on:** Closed out M1 acceptance (modulo Eric review). Refactored `WidgetNode` from a single `children: List<WidgetNode>` to `childSlots: Map<String, List<WidgetNode>>` so Scaffold/AppBar/MaterialApp's multiple widget slots can be modeled. Expanded `PropertyValue` with `BoolLiteralValue`, `NullLiteralValue`, `ColorValue`, `EnumReferenceValue` — completes the M1 surface from PROJECT_SPEC.md. Expanded `WidgetCatalog` to 17 widgets covering everything the new fixtures need. Added 4 hand-crafted edge-case fixtures (nested, no-trailing-commas, mixed-const, enum-and-bool) and 3 real-world fixtures cherry-picked from `flutter/website @ e927ec21`. The round-trip no-op idempotence test now iterates the entire 8-fixture corpus: 9 unit + 8 idempotence assertions all green, M2 stability test still skipped.
**Learned:**
  - **Cherry-picking M1-compatible real-world Flutter code is hard.** The vast majority of files in `flutter/samples` and `flutter/website/examples` use callbacks (`onPressed:`, `onTap:`), helper methods (`_buildSomething()`), conditional rendering (`?:`, `Theme.of(context).x.y`), or constructor calls (`BoxDecoration`, `TextStyle`) not in M1's modeling. Survey found three usable files: a "Welcome to Flutter" starter, the widgets-intro tutorial (Scaffold with multi-slot AppBar), and the cookbook tabs demo. All three pinned at SHA `e927ec21e7ed6c185ade4c0e7341c4bcaff20434` so future re-fetches reproduce.
  - **`Scaffold(body:, appBar:)` and `AppBar(title:, leading:, actions:)` forced the multi-slot refactor.** The original single-children-slot WidgetNode model was a YAGNI choice that broke under the first real-world fixture. Lesson for future milestones: hand-crafted fixtures are insufficient validation; the corpus has to drive design pressure.
  - **`PrefixedIdentifier` covers more than just enum references.** `Icons.menu`, `Colors.blue`, `MainAxisAlignment.center`, and `TextDirection.ltr` are all syntactically identical (`Prefix.member`) but semantically span true enums and static fields. `EnumReferenceValue` treats them uniformly; M1 makes no distinction. M2's emission and M3's AST equivalence will need to be aware of the distinction only if a future bug demands it.
  - **`dart format` does not add or remove trailing commas.** It does reflow lines, which means a "no-trailing-commas" fixture remains no-trailing-commas after format (verified on `no_trailing_commas.dart` — format reflowed one line but didn't insert any commas).
**Decided:** No new Settled Decisions this session. The "hold the line, don't pull M4 forward" call I made when picking real-world fixture sources is implicit in the spec milestone ordering and didn't warrant a separate ratification.
**Next:** **Eric review gate.** When ready, open M2 implementation plan: property-edit emission, `SourceEdit` for a single literal property change, glados-driven round-trip stability test flipped on. That plan should also propose decisions for Open Question Q2 (trailing-comma detection scope — likely settled implicitly by the current per-list `hasTrailingComma` capture).

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

- **Hand-crafted fixtures are insufficient design pressure.** The single-fixture M1 first pass shipped a single-children-slot `WidgetNode` because no fixture demanded otherwise. The first real-world fixture (`Scaffold(body:, appBar:)`) immediately broke that assumption and forced a multi-slot refactor. Future milestones should pull at least one corpus fixture into the design phase before locking the model.
- **`parseString` does not resolve types, so constructor calls without `const`/`new` come back as `MethodInvocation`, not `InstanceCreationExpression`.** This is the canonical shape: `Column(...)` → `MethodInvocation(methodName=Column)`; `const Column(...)` → `InstanceCreationExpression`. Similarly `EdgeInsets.all(8.0)` → `MethodInvocation(target=EdgeInsets, methodName=all)`. The widget visitor normalizes both AST shapes through `_CallInfo` in `lib/src/parsing/widget_visitor.dart`. If we ever switch to a resolved analyzer context (e.g. for cross-file work in M5+), this normalization can collapse to just the `InstanceCreationExpression` path.
- **`test/fixtures/**` is excluded from `dart analyze`.** Fixtures are Flutter source files we parse from a string at test time. They reference packages (Flutter) Loom deliberately does not depend on, so `dart analyze` would flood with `uri_does_not_exist` and `undefined_class` errors. The exclusion lives in `analysis_options.yaml`. If you add a new fixture directory, exclude it the same way.
- **analyzer 6.5.0–7.2.x are broken on current Dart SDKs.** They pull in `package:macros` which depends on `_macros` from the SDK, which the SDK no longer ships. Use `analyzer: ^7.3.0` (and `dart_style: ^3.0.0` so it picks a compatible analyzer). If you see a `version solving failed` error mentioning `_macros 0.x.y from sdk`, this is what you're looking at.

---

## References Consulted

Things read during the work that turned out useful. Helps future sessions avoid re-discovering the same resources.

- _(none yet)_
