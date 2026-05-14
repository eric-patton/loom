# DEVLOG — Loom

Running record of decisions, milestone progress, and lessons learned for the Loom kernel. Exists so future sessions — human and AI — can pick up without re-litigating settled questions.

**Update protocol:** every working session ends with at least one entry in the Session Log. Entries are append-only; corrections go in new entries that reference the original. Never edit history. The Current State block at the top is the only section that gets rewritten in place.

---

## Current State

**Active milestone:** M5.4 — scout pass + Dart 3.x experimental-feature opt-in
**Last touched:** 2026-05-14 — Eric-requested scout against flutter/codelabs (1068 .dart files): **0 crashes, 0 idempotence failures**, 392 clean parses, 676 expected `ParseException` (no `build()`), and 2 files with diagnostics that turned out to be a real issue: our pinned `analyzer ^7.3.0` is older than the SDK-bundled one and doesn't enable recent experimental flags by default. Fixed by passing an explicit `featureSet` to `parseString` enabling `dot-shorthands`, `digit-separators`, `null-aware-elements`, `wildcard-variables`. Re-scout: **392 clean / 0 diagnostics / 0 crashes / 0 idempotence failures**. Also landed `tool/scout.dart` as a reusable utility for future broad real-world testing.
**Blockers:** none
**Next action:** **Eric review gate for M5 + M5.1 + M5.2 + M5.3 + M5.4.** Every spec Open Question is settled; the kernel has been validated against 1000+ real Flutter files in addition to the 20-fixture pinned corpus. Long-term TODO (deliberately deferred, not blocking review): bump `analyzer` past 13.0.0 once the visitor adapts to its renamed AST API (`NamedExpression` → `Argument`, `members` getter rename, etc.). The experimental-flags list is a band-aid that grows as future scouts find more features; the proper fix is matching the SDK-bundled analyzer.

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

### [2026-05-14] Q4 — Parse errors: partial model + diagnostics list
**Question:** PROJECT_SPEC.md Open Question 4 — how should the parser behave when the source has syntax errors? Throw, drop the whole model, or build a partial model?
**Decision:** Spec default — partial model + diagnostics list. `parseString` is called with `throwIfDiagnostics: false`, and the analyzer's `errors` list is surfaced on `WidgetTreeModel.diagnostics` as `List<ParseDiagnostic>` (each carries `SourceSpan` + message). The model itself reflects what the analyzer could error-recover; UI consumers can either show a "this file has syntax errors" warning or refuse edits while diagnostics are non-empty.
**Rationale:** Throwing on errors would break the natural UI flow where a file is briefly unparseable mid-typing. A partial model preserves the editor's ability to show structure for the parts that DID parse, while the diagnostics flag warns the consumer not to apply destructive edits. Cost is essentially zero — the analyzer already returns the diagnostics list; we just propagate it.
**Revisit if:** A real consumer needs richer diagnostic shape (severity levels, error codes) that the current `ParseDiagnostic` (span + message) doesn't capture, or if error-recovered ASTs prove unsafe to model at all (haven't seen any cases in the corpus).

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
4. **Parse errors in the source** — **Settled** [2026-05-14]: partial model + diagnostics list on `WidgetTreeModel.diagnostics`. See Settled Decisions.
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

- [x] Insert child into `children:` list
- [x] Remove child from `children:` list
- [x] Reorder children
- [x] Trailing comma style detected per-list and preserved
- [x] Single-line vs multi-line list style detected and preserved
- [x] Empty-list ↔ non-empty transitions handled
- [x] Round-trip property tests pass for 10-edit sequences in arbitrary order (1,000 sequences local, 10,000 sequences = ~100,000 edits in CI)
- [ ] **Gate**: reviewed by Eric before M4 begins

### M4 — Opaque blocks

- [x] `OpaqueNode` type added to model (sealed `ModelNode` with `WidgetNode`/`OpaqueNode`)
- [x] Closures become opaque nodes (`FunctionExpression` -> `OpaquePropertyValue` at property positions, `OpaqueNode` at widget positions)
- [x] Conditional expressions become opaque nodes
- [x] `.map().toList()` patterns become opaque nodes
- [x] Ternaries become opaque nodes
- [x] Method calls returning Widget become opaque nodes (in-class promotion is M5)
- [x] API throws on attempted mutation of opaque node (`OpaqueEditException`)
- [x] Opaque content byte-preserved through any sequence of edits to surrounding nodes (verified by the property tests now that the corpus contains an opaque fixture)
- [x] Parses a complex real-world fixture without crashing (`real_world_opaque_mybutton.dart`)
- [ ] **Gate**: reviewed by Eric before M5 begins

### M5 — Helper method following

- [x] In-class method references represented as `MethodReferenceNode`
- [x] Navigation into referenced method works (`nodeAt` / `walk` descend through the virtual `body` slot; `withProperty` / `_modifySlot` rebuild the `MethodReferenceNode` chain)
- [x] Edits to referenced method update the helper's source (body's nodes carry sourceSpans that point into the helper definition, so `EditPlanner.propertyEdit` naturally targets the helper)
- [x] Cyclic references detected, no infinite recursion (`_resolvingMethods` set; inner self-reference becomes `OpaqueNode`)
- [x] Cross-file references explicitly fall back to opaque (only in-class methods are looked up; everything else stays an `OpaqueNode`)
- [x] Round-trip invariants hold across method boundaries (verified by the round-trip property test running 1,000+ random edits across `helper_methods.dart`)
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
| `test/fixtures/real_world_opaque_mybutton.dart` | flutter/website @ `e927ec21`, `examples/ui/widgets_intro/lib/main_mybutton.dart` | 33 | M4 opaque coverage: closure (`onTap: () {…}`), unmodeled constructors (`BoxDecoration`, `BorderRadius.circular`), `EdgeInsets.symmetric`, indexer (`Colors.lightGreen[500]`), user-defined widget class (`MyButton`) |
| `test/fixtures/helper_methods.dart` | hand-crafted | 28 | M5: in-class helpers (`_buildTitle`, `_buildContent`) each called once from `build()`. Edits inside helpers must target the helper's source range, not the call site |
| `test/fixtures/real_world_layout_base.dart` | flutter/website @ `e927ec21`, `examples/layout/base/lib/main.dart` | 30 | Minimal MaterialApp → Scaffold(appBar, body=Center(child=Text)) with `// #docregion` comments around catalog widgets |
| `test/fixtures/real_world_basic_list.dart` | flutter/website @ `e927ec21`, `examples/cookbook/lists/basic_list/lib/main.dart` | 24 | MaterialApp → Scaffold with `body: ListView(children: [ListTile, ...])`. ListView/ListTile not in catalog — exercises an opaque widget contained in a single-shaped slot |
| `test/fixtures/real_world_horizontal_list.dart` | flutter/website @ `e927ec21`, `examples/cookbook/lists/horizontal_list/lib/main.dart` | 37 | Container with `margin: EdgeInsets.symmetric(...)` opaque property + height literal int + ScrollConfiguration opaque child; collection-for inside ListView |
| `test/fixtures/real_world_navigation_basics.dart` | flutter/website @ `e927ec21`, `examples/cookbook/navigation/navigation_basics/lib/main.dart` | 45 | First-of-multiple classes (FirstRoute) with Scaffold → Center → ElevatedButton(child:, onPressed: closure); SecondRoute defined but parser uses first class only |
| `test/fixtures/real_world_passing_data.dart` | flutter/website @ `e927ec21`, `examples/cookbook/navigation/passing_data/lib/main.dart` | 78 | Three classes (Todo data class, TodosScreen, DetailScreen). Parser picks TodosScreen; Scaffold → ListView.builder (opaque) with closures |
| `test/fixtures/real_world_snackbars.dart` | flutter/website @ `e927ec21`, `examples/cookbook/design/snackbars/lib/main.dart` | 50 | SnackBarDemo first; MaterialApp → Scaffold → opaque SnackBarPage; second class Center(child: ElevatedButton(...)) defined but not modeled |
| `test/fixtures/real_world_grid_lists.dart` | flutter/website @ `e927ec21`, `examples/cookbook/lists/grid_lists/lib/main.dart` | 35 | MaterialApp → Scaffold → opaque GridView.count with closure inside `List.generate(...)` |
| `test/fixtures/real_world_orientation.dart` | flutter/website @ `e927ec21`, `examples/cookbook/design/orientation/lib/main.dart` | 47 | First class MyApp uses `const MaterialApp(...)` containing opaque OrientationList; exercises const-MaterialApp + opaque-single-slot |
| `test/fixtures/real_world_text_input.dart` | flutter/website @ `e927ec21`, `examples/cookbook/forms/text_input/lib/main.dart` | 50 | MaterialApp → Scaffold → opaque MyCustomForm; second class MyCustomForm uses Column with multiple Paddings around opaque TextField/TextFormField |
| `test/fixtures/real_world_long_lists.dart` | flutter/website @ `e927ec21`, `examples/cookbook/lists/long_lists/lib/main.dart` | 32 | MyApp with non-const constructor and `final List<String> items` field; MaterialApp → Scaffold → opaque ListView.builder with closures |

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

### [2026-05-14] M5.4 — scout against flutter/codelabs + Dart 3.x feature-flag fix
**Worked on:** Eric asked for a "real-world scout" — point the kernel at every `.dart` file in a popular modern Flutter repo and see what breaks. Picked flutter/codelabs (1068 .dart files; modern Dart 3.x, actively maintained).

**Scout result (first pass):**
- 1068 total files
- 0 crashes
- 0 no-op idempotence failures (the spec's invariant 2 held on every parsed file)
- 392 parsed clean (real widget trees, no diagnostics)
- 676 `ParseException` (no `build()` method — data classes, tests, generated code; all expected)
- 2 parsed-with-diagnostics

The 2 diagnostic files (`google-maps-in-flutter/step_3/lib/main.dart` and `webview_flutter/step_03/lib/main.dart`) both use Dart's dot-shorthand syntax (`colorScheme: .fromSeed(...)`, `mainAxisAlignment: .center`). Our parser surfaced "this requires the 'dot-shorthands' language feature to be enabled" diagnostics on both.

**Root cause:** the kernel pins `analyzer: ^7.3.0` (the `_macros` SDK-conflict workaround that landed during M1 scaffolding). The SDK-bundled analyzer (on Dart 3.11.5) is much newer — likely analyzer 13.0.0 — and has dot-shorthand stable by default. Our pinned 7.7.1 still treats it as experimental.

**Tried bumping `analyzer: ^13.0.0`:** pub solved cleanly, but the kernel's visitor doesn't compile against the new AST. Breaking changes in analyzer 8+: `ClassDeclaration.members` getter renamed, `NamedExpression` renamed to `Argument`, `NamedType.name2` renamed. Adapting the visitor is non-trivial and would be its own milestone.

**Pragmatic fix:** pass an explicit `FeatureSet` to `parseString` that enables the experimental flags our pinned analyzer knows about but doesn't enable by default. List currently includes `dot-shorthands`, `digit-separators`, `null-aware-elements`, `wildcard-variables`. New `_enabledExperimentalFlags` constant in `widget_tree_parser.dart` documents the why; future scouts that find more missing features add to it.

**Re-scout after the fix:** 1068 files / **0 crashes / 0 idempotence failures / 0 diagnostics / 392 clean parses**. The dot-shorthand files now parse clean. The visitor's "any AST shape we don't model becomes opaque" design did the rest — `.fromSeed(...)` and `.center` round-trip as `OpaquePropertyValue`s.

**New tool: `tool/scout.dart`** — point at any directory, get a summary of total / clean / diagnostics / crashes / idempotence failures, plus the file paths of any failures or diagnostic-bearing files. ~100 LOC. Reusable for future broad real-world testing against arbitrary Flutter codebases.

**Learned:**
- **The kernel's graceful-degradation design works in the wild.** Across 1068 real Flutter files spanning beginner codelabs to production-quality samples, zero AST shapes crashed the visitor. Everything we don't model lands as `OpaqueNode` / `OpaquePropertyValue` exactly as designed.
- **Pinned analyzer dep is a real-world ceiling on language-feature support.** Anything that became stable AFTER our pinned analyzer's release still needs an experimental flag. The flag-list workaround is fragile (we'd need to keep adding flags as Dart evolves) and the proper fix is matching the SDK-bundled analyzer. Documented as a Gotcha.

**Headline numbers:** 114 tests + scout against 1068 real-world files, all green. The kernel is now validated well beyond the 20-fixture spec corpus.

**Next:** Eric reviews and ratifies M5 + M5.1 + M5.2 + M5.3 + M5.4. The kernel is ready to ship. Long-term: bump analyzer past 13.0.0 once the visitor adapts to its renamed AST API — that's UI-integration-time work, not pre-review work.

### [2026-05-14] M5.3 — close all deferred items: root widen, Q4, applySourceEdits perf, corpus 10→20
**Worked on:** Closed every item that was deliberately deferred from M5.1 / M5.2.

**Root widened from `WidgetNode` to `ModelNode`** (Gotcha resolved):
  - `WidgetTreeModel.root: ModelNode` — bare-helper-root `build() => _h()` now resolves at the root level (returns `MethodReferenceNode(_h)` or `OpaqueNode` per the multi-reference defense), no more `ParseException` for that pattern. Skipped test un-skipped.
  - `WidgetVisitor.convertWidget` deleted; `parseWidgetTree` calls `convertModelNode` directly. `ParseException` now only fires when there's no `build()` method or its body has no return expression.
  - `NodeNavigation` extension methods (`withProperty`, `insertChild`, `removeChild`, `moveChild`) dispatch through the existing `_withPropertyOnModelNode` / `_modifySlotOnModelNode` helpers so any of the three root types works. The single-shaped-slot guard in `_requireListSlotParent` still uses `nodeAt(parentPath) is WidgetNode` — non-WidgetNode parents (e.g. opaque or method-ref) can't be structurally edited anyway, matching planner behavior.
  - CLI's `_printTree` switches on the root subtype to render an appropriate header line, and emits any captured `diagnostics` before the tree.
  - Test sites that assume a `WidgetNode` root use `model.root as WidgetNode` casts; the existing fixture corpus all have widget roots so no test behavior changed.

**Q4 ratified** (Settled Decision [2026-05-14]):
  - `WidgetTreeModel.diagnostics: List<ParseDiagnostic>` — spans + messages translated from the analyzer's `result.errors`. Empty for clean source; populated when the analyzer error-recovers.
  - New `ParseDiagnostic { span, message }` value type (avoids leaking `package:analyzer` types through the public API).
  - Two new tests: clean source → empty diagnostics; source with a missing close paren → non-empty diagnostics, all carrying valid spans + messages.

**`applySourceEdits` rewritten as O(N) single-pass StringBuffer walk:**
  - Previously each `replaceRange` re-allocated the source — `O(N * source.length)` for N edits.
  - Now: walk the already-sorted ascending list with a cursor, emit pre-edit bytes via `buf.write(source.substring(...))`, emit replacement, advance cursor past edit. O(source.length + sum-of-replacements). Behavior identical (validated by the full 200k-edit property test still being green).
  - Future-proofs the kernel for batched-output UI consumers issuing 1000+ edits per call.

**`==` policy unified across `ModelNode` subtypes:**
  - Removed `==` / `hashCode` overrides from `OpaqueNode` and `MethodReferenceNode`. All `ModelNode`s default to identity comparison.
  - `StructuralEquivalence.equal` is now unambiguously the only oracle. Previously `MethodReferenceNode == MethodReferenceNode` recursively called `==` on `body`, which gave identity-fallback for `WidgetNode` bodies and structural-comparison for `OpaqueNode` bodies — inconsistent based on what the helper happened to return.

**PROJECT_SPEC.md disclaimer** added at the top of the spec doc, pointing readers at DEVLOG.md for current state. Lists the specific deltas (package rename, file consolidations, `WidgetTreeModel.root` widening, diagnostics surface, catalog of 17 widgets).

**Corpus 10 → 20 fixtures:** sourced 10 more files from flutter/website at the same pinned commit (`e927ec21e7ed6c185ade4c0e7341c4bcaff20434`):
  - `real_world_layout_base.dart` — minimal MaterialApp+Scaffold+Center+Text
  - `real_world_basic_list.dart` — ListView opaque inside Scaffold.body
  - `real_world_horizontal_list.dart` — Container with `EdgeInsets.symmetric` opaque property
  - `real_world_navigation_basics.dart` — first-of-multiple classes with onPressed closure
  - `real_world_passing_data.dart` — three classes (Todo data class + TodosScreen first), opaque ListView.builder
  - `real_world_snackbars.dart` — MaterialApp+Scaffold with opaque SnackBarPage and closure-heavy second class
  - `real_world_grid_lists.dart` — opaque GridView.count + closure inside `List.generate`
  - `real_world_orientation.dart` — `const MaterialApp(...)` with opaque OrientationList
  - `real_world_text_input.dart` — Column with multiple Padding wrappers around opaque TextField/TextFormField
  - `real_world_long_lists.dart` — non-const MyApp constructor with `final List<String> items` field, opaque ListView.builder
  - Fixture corpus table in DEVLOG.md updated with attribution and what each exercises.

**Learned:**
  - **The fixture corpus exposed that the existing M5.2 fix for `Container(width: 160, color: color)` produces a non-list child slot.** Actually no — the `_for-in` collection element inside the ListView's `children:` is an `Expression` from `for (final color in Colors.primaries) Container(...)` — analyzer's AST has it as `ForElement`. The visitor's `_collectChildSlot` checks `if (element is Expression)` and skips ForElement (it's a `CollectionElement` subtype, not an `Expression`), so the whole element opaques. Worked as designed. (No code change needed — leaving this note for future me.)
  - **Real flutter/website source has `// #docregion` comments scattered between widget elements.** These DO live in list-element separators. The existing comment-preservation fix in `_trimEndBeforeComment` / `_trimStartAfterComment` handles them naturally because they look like ordinary line comments. Stress-tested at 10k iterations per fixture across all 20 — green.
  - **Root widening had subtler downstream impact than expected.** The model's `withProperty` / `insertChild` / `removeChild` / `moveChild` ALL had to dispatch through their `ModelNode`-aware variants rather than the `WidgetNode`-only ones. Once redirected, the existing `_requireListSlotParent` guard transparently handled non-WidgetNode roots (they fail the `is! WidgetNode` check on `nodeAt(parentPath)` with a clear error).

**Headline numbers:** 114 tests passing, **0 skips**. CI-grade run at 10k iterations per fixture across 20 fixtures ≈ 25 seconds (~200k property edits + ~200k structural edits). The doubled corpus paired with the unchanged per-fixture iteration count means the round-trip property test now exercises 400k edits per CI invocation.

**Next:** Eric reviews and ratifies M5 + M5.1 + M5.2 + M5.3. Every spec Open Question is now closed. No remaining deferred items. Kernel is ready to ship to a UI layer.

### [2026-05-14] M5.2 — round-2 hardening: close BLOCKER/HIGH findings and opportunistic mediums
**Worked on:** Round-2 multi-agent peer review surfaced 5 real bugs (1 BLOCKER + 4 latent-but-real) plus ~10 mediums and a clutch of polish nits. This pass closes all five bugs, four of the mediums, and the cheap polish items; the rest were either deliberately deferred (out of scope) or judged cosmetic and not worth churning.

**Real bugs fixed:**
  - **`applySourceEdits` same-offset validation hole.** Two edits at the same offset where one is a pure insert (`length==0`) and the other has `length>0` used to pass validation in one input order and throw `"overlap"` in the reverse order, with the descending-offset sort then applying them in undefined relative order — the unstable sort dropped the pure insert silently. Now: any two edits at the same offset throw `ArgumentError` ("application order is ambiguous"), regardless of length. Single unambiguous case for same-offset edits doesn't exist — "does the insert land before or after the replacement?" has no canonical answer.
  - **Last-element removal with a preserved trailing comment + a trailing comma leaves an orphan comma.** `[A, // c\n  B,]` → `removeChildEdit(index:1)` used to yield `[A, // c\n  ,]`, which analyzer error-recovers as a list with an empty second element. The reparse said 2 children while the model said 1 — direct invariant violation. Fix: when `_trimStartAfterComment` preserved a comment (i.e. `separatorStart > prev.sourceSpan.end`), the inter-element comma now functions as the trailing comma; extend the deletion to consume the original trailing comma after the removed element. The no-comment case is unchanged.
  - **Empty multi-line list insert double-indents and adds spurious trailing comma.** For `children: [\n      ],` (6-space indent on `]`'s line) inserting a Text used to emit a 12-space indent + an unwanted `,`. Fix: anchor the insertion just AFTER the opening `[` (so the existing newline+whitespace before `]` naturally becomes the closing-bracket indent), and don't emit a trailing comma (the empty list's `hasTrailingComma` is always `false` by parse semantics; the model's `insertChild` doesn't flip it, so emitting one would make the in-memory and reparsed models disagree).
  - **`_interElementSep` fallback hardcoded 2-space indent.** When the natural separator between two list elements contained a `//` or `/*` (and so couldn't be duplicated), the fallback used `,\n  ` regardless of the real list indent. Inside nested widgets the real indent might be 8 or 10 spaces, so trailing siblings got pushed out of column. Round-trip equivalence still held (style-blind comparison), but Global Acceptance #4 ("whitespace in unedited regions preserved byte-for-byte") was broken. Fix: infer the indent from the first element's line.
  - **Model and planner disagree on non-list slots.** After M5.1.2, a non-list expression in a list-shaped slot (`children: spread()`) is recorded as a single `OpaqueNode` with no `ListSlotStyle`. `EditPlanner` refuses to plan structural edits there (its `_requireListStyle` throws); `WidgetTreeModel.insertChild`/`removeChild`/`moveChild` happily mutated and produced models that couldn't be serialized. Fix: a new `_requireListSlotParent` guard in `node_path.dart` resolves the parent and rejects the call if the slot has no `ListSlotStyle` — matching the planner's behavior. Same guard applies to single-shaped slots like `Padding.child`, which were never legitimately structurally-editable.

**Mediums fixed:**
  - **Widget-position-aware `_ReferenceCounter`.** The old counter was a `RecursiveAstVisitor` that walked the entire AST and counted every no-target, no-arg `_method()` invocation. It over-counted in property positions (`Text(_a())`), method-call targets (`_a().wrap()`), and inside opaque expressions (closures, ternaries) — the visitor wouldn't resolve `_a()` to a `MethodReferenceNode` in any of those, so they shouldn't count toward the multi-reference limit. Fix: rewrote the counter as a recursive walker that mirrors `WidgetVisitor.convertModelNode`'s logic exactly — uses the catalog to identify constructor calls, recurses into named-arg expressions for known child slots, treats everything else as opaque/property and stops. Same self-recursion / indirect-cycle defense still works.
  - **`__positional$i` override conflict in `WidgetSerializer`.** If a hand-built `WidgetNode` had BOTH a catalog-mapped positional (`data` for Text at index 0) AND a `__positional0` opaque, the serializer's `positionalByIndex` map silently let one override the other. The visitor never produces this shape; external callers can. Fix: throws `ArgumentError` when both keys claim the same index.
  - **`MethodReferenceNode` dropped type arguments.** `_h<int>()` resolved to `MethodReferenceNode(_h)` whose serializer emits `_h()` — type args lost on re-emission. Fix: visitor requires `typeArguments == null` on the no-target-no-arg shape; type-argumented helper calls fall through to `OpaqueNode`, which round-trips the source bytes (including type args) verbatim. Same `typeArguments == null` check added to the reference counter.

**Cleanup / polish:**
  - **Dropped `checks` and `glados`** from `pubspec.yaml` dev_dependencies. Neither was imported anywhere after M2's hand-rolled property loop replaced the glados-driven plan.
  - **Inlined `_extractReturnExpression` forwarder** in `widget_visitor.dart`. Was a one-liner forwarding to top-level `extractMethodReturnExpression`; the call site now uses the top-level function directly.
  - **Removed `comment_references` lint** from `analysis_options.yaml`. Earned nothing — the codebase uses backtick `Identifier` style for doc references, not bracket `[Identifier]`, so the rule never fired.
  - **`_formatString` now escapes 0x7F (DEL)** as `\x7f`. Previously passed through as a raw non-printable byte. (Round-trip-correct, but emitting non-printable bytes in re-serialized source is a code-quality concern.)
  - **Removed `final fixture = initialFixture;` leftover** in `round_trip_test.dart`'s structural-edit loop. The outer `for (final initialFixture in fixtures)` was a refactor artifact; the inner alias served no purpose.

**Strengthened tests:**
  - `applySourceEdits` validation: new test for the mixed-length same-offset case, both input orders.
  - `EditPlanner` structural edits: new tests for last-element-with-comment removal, empty-multi-line-list insert indent + no-trailing-comma, and the fallback-indent case with a comment in the natural separator.
  - `WidgetTreeModel`: new test verifying the model's structural-edit API refuses non-list slots.
  - `WidgetSerializer`: new test for the positional-override conflict.
  - Parser: new tests for the widget-position-aware counter (helper called from a property position still resolves at the widget position) and for the typeArguments fall-through to opaque.
  - New "opaque byte preservation" test: edit a literal far from an opaque region, verify the opaque region's bytes are identical post-edit.
  - New "composed batch of non-overlapping edits" test: batched property edits apply deterministically and the result reparses with both new values (closes Global Acceptance edit-composition gap that existed implicitly but wasn't directly tested).

**Deliberately left unfixed (out of M5.2 scope, documented in Gotchas where applicable):**
  - `WidgetTreeModel.root` is still `WidgetNode` (bare `build() => _helper()` still requires a wrap).
  - Corpus is still 10 fixtures; spec calls for 20.
  - `MethodReferenceNode.==` policy across body types is cosmetic — `StructuralEquivalence` is the official oracle, and the `==` API is documented to defer to it.
  - `applySourceEdits` is O(N·M) on `source.length × edits.count`. Within the kernel's per-edit budget for current loads.
  - Multi-class-in-one-file: parser walks the first class with a build method only. Intentional scope per the spec.
  - True multi-reference helper *support*: current opaque-degrade defense is the established soft constraint.

**Headline numbers:** 100 tests passing (up from 90), 1 documented skip. CI-grade run with 10k per-fixture iterations ≈ 14 seconds (down from ~80s — pure observation, no change in measurement methodology; round-2 didn't touch the property test inner loop). All round-2 BLOCKER + HIGH findings are fixed and tested. Round-2's stress on string escaping, validation, multi-reference defense, per-fixture iteration found no regressions, confirming the M5.1 work was durable.

**Next:** Eric reviews and ratifies M5 + M5.1 + M5.2 together. After approval the kernel is feature-complete, hardened across two review rounds, and ready to ship to the UI layer.

### [2026-05-13] M5.1 — post-review hardening: close substantive findings from the multi-agent peer review
**Worked on:** Four review subagents combed the M5-complete kernel for invariant gaps, code-quality concerns, adversarial inputs, and spec compliance divergences. This pass closes the substantive findings across seven sub-commits (`M5.1.1` … `M5.1.7`).

**Real bugs fixed (`M5.1.1` + `M5.1.2`):**
  - `PropertySerializer._escapeString` now covers `$`, `\n`, `\r`, `\t`, `\b`, and code units below U+0020 (as `\xHH`). Previously a property edit on a `Text` containing any of these produced invalid Dart.
  - `StringLiteralValue` gains `usesDoubleQuotes`; visitor captures it from `SimpleStringLiteral.isSingleQuoted`. Round-trip now preserves user quote style instead of unconditionally flipping `"…"` to `'…'`.
  - Raw (`r'...'`) and triple-quoted strings route to `OpaquePropertyValue` rather than `StringLiteralValue` (which doesn't model those surface forms).
  - `applySourceEdits` validates inputs: negative/oversized offsets, overlapping edits, and two pure inserts at the same offset all throw `ArgumentError` with a descriptive message instead of silently producing garbage.
  - `NumLiteralValue` rejects NaN/Infinity; `ColorValue` rejects negative or >32-bit values.
  - Synthetic `__positional$i` keys now share a public constant (`kPositionalOpaqueKeyPrefix`) and `WidgetSerializer` re-emits them in numeric-suffix order, interleaved with catalog-modeled positionals (not grouped or dropped). `Text('foo', 'bar')` round-trips correctly.
  - `EditPlanner.insertChildEdit` widens its `newChild` parameter from `WidgetNode` to `ModelNode` to match the model-level API.
  - Non-list expression in a list-shaped slot (`children: spread()`, `.map().toList()`) no longer synthesizes a degenerate `ListSlotStyle` pointing at arbitrary expression source. The slot is excluded from structural-edit targets.

**Comment + indent preservation (`M5.1.3`):**
  - `removeChildEdit` trims its deletion range to preserve trailing or leading comments adjacent to the removed element. Two helpers (`_trimEndBeforeComment`, `_trimStartAfterComment`) scan ONLY the separator zone between elements — never the element bytes themselves — so `//` or `/*` inside a string literal inside the element doesn't confuse the trim.
  - `_interElementSep` falls back to a default separator when the natural separator contains a comment marker, preventing duplicate comments on every inserted element.
  - Empty-multi-line-list insertion infers indent from the line containing `[` rather than hardcoding two spaces.

**Multi-reference helper defense at parse time (`M5.1.4`):**
  - The parser pre-scans the build body and each helper body for argumentless no-target invocations of in-class methods. Methods invoked more than once (including self-recursive ones) are dropped from the visitor's `classMethods` map and emit `OpaqueNode` at every call site. This closes the multi-reference soft constraint by enforcing it in code, not docs.
  - The visitor's old `_resolvingMethods` cycle defense remains as defense-in-depth (now unreachable for the self-recursive case the pre-scan catches first).
  - The cyclic-helper test was updated to expect `OpaqueNode` at the outer reference (matching the new, stricter behavior).

**Stronger tests + per-fixture iterations (`M5.1.5`):**
  - The property and structural round-trip tests now loop `iterations` times *per fixture* (was: total across the corpus). The local default is 100 per fixture (~1k total); CI's `LOOM_PROPERTY_ITERATIONS=10000` now means 10k per fixture, matching the spec's "10,000 iterations per fixture per run" gate.
  - `_randomString` includes metacharacters: `$`, `\`, `'`, `"`, `\n`, `\t`, `/`. `_generateChild` now produces nested widgets (Padding, Column with two Texts) alongside plain Text. Generated Column carries a matching `childSlotStyles` entry so the in-memory model agrees with the reparsed model on list shape.
  - `OpaqueEditException` is now actually exercised by a test that calls `withProperty` on a path descending into an opaque entry. Direct `WidgetSerializer` tests cover plain Text, const-with-trailing-comma Text, Padding+EdgeInsets+child, `OpaqueNode`, and `MethodReferenceNode`. Indirect cycle (`a → b → a`) test confirms both helpers degrade to opaque via the multi-reference defense.

**Performance benchmark (`M5.1.6`):**
  - New `test/performance_test.dart` synthesizes a >1,000-line Column-of-Text source and asserts parse <100ms / single-property-edit emission <10ms (best of 5 runs after warmup). Measured ~3–5 ms parse, sub-ms emit on the dev machine. Closes Global Acceptance #5.

**Cleanup (`M5.1.7`):**
  - Deleted `lib/src/emission/formatter.dart` and `lib/src/equivalence/ast_equivalence.dart` (TODO stubs that the Settled Decisions already obsoleted; their concerns moved to `model_equivalence.dart` and were left unimplemented in `formatter.dart`).
  - Dropped `dart_style` from `pubspec.yaml` (only ever there to power the never-implemented formatter).
  - Centralized `extractMethodReturnExpression` (was duplicated `_extractRootExpression` in `widget_tree_parser.dart` and `_extractReturnExpression` in `widget_visitor.dart`).
  - Added lint rules: `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `comment_references`. Five `prefer_const_constructors` findings on inner `StringLiteralValue`/`EdgeInsetsAllValue` constructions in tests; fixed.

**Deliberately left unfixed (out of M5.1 scope):**
  - Widening `WidgetTreeModel.root` from `WidgetNode` to `ModelNode` (the bare `build() => _helper()` case still throws `ParseException` with a documented skip).
  - Corpus growth from 10 to 20 fixtures (spec calls for "20 hand-picked real-world Flutter files"; current corpus is 10). Would require sourcing additional `flutter/samples`-style files.
  - Equality-policy unification across `ModelNode` subtypes (`WidgetNode` has no `==`; `OpaqueNode` and `MethodReferenceNode` do — `StructuralEquivalence` is the official oracle, so this is cosmetic).
  - `WidgetSerializer` named-argument alphabetical ordering (only matters for genuinely-new inserted widgets; doesn't affect round-trip correctness).
  - True multi-reference helper *support* (current defense degrades them to opaque; supporting them would require structural sharing in the model or a different update propagation strategy).

**Headline numbers:** 90 tests passing (up from 59 at M5 close), 1 documented skip. CI-grade run with 10k per-fixture iterations ≈ 80 seconds. The peer review's BLOCKER findings (string escaping, applySourceEdits validation, comment preservation, `__positional` mismatch, non-list slot synthesis) are all fixed and tested.

**Next:** Eric reviews and ratifies M5.1 alongside M5. After approval the kernel is feature-complete and hardened.

### [2026-05-13] M5 — helper-method following, kernel feature-complete
**Worked on:** Eric approved M4. Opened M5 — the last kernel milestone.
  - New sealed subtype `MethodReferenceNode { methodName, callSourceSpan, body: ModelNode }` joins `WidgetNode | OpaqueNode`.
  - `WidgetVisitor` gained a `classMethods` map (populated by `parseWidgetTree` from the enclosing `ClassDeclaration`) and a `_resolvingMethods` set for cycle detection. `convertModelNode` special-cases a `MethodInvocation` with `target == null && argumentList.arguments.isEmpty` whose method name matches an in-class method: it recursively converts the helper's return expression and wraps the result in a `MethodReferenceNode`. A cycle (helper resolving back to itself) is broken at the inner reference, which becomes an `OpaqueNode`.
  - Navigation through `MethodReferenceNode` uses a virtual `(slot: 'body', index: 0)` segment. `nodeAt`, `walk`, `_withProperty`, and `_modifySlot` all handle this case. Immutable update rebuilds the `MethodReferenceNode` with the new body but the same `methodName` and `callSourceSpan`.
  - `StructuralEquivalence` compares two `MethodReferenceNode`s by name and body (recursive equality).
  - `WidgetSerializer` re-emits `MethodReferenceNode` as `methodName()` (assumes the helper already exists — M5 doesn't synthesize helpers).
  - The CLI tree printer renders method-ref entries as `-> methodName() [call @offset+length]` and indents the body underneath.
  - Hand-crafted fixture `helper_methods.dart`: `MyPage` whose `build()` returns `Column(children: [_buildTitle(), _buildContent()])`. Each helper called exactly once (multi-reference is out of scope per the design note). Lands in the round-trip property test corpus.
  - Three M5 unit tests in `parsing_test.dart`: helper resolution to `MethodReferenceNode`; cyclic helper (helper calls itself inside a `Padding`) terminates with an inner `OpaqueNode`; and edits to a Text inside a helper produce a `SourceEdit` whose offset is in the HELPER source range, not the call site in `build()`.
**Learned:**
  - **The visitor's `_extractReturnExpression` is the same logic as the parser's `_extractRootExpression` for `MethodDeclaration` bodies.** Duplicated — 5 lines, not worth a shared utility. Just keep them in sync if either grows.
  - **Multi-reference helpers are a soft constraint, not a runtime check.** If the same helper is called from two places, two in-memory `MethodReferenceNode`s point at structurally-equivalent but distinct `body` trees. Editing one path-through-helper updates only that path's `body` in the expected model. Source-level there's only one helper definition, so the reparse picks up the change in both call sites — and the expected model wouldn't match the reparsed one. M5's fixture and acceptance both have each helper called once; if a future fixture has multi-reference, the property test would fail and surface the issue. Documented in Gotchas.
  - **The "build() that directly returns a helper call" pattern doesn't fit the current model shape.** Our `WidgetTreeModel.root: WidgetNode` requires the root to be a widget. If `build()` returns `_buildHeader()` directly, the root would be a `MethodReferenceNode` — but the model type forbids that. A wrapped variant (`return Column(children: [_buildHeader()])`) works fine. Left a documented skip in the test for the bare-helper-root pattern.
**Decided:** No new Settled Decisions. Q4 (parse errors) stays explicitly deferred — M5 doesn't depend on it either. Five of the spec's five Open Questions either ratified or explicitly deferred to a future milestone that isn't on the road map yet.
**Next:** **Eric review gate for M5 — the kernel-ships gate.** After approval the kernel is feature-complete per PROJECT_SPEC.md's milestone definitions and ready to be consumed by a UI layer. There is no M6 in the spec — the next phase is "build a UI on top of this."

### [2026-05-13] M4 — opaque blocks: real Flutter source parses without crashing
**Worked on:** Eric approved M3. Opened M4. Introduced opacity at both the model-node level and the property-value level.
  - `sealed class ModelNode` with `WidgetNode` and `OpaqueNode` subtypes. `WidgetNode.childSlots` now holds `Map<String, List<ModelNode>>` instead of `List<WidgetNode>`. Cascading refactor through visitor, serializer, equivalence, edit planner, node-path, CLI, and every test. Old `opaque_node.dart` stub was deleted — the sealed pair lives in `widget_node.dart` because Dart requires sealed subtypes in the same library.
  - `OpaquePropertyValue` joins the `PropertyValue` sealed family. Anything outside M1's literal set (closures, unmodeled constructors like `BoxDecoration`/`TextStyle`/`EdgeInsets.symmetric`, index expressions, `Theme.of(context).x` chains) now lands here instead of throwing.
  - Both opaque types carry `sourceText` in addition to `sourceSpan`, because spans shift across re-parses while content is invariant. `StructuralEquivalence` compares by `sourceText` for opaque nodes.
  - Visitor restructured: `convertModelNode(expr)` is total (returns `WidgetNode` or `OpaqueNode`); `_convertProperty(expr)` is total (returns one of the literal variants or `OpaquePropertyValue`); only `convertWidget(expr)` (used for the build-method root) can still throw `ParseException`, when the root would be opaque.
  - Path-descent into opaque content throws `OpaqueEditException`. The slot CONTAINING an opaque entry remains structurally editable — `insertChild`/`removeChild`/`moveChild` can shuffle opaque entries as opaque units.
  - Added one real-world fixture: `flutter/website` `examples/ui/widgets_intro/lib/main_mybutton.dart` (33 lines, has `GestureDetector` with closure, `BoxDecoration`, `Colors.lightGreen[500]`, `EdgeInsets.symmetric`). Existing round-trip property test suite now exercises ~100,000 edits across a corpus that includes this opaque fixture, and the byte-preservation guarantee for opaque content is implicit in the corpus passing.
**Learned:**
  - **`const Prefix.Name(args)` parses very differently from `Prefix.Name(args)`.** Without const, the analyzer gives a `MethodInvocation` with target = `Prefix`, methodName = `Name`. With const, it gives an `InstanceCreationExpression` whose `NamedType` has `importPrefix = Prefix` and `name2 = Name` — i.e., the analyzer treats `Prefix` as a possible *import prefix*, not as the type name. The visitor's `_tryExtractCall` now reads `importPrefix` and re-interprets it as the class name, so `const EdgeInsets.all(8)` lands on `_convertConstructorPropertyValue` the same way the non-const form does. Added to Gotchas.
  - **Sealed subtypes must live in the same Dart library.** I started with `sealed class ModelNode` in `opaque_node.dart` and `class WidgetNode extends ModelNode` in `widget_node.dart` — that's a compile error (`invalid_use_of_type_outside_library`). Two options: combine into one file, or use `part`/`part of`. Combined. The empty `opaque_node.dart` stub file is gone.
  - **`prefer_final_locals` flags pattern-matched variables once again.** Now in three places (property-equivalence, widget-serializer, model-equivalence's outer switch). All fixed with `final`.
  - **`__positional$i` synthetic property keys** — when a positional argument doesn't have a `positionalToProperty` entry in the catalog, the visitor captures it as `OpaquePropertyValue` under a synthetic key like `__positional0`. `WidgetSerializer` skips these synthetic keys when re-emitting (they round-trip via the opaque-byte mechanism, not via named-argument re-emission). Awkward but works.
**Decided:** Q4 (parse errors) explicitly stays deferred. M4 doesn't depend on it; if a future milestone needs syntactic-error robustness, Q4 gets ratified then.
**Next:** **Eric review gate for M4.** After approval, M5 — helper-method following. In-class `_buildHeader()` references become `MethodReferenceNode` instead of opaque, with navigation + editing across method boundaries.

### [2026-05-13] M3 — structural edits, per-list style preserved across 100,000 edits
**Worked on:** Eric approved M2. Opened M3.
  - New `ListSlotStyle` (`hasTrailingComma`, `isMultiLine`, `bracketsSpan`) in `lib/src/model/list_slot_style.dart`. `WidgetNode` gains an optional `childSlotStyles: Map<String, ListSlotStyle>` populated by the parser for list-shaped slots only.
  - Visitor takes `source` in its constructor so list-literal multi-line detection (substring scan for `\n` between `[` and `]`) works without an extra LineInfo pass.
  - `withProperty` / `insertChild` / `removeChild` / `moveChild` on `WidgetTreeModel`, immutable, via a single `_modifySlot` helper.
  - `WidgetSerializer` recursively converts a `WidgetNode` back to Dart source (positional args first by catalog index, then named alphabetically). Used by `EditPlanner.insertChildEdit` for genuinely-new children.
  - `EditPlanner.insertChildEdit` / `removeChildEdit` / `moveChildEdits`. `moveChildEdits` returns a (remove, insert) pair against the ORIGINAL source and byte-copies the moved widget's source verbatim — so internal whitespace/comments inside the moved subtree survive.
  - Round-trip stability test now has a second group: sequences of 1-10 mixed insert/remove/move per fixture, with deterministic seed `Random(0x5704C7)`. 1,000 sequences local (≈5,000 edits), 10,000 sequences in CI (≈100,000 edits), all green.
  - `model_equivalence` skips list-style comparison when both sides have an empty slot (a multi-line list contracting to `[]` is unavoidable on emptying — the comparator handles this special case rather than re-introducing multi-line emit for empty lists).
**Learned:**
  - **`withProperty` had a latent bug: it rebuilt `WidgetNode` without forwarding `childSlotStyles`.** The M2 property test caught it instantly when M3's `childSlotStyles` field went live — first iteration failed. Both `withProperty` and `_modifySlot` now thread the style map through.
  - **Move-as-(remove + insert) composes cleanly against the original source.** Because `applySourceEdits` sorts by descending offset and edits are non-overlapping, the remove and insert can be planned against the original spans simultaneously. The only subtlety is the index-shift: when `from < to`, the insert index in the original list is `to + 1` (since the removed element would have shifted `to` left by one).
  - **The inter-element separator can be read straight out of source.** For a non-empty list, `source[children[0].end..children[1].offset]` gives the exact bytes between successive elements — `, ` for single-line, `,\n  ` for multi-line. No need to synthesize. Falls back to `,\n  ` / `, ` defaults only for N=1 (one-element lists).
  - **Pattern variables again.** The model-equivalence switch arms need `final` on every bound variable (`(final StringLiteralValue a, ...)` not `(StringLiteralValue a, ...)`) under `prefer_final_locals`. Already in Gotchas from M2.
**Decided:** No new Settled Decisions this session. The empty-list-style equivalence relaxation is a comparator detail, not a spec divergence; logged in Gotchas.
**Next:** **Eric review gate for M3.** After approval, M4 — opaque blocks for unmodelable Dart (closures, ternaries, helper method calls, `.map().toList()`). Q4 (parse errors) lives there too.

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

- **The kernel's pinned `analyzer ^7.3.0` lags the SDK-bundled analyzer.** The Dart SDK (3.11.5 as of writing) ships analyzer 13.0.0 internally, which has many recent language features stable by default (e.g., dot-shorthand `.fromSeed(...)`). Our package's pinned analyzer (resolves to 7.7.1) still treats those as experimental flags. Symptom: real-world files surface false-positive "this requires the X language feature" diagnostics even though the SDK's own analyzer parses them clean. Workaround in `widget_tree_parser.dart`: `_enabledExperimentalFlags` constant lists known-needed flags and gets passed via `FeatureSet` to `parseString`. Long-term fix: bump analyzer to the same major version the SDK ships, which requires adapting the visitor to renamed AST APIs (`NamedExpression` → `Argument`, `ClassDeclaration.members` renamed, `NamedType.name2` renamed) — non-trivial but ultimately the right call.
- **Multi-reference helpers aren't supported by the property tests** as a soft constraint. If the same helper is called from two places, two in-memory `MethodReferenceNode`s point at structurally-equivalent but distinct `body` trees. The expected model from `withProperty(path_through_one_ref, …)` only updates that path's body; the reparsed model picks up the helper-source change in BOTH call sites. The two models would diverge, and the property test would fail. M5's `helper_methods.dart` fixture has each helper called exactly once; adding multi-reference fixtures requires either propagating the in-memory edit to all references with the same name, or weakening the equivalence comparator. Out of scope for M5.
- **`MethodReferenceNode` requires path navigation through a *virtual* slot named `body`.** It's not a real `childSlots` entry — `MethodReferenceNode` doesn't have `childSlots` — but `nodeAt`, `walk`, `_withProperty`, and `_modifySlot` all special-case it. New ModelNode subtypes need this same audit.
- **`const Prefix.Name(args)` and `Prefix.Name(args)` produce different analyzer ASTs.** Non-const: `MethodInvocation(target=Prefix, methodName=Name)`. Const: `InstanceCreationExpression` with `NamedType.importPrefix = Prefix` and `NamedType.name2 = Name` (the analyzer treats `Prefix` as a possible import prefix, since without resolution that's a valid reading). The visitor's `_tryExtractCall` reads `importPrefix` and re-interprets it as the class name. Without this, `const EdgeInsets.all(8)` falls through to `OpaquePropertyValue` despite being a fully modelable expression.
- **Sealed subtypes need to live in the same Dart library** (= same `.dart` file, unless `part`/`part of` is used). I started with `sealed class ModelNode` in `opaque_node.dart` and `WidgetNode extends ModelNode` in `widget_node.dart` — compile error `invalid_use_of_type_outside_library`. Combined into a single `widget_node.dart`. Future spec-shaped file splits will need to consider this if they refactor sealed hierarchies.
- **When a `WidgetNode` field is added, all the immutable-update paths must forward it.** M3 added `childSlotStyles`. `withProperty` was missed and silently dropped the new field, which only surfaced when M2's property test rebuilt nodes via `withProperty` and compared against the reparsed (style-bearing) model. `_modifySlot` and any future structural-update path needs the same audit.
- **An empty list comparison needs a style exemption.** A multi-line `[\n  a,\n]` contracts to a single-line `[]` when the only element is removed. The reparsed model honestly reports `isMultiLine=false` while the in-memory pre-edit model still claims `isMultiLine=true`. `model_equivalence` skips style comparison when both sides have an empty slot for that key — preferable to introducing an "empty multi-line" emit shape that no real Dart uses.
- **Hand-crafted fixtures are insufficient design pressure.** The single-fixture M1 first pass shipped a single-children-slot `WidgetNode` because no fixture demanded otherwise. The first real-world fixture (`Scaffold(body:, appBar:)`) immediately broke that assumption and forced a multi-slot refactor. Future milestones should pull at least one corpus fixture into the design phase before locking the model.
- **`parseString` does not resolve types, so constructor calls without `const`/`new` come back as `MethodInvocation`, not `InstanceCreationExpression`.** This is the canonical shape: `Column(...)` → `MethodInvocation(methodName=Column)`; `const Column(...)` → `InstanceCreationExpression`. Similarly `EdgeInsets.all(8.0)` → `MethodInvocation(target=EdgeInsets, methodName=all)`. The widget visitor normalizes both AST shapes through `_CallInfo` in `lib/src/parsing/widget_visitor.dart`. If we ever switch to a resolved analyzer context (e.g. for cross-file work in M5+), this normalization can collapse to just the `InstanceCreationExpression` path.
- **`test/fixtures/**` is excluded from `dart analyze`.** Fixtures are Flutter source files we parse from a string at test time. They reference packages (Flutter) Loom deliberately does not depend on, so `dart analyze` would flood with `uri_does_not_exist` and `undefined_class` errors. The exclusion lives in `analysis_options.yaml`. If you add a new fixture directory, exclude it the same way.
- **analyzer 6.5.0–7.2.x are broken on current Dart SDKs.** They pull in `package:macros` which depends on `_macros` from the SDK, which the SDK no longer ships. Use `analyzer: ^7.3.0` (and `dart_style: ^3.0.0` so it picks a compatible analyzer). If you see a `version solving failed` error mentioning `_macros 0.x.y from sdk`, this is what you're looking at.

---

## References Consulted

Things read during the work that turned out useful. Helps future sessions avoid re-discovering the same resources.

- _(none yet)_
