# DEVLOG — Loom

Running record of decisions, milestone progress, and lessons learned for the Loom kernel. Exists so future sessions — human and AI — can pick up without re-litigating settled questions.

**Update protocol:** every working session ends with at least one entry in the Session Log. Entries are append-only; corrections go in new entries that reference the original. Never edit history. The Current State block at the top is the only section that gets rewritten in place.

---

## Current State

**Active milestone:** M7.5 — qualifier editing (M7 complete)
**Last touched:** 2026-05-14 — deepened class-structure further by modeling individual parameters within method/constructor parameter lists, and by capturing annotations on class members + classes themselves.

**Parameter modeling** — replaces M7.1's `parametersSource: String` blob:
- `ClassParameterNode` — name, type, default value (each with span), `isRequired` / `isNamed` / `isPositional` / `isOptional` / `isThis` / `isSuper` / `isFinal` / `isConst` flags, plus the parameter's own annotations.
- Both `ClassMethodNode` and `ClassConstructorNode` now expose a `parameters` list. The raw `parametersSource` is kept alongside for backward compat and for callers who want the verbatim text.

**Annotation modeling** — new `AnnotationNode`:
- Captures name (`'override'` / `'JsonKey'` / `'freezed'`), arguments source (`'(name: \'x\')'` or null for bare `@override`), plus spans.
- Available on every `ClassMember` (field / method / constructor / opaque) AND on `ClassStructureNode` itself AND on each `ClassParameterNode`.
- M7.2 captures only; edit operations on annotations are deferred to M7.3+.

**Edit-planner additions:**
- `renameParameter` — replace parameter name span
- `changeParameterType` — replace type span (requires existing type)
- `changeParameterDefault` — replace default value span (requires existing default)

Parameter add/remove are deliberately deferred — they require placement logic for positional vs `[optional]` vs `{named}` sections plus comma + bracket handling. M7.2.1 territory.

**New fixture:** `class_freezed_like.dart` — synthetic Freezed/json_serializable shape with `@freezed` class annotation, `@JsonKey(name: '…')` field annotations, and a factory constructor with `required`/`this.x`/default-value parameters. Doesn't depend on Freezed at runtime; just exercises the shape.

**Validation:** 210 tests green (202 → 210, +8 new across parsing + round-trip). dart analyze + dart format clean. Scout against flutter/packages/go_router (117 files): identical to M7.1 — 0 crashes, 0 idempotence failures, 78 class-structure clean parses. Same files parse; we capture more inside each.

CLI updated: `loom parse` on class-structure files now prints class-level annotations + member-level annotations inline.

**M7.5 surface added (just now):**

Model surgery: added 10 nullable `SourceSpan?` keyword-span fields across the class-structure node types.
- `ClassFieldNode`: `finalKeywordSpan`, `varKeywordSpan`, `lateKeywordSpan`, `staticKeywordSpan`
- `ClassMethodNode`: `staticKeywordSpan`
- `ClassConstructorNode`: `constKeywordSpan`, `factoryKeywordSpan`
- `ClassParameterNode`: `requiredKeywordSpan`, `finalKeywordSpan`, `constKeywordSpan`

Parser updates capture each from analyzer 13's `Token?` accessors (`fields.keyword`, `fields.lateKeyword`, `member.staticKeyword`, `modifierKeyword`, `constKeyword`, `factoryKeyword`, `requiredKeyword`, `finalKeyword`).

16 add/remove qualifier operations on `ClassStructureEditPlanner`:
- Field: `addFieldFinal` (handles var→final replacement) / `removeFieldFinal`; `addFieldLate` / `removeFieldLate`; `addFieldStatic` / `removeFieldStatic`
- Method: `addMethodStatic` / `removeMethodStatic`
- Constructor: `addConstructorConst` / `removeConstructorConst`; `addConstructorFactory` / `removeConstructorFactory`
- Parameter: `addParameterRequired` (named-only) / `removeParameterRequired`; `addParameterFinal` / `removeParameterFinal`

Canonical insertion order is respected: e.g. `addFieldFinal` on a field with existing `static late` lands `final` AFTER `late`, producing the conventional `static late final` sequence. Insertion uses a `_qualifierInsertionPoint` helper that walks past annotations and any present preceding qualifiers (in canonical order) before placing the new keyword. Removal uses `_removeKeyword` which deletes the keyword span plus trailing whitespace through the next non-whitespace byte.

**The M7 series is now functionally complete** for class-structure editing:
- M7.0 fields, M7.1 methods + constructors, M7.2 parameters + annotations, M7.2.1 parameter add/remove, M7.3 annotation editing, M7.4 section creation + bracket cleanup + bare-annotation args + ctor rename, M7.5 qualifier editing.

Together, the M7 family covers every edit a Freezed / json_serializable / Drift table tooling layer would normally need.

Truly long-tail items remaining (ship ad-hoc only if real fixtures demand):
- Adding a type annotation to an untyped field or parameter
- Adding an initializer to a bare field
- Adding a default value to a parameter without one
- Converting an unnamed constructor into a named one
- Multi-variable field declarations beyond best-effort
- Reordering members

**Blockers:** none
**Next action:** **Eric review gate for the full M6 + M7 series** (16 commits since the last review gate, all the major work to make Loom usable for OutSystems-style entity + DSL modeling). Then **M8 — function-body / statement modeling**, the next genuinely new shape after constructor trees, flat member lists, and complete class structure.

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

### M6.0 — Non-Flutter Dart layer (first slice: route DSL)

- [x] Sealed `RouteTreeNode` hierarchy added: `RouteNode | RouteOpaqueNode | RouteMethodReferenceNode`
- [x] `RouteTreeModel` parallel to `WidgetTreeModel` (root + diagnostics list)
- [x] `RouteCatalog` covers `GoRouter`, `GoRoute`, `ShellRoute` (each with `routes:` list slot)
- [x] `parseRouteTree(String source)` locates routes via top-level variable initializer (primary path) or class-method return (fallback)
- [x] `RouteVisitor` adapts the widget-side traversal: same scaffolding minus widget-only property kinds (EdgeInsets / Color)
- [x] Function-literal arguments (e.g. `builder:`) flow through `OpaquePropertyValue` (reused unchanged)
- [x] In-class helper-method resolution wired (4th fixture exercises `routes: [_homeRoute()]`)
- [x] `RouteEditPlanner` covers property / insert / remove / move edits scoped to `RouteNode`
- [x] CLI `loom parse <file>` auto-detects widget vs route trees
- [x] Scout extended to dual-mode parser detection; per-file outcome reporting
- [x] 4 fixtures (`route_simple`, `route_nested`, `route_shell`, `route_with_helper`) + 23 tests
- [x] Round-trip invariant 1 holds on routes: property edit, insert, remove, move all re-parse cleanly
- [x] Round-trip invariant 2 holds on routes: `apply([], source) == source` byte-exact
- [x] Real-world scout: 1,274 files (loom + lowcode-flutter + flutter/examples), 0 crashes, 0 idempotence failures
- [ ] **Gate**: reviewed by Eric before M6.1 begins

---

## M6 roadmap — toward OutSystems-for-Dart/Flutter

The user explicitly asked the M6 plan to capture "everything we would need to build to support everything." M6.0 shipped the first slice; the roadmap below sequences the remaining work.

| Milestone | Deliverable | Why |
|---|---|---|
| **M6.0** (shipped 2026-05-14) | First non-widget catalog: route DSL (GoRouter-shaped). Same constructor-tree shape as widgets. | Forcing function: a second consumer of the kernel. |
| **M6.1** (shipped 2026-05-14) | Extracted shared scaffolding in three phases: (1) unified sealed `ModelNode` hierarchy (Route node types collapsed into shared `OpaqueNode` / `MethodReferenceNode`); (2) `BaseVisitor` abstract class with three domain hooks; (3) `ListEditHelpers` for byte-level slot edits + `RouteSerializer` sibling of `WidgetSerializer`. Each visitor / edit-planner now ~50–100 lines instead of ~300–450. | Made the kernel genuinely reusable for a third domain — M6.2's next catalog needs ~50 lines, not a copy of the scaffolding. |
| **M6.2** (shipped 2026-05-14) | Third domain catalog: synthetic Pipeline DSL (Pipeline / Branch / ValidateInput / Transform / SaveToDatabase / SendEmail / LogError / LogInfo). Invented for the demo, representative of OutSystems-style declarative workflows. Adding the third domain revealed a hidden duplication in the per-domain serializers (the constructor-call serialization was ~100 lines of identical code in two places); extracted as `ConstructorCallSerializer`. | Validated M6.1's scaffolding actually plugs in a third domain — non-shared per-domain code is ~250 LOC total. The literal M6.2 options from the original plan (test framework, MaterialApp configs, Shelf cascades) turned out to be poor fits for "constructor-tree catalog" (test bodies live in function literals, MaterialApp is already a widget, Shelf is a cascade — different shape). Pipeline DSL is the cleanest demonstration of the OutSystems trajectory. |
| **M7.0** (shipped 2026-05-14) | Class-structure modeling — **fields only**, first slice. Parse a class's field declarations; methods + constructors stay opaque. Separate sealed hierarchy from constructor-tree `ModelNode` (different shape: flat list of members vs. tree of expressions). Five edit operations: rename / changeType / changeInitializer / remove / addField. ~600 LOC new. | OutSystems-style entity modeling for Drift tables, Freezed unions, json_serializable classes — most of those are field-shaped. |
| **M7.1** (shipped 2026-05-14) | Method signatures + constructors. Sealed `ClassMember = ClassFieldNode | ClassMethodNode | ClassConstructorNode | OpaqueClassMember`. Edit ops added: renameMethod, changeMethodReturnType, removeMember (polymorphic), addMember (polymorphic). Backward-compat `fields` / `opaqueMemberSpans` getters keep M7.0 callers working. | Methods + constructors are the rest of "class shape" — together with M7.0's fields, this covers virtually all real-world class members. |
| **M7.2** (shipped 2026-05-14) | Parameter modeling + annotation capture. `ClassParameterNode` (name / type / default / kind flags) replaces M7.1's `parametersSource` blob. `AnnotationNode` attached to members, parameters, and `ClassStructureNode` itself. Edit ops added: renameParameter, changeParameterType, changeParameterDefault. New fixture `class_freezed_like.dart` exercises the Freezed/json_serializable shape. | Unlocks Freezed-style entity editing where "fields" are actually factory-constructor parameters. Captures the annotations that codegen pipelines key off. |
| **M7.2.1** (shipped 2026-05-14) | Parameter add/remove. `appendParameter` to existing section (creates within empty `positionalRequired` if other sections exist; throws on empty `named`/`positionalOptional` for now). `removeParameter` handles intra-section deletion with separator cleanup, leaves empty brackets behind. | The "add a field" / "remove a field" operations for Freezed-style entities where fields-as-params is the modeling layer. |
| **M7.3** (shipped 2026-05-14) | Annotation editing. `addClassAnnotation`, `addMemberAnnotation`, `addParameterAnnotation` (each with appropriate formatting — newline for class/member, inline for parameter). `removeAnnotation` cleans up trailing whitespace/newline. `replaceAnnotationArguments` swaps the `(...)` portion. | Codegen-driven entity classes (Freezed / json_serializable / Drift) live and die by their annotations. This makes them first-class editable. |
| **M7.4** (shipped 2026-05-14) | Closing M7 gaps. `appendParameter` now creates `{}` / `[]` sections when needed; `removeParameter(parameter, source, parent)` drains empty sections; `replaceAnnotationArguments` now inserts on bare annotations; `renameNamedConstructor` replaces the `.named` segment. | Most M7 edits land cleanly without ad-hoc workarounds. |
| **M7.5** (shipped 2026-05-14) | Qualifier editing. Added 10 keyword-span fields across the class-structure node types; 16 add/remove operations covering field final/late/static, method static, ctor const/factory, parameter required/final. Insertion respects canonical ordering. M7 is now feature-complete for class-structure editing. | Closes the entity-modeling surface — toggling `static`, `late`, `final`, `required` etc. is a common need for Freezed / json_serializable / Drift tooling. |
| Future M7.x | Ad-hoc additions only if real fixtures demand: adding type to untyped fields/params, adding initializer to bare fields, adding default to bare params, unnamed→named ctor conversion, multi-variable field decls beyond best-effort, member reordering. | Long-tail edge cases. |
| **M8** | Function-body / statement modeling — variable decls, assignments, calls, control flow inside a method. Dozens of statement kinds; probably multi-milestone. | OutSystems-style business logic: visual workflows that compile to Dart functions. |
| M9 | Cross-file modeling — imports / exports, multi-file project view. | Required for "see the whole app" visual editing. |
| M10+ | Reference / type analysis, codegen-aware editing (`json_serializable` annotations, Drift schema → table classes, etc.). | Resolves named symbols across files; understands codegen output. |

The bet: **M6.0 alone doesn't unlock OutSystems-for-Dart — the kernel generalization does.** Every milestone above re-uses the same source-span / source-edit / round-trip core, and M6.0 is the cheapest way to prove that core actually generalizes.

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

### Class-structure fixtures (M7.0)

The first non-tree-shaped model. Validates the kernel handles flat lists of class members alongside the constructor-tree DSLs.

| File | Source | Lines | Exercises |
|---|---|---|---|
| `test/fixtures/class_simple.dart` | hand-crafted | 6 | Four fields with varied qualifiers: `final String`, `final int`, nullable `String?`, `late final DateTime`. No methods/constructors. |
| `test/fixtures/class_with_methods.dart` | hand-crafted | 14 | Class with both fields and non-field members — constructor, getter, instance method, static const field. M7.0 captured opaque spans; M7.1 captures the methods + constructor as modeled nodes. |
| `test/fixtures/class_with_constructors.dart` | hand-crafted | 22 | M7.1: four constructor shapes — const default, const named with initializer list, factory with body, factory redirecting `= Money;`. Plus operator overload (`operator +`) and override method (`toString`). |
| `test/fixtures/class_freezed_like.dart` | hand-crafted | 21 | M7.2: synthetic Freezed/json_serializable shape. Class-level `@freezed` annotation, `@JsonKey(name: '…')` field annotations, factory constructor with `required`/`this.x`/default-value parameters. Validates annotation capture + parameter modeling without depending on Freezed at runtime. |

### Pipeline fixtures (M6.2)

Synthetic data-pipeline / workflow DSL — invented for the demo. Validates the kernel's third-domain reusability after the M6.1 scaffolding extraction.

| File | Source | Lines | Exercises |
|---|---|---|---|
| `test/fixtures/pipeline_simple.dart` | hand-crafted | 11 | Top-level `final pipeline = Pipeline(name, steps: [ValidateInput, Transform, SaveToDatabase])`. Bool property (`required: true`). |
| `test/fixtures/pipeline_with_branch.dart` | hand-crafted | 21 | Branch node with two list slots (`onTrue` / `onFalse`); demonstrates a node with multiple list-shaped child slots. |

### Route fixtures (M6.0 / M6.0.1)

A separate corpus for the route-DSL upper layer. Each exercises the route parser + visitor + edit planner.

| File | Source | Lines | Exercises |
|---|---|---|---|
| `test/fixtures/route_simple.dart` | hand-crafted | 9 | Flat router: top-level `final router = GoRouter(initialLocation, routes: [GoRoute×2])`. Primary entry-point shape. |
| `test/fixtures/route_nested.dart` | hand-crafted | 15 | Parent GoRoute with two child GoRoutes; tests nested `routes:` slots. |
| `test/fixtures/route_shell.dart` | hand-crafted | 13 | ShellRoute wrapping two GoRoutes; sibling top-level GoRoute. |
| `test/fixtures/route_with_helper.dart` | hand-crafted | 16 | Class-method fallback entry point + `routes: [_homeRoute()]` resolving to `RouteMethodReferenceNode`. |
| `test/fixtures/real_world_go_router_main.dart` | flutter/packages @ `0ffbde8f`, `packages/go_router/example/lib/main.dart` | 86 | Canonical go_router example: top-level `final GoRouter _router = GoRouter(...)`, typed list literal `<RouteBase>[...]`, nested GoRoute with `builder:` function literals (→ opaque), MaterialApp.router widget tree alongside. |
| `test/fixtures/real_world_go_router_named_routes.dart` | flutter/packages @ `0ffbde8f`, `packages/go_router/example/lib/named_routes.dart` | 190 | M6.0.1 class-field entry-point: `late final GoRouter _router = GoRouter(...)` inside `class App`. Triple-nested GoRoutes; `name:` properties; `debugLogDiagnostics: true` (BoolLiteralValue); typed list literals `<GoRoute>[...]`. |

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

### [2026-05-14] M7.5 — qualifier editing (M7 feature-complete)
**Worked on:** Last of the M7 series. Adds 16 qualifier add/remove operations covering field `final`/`late`/`static`, method `static`, constructor `const`/`factory`, and parameter `required`/`final`. Required model surgery to capture keyword spans (10 new nullable `SourceSpan?` fields across 4 node types).

**Surface added:**

| Target | Operations |
|---|---|
| Field | `addFieldFinal`/`removeFieldFinal`, `addFieldLate`/`removeFieldLate`, `addFieldStatic`/`removeFieldStatic` (6) |
| Method | `addMethodStatic`/`removeMethodStatic` (2) |
| Constructor | `addConstructorConst`/`removeConstructorConst`, `addConstructorFactory`/`removeConstructorFactory` (4) |
| Parameter | `addParameterRequired`/`removeParameterRequired`, `addParameterFinal`/`removeParameterFinal` (4) |

**Canonical insertion order respected.** Helper `_qualifierInsertionPoint` walks past annotations and present preceding qualifiers in canonical order before placing the new keyword. So `addFieldFinal` on `static late int x;` lands at the position between `late` and `int`, producing `static late final int x;`. Without that helper the new keyword would land at the start, producing the non-canonical `final static late int x;` (which parses but `dart format` would reorder).

**`addFieldFinal` handles the var→final replacement case.** A `var x;` field has `varKeywordSpan` populated; addFieldFinal replaces the `var` token with `final` rather than inserting a second qualifier. Symmetric with how Dart treats `final` and `var` as mutually exclusive.

**Removal is uniform.** All `remove*` ops delete the keyword token + trailing whitespace through the next non-whitespace byte. Captured by `_removeKeyword` helper. This keeps spacing tight without leaving double-spaces.

**Precondition checking:** every add operation throws `ArgumentError` if the qualifier is already present. Every remove operation throws if the qualifier is absent. Caller checks current state via the existing bool flags (`field.isFinal`, etc.) before calling. The thrown errors include clear messages identifying which member and which qualifier.

**Edge cases handled:**
- `addParameterRequired` only works on named parameters (positional are implicitly required). Throws clear error on positional.
- `addParameterFinal` throws if the parameter is `const` (mutually exclusive).
- `addFieldFinal` on a `var` field replaces the keyword; on a bare field inserts new.

**Validation:**
- 246 tests green (was 231, +15 new across all qualifier ops).
- `dart analyze` and `dart format` clean.
- Scout against `flutter/packages/go_router` (117 files): unchanged — 0 crashes, 0 idempotence failures, 78 class clean parses.

**Decision retrospective:** I initially flagged qualifier editing as "M7.5 if real fixtures demand" because it required model surgery. Eric chose to do it anyway for closure. The work took ~1 hour and produced a meaningfully more complete kernel. Closing the M7 chapter cleanly is worth the upfront investment — entity-modeling tooling can now toggle ANY qualifier through the kernel without raw source manipulation.

**M7 family is now feature-complete** (6 commits):
- M7.0: fields
- M7.1: + methods + constructors
- M7.2: + parameter modeling + annotation capture (renameParameter, changeParameterType, changeParameterDefault)
- M7.2.1: + parameter add/remove with section awareness
- M7.3: + annotation editing
- M7.4: + section creation, bracket cleanup, bare-annotation args, ctor rename
- M7.5: + qualifier editing

**Truly long-tail items remaining** (would ship ad-hoc only if real fixtures demand):
- Adding a type annotation to an untyped field or parameter (rare)
- Adding an initializer to a bare field (rare)
- Adding a default value to a parameter without one (rare)
- Converting an unnamed constructor into a named one (rare)
- Multi-variable field declarations beyond best-effort
- Reordering class members

**Next:** Eric review gate for the entire M6 + M7 series (16 commits total — substantial). Then M8 — function-body / statement modeling, the next genuinely new shape. Constructor trees, flat member lists, and complete class structure are all in the kernel; M8 takes on the inside of methods, the place where business logic lives.

### [2026-05-14] M7.4 — closing M7 gaps (section creation, bracket cleanup, bare-annotation args, ctor rename)
**Worked on:** Eric asked to "finish up any M7 gaps in one go, if possible." Surveyed the still-deferred list across M7.0 / M7.1 / M7.2 / M7.2.1 / M7.3 entries. Four gaps were genuinely closable without model surgery; one (qualifier editing) requires capturing keyword spans on `ClassFieldNode` / `ClassMethodNode` / `ClassConstructorNode` / `ClassParameterNode` and is deferred to M7.5.

**Four operations:**

1. **Section creation in `appendParameter`.** Previously threw when the target section (`named` or `positionalOptional`) was empty. Now inserts the `{newParam}` / `[newParam]` brackets and prefixes with `, ` if positional params precede.
   - Edge case: empty list `()` → wraps newParam in brackets directly inside `(...)`.
   - Edge case: only positional params → inserts after the last positional with `, ` separator.

2. **Empty-section bracket cleanup in `removeParameter`.** Added optional `parent` parameter (M7.2.1's signature kept `parameter` + `source` only). When `parent` is supplied AND the removed param is the SOLE member of its named/optional-positional section, the deletion extends back through the section brackets AND any preceding `, ` separator.
   - No behavior change for callers that don't pass `parent` — intra-section deletion still leaves empty brackets behind.
   - Algorithm: walk backward from `parameter.offset` through whitespace to find `{`/`[` opener; walk forward through optional trailing `,` + whitespace to find `}`/`]` closer; extend back through preceding `, ` separator if any.

3. **`replaceAnnotationArguments` for bare annotations.** Previously threw on bare `@override` (no parens to replace). Now INSERTS the new arguments after the annotation name. Symmetric with the existing replace-when-args-exist path; just two cases in the same function.

4. **`renameNamedConstructor`.** Replaces `ctor.namedConstructorSpan`. Throws on unnamed constructors (converting unnamed → named requires inserting the `.` separator, deferred).

**Validation:**
- 231 tests green (was 225, +6 new — 3 section-creation, 2 section-drain, 1 bare-annotation, 1 ctor rename + 1 negative case for unnamed-ctor).
- Two M7.2.1 / M7.3 tests that previously asserted `throws` were updated since M7.4 implements the formerly-deferred behavior.
- `dart analyze` and `dart format` clean.
- Scout against `flutter/packages/go_router` (117 files): unchanged — 0 crashes, 0 idempotence failures, 78 class clean parses.

**Decision: qualifier editing deferred to M7.5.** It needs keyword spans on every relevant node type (ClassFieldNode for `final`/`var`/`late`/`static`, ClassMethodNode for `static`, ClassConstructorNode for `const`/`factory`, ClassParameterNode for `required`/`final`/`const`). That's substantive model surgery — adding 4-5 nullable `SourceSpan` fields across four node classes and updating the parser to populate them. Not hard, just bigger than the rest of M7.4. Ships as M7.5 if real fixtures demand qualifier toggles.

**Other deferrals (the genuine "long tail" of M7 — each rare in real code):**
- Adding a type annotation to an untyped field or parameter
- Adding an initializer to a bare field
- Adding a default value to a parameter without one
- Converting an unnamed constructor into a named one
- Multi-variable field declarations beyond best-effort
- Reordering members

These are all token-insertion edits with separator handling. Each is small; together they'd bloat the surface. Will ship ad-hoc when real-world consumers ask for them.

**M7 series summary** (six commits across this session):
- M7.0: fields only
- M7.1: + methods + constructors
- M7.2: + parameter modeling + annotation capture
- M7.2.1: + parameter add/remove
- M7.3: + annotation editing
- M7.4: + section creation, bracket cleanup, bare-annotation args, ctor rename

The kernel now has functionally complete class-structure editing for the common entity-modeling workflows: Freezed-shaped classes, json_serializable-shaped classes, Drift tables (modeled as class-with-getters). Real-world entity files can be inspected and edited end-to-end through the kernel without raw source manipulation.

**Next:** Eric review of the full M6 + M7 series (substantial — ~14 commits since the last review gate). Then M8 (function-body / statement modeling — the next genuinely new shape after constructor trees, flat member lists, and now-complete class structure).

### [2026-05-14] M7.3 — annotation edit operations
**Worked on:** Completed the annotation surface — M7.2 captured them; M7.3 makes them editable. Together this closes the loop on entity-modeling needs: codegen-driven classes (Freezed / json_serializable / Drift) can now be inspected AND modified through the kernel without raw source manipulation.

**Five new operations:**
- `addClassAnnotation(parent, annotationSource, source)` — prepend before class decl, newline + class indent.
- `addMemberAnnotation(member, annotationSource, source)` — prepend before any class member, newline + member indent.
- `addParameterAnnotation(parameter, annotationSource)` — inline before parameter, single-space separator (most common Dart style; multi-line parameter annotations can use `addParameterAnnotation` then manual reformat).
- `removeAnnotation(annotation, source)` — delete annotation source + trailing horizontal whitespace + up to one newline. Same line-collapse pattern as `removeMember`.
- `replaceAnnotationArguments(annotation, newArgumentsSource)` — replace just the `(...)` portion. Requires existing arguments list (adding parens to a bare annotation needs insertion logic deferred to a future milestone).

**Three placement strategies for `add*Annotation`:**
| Target | Style | Reason |
|---|---|---|
| Class | `@Anno\n<indent>` | Annotations on their own line is the universal class convention |
| Member | `@Anno\n<indent>` | Same — `@override\n  String foo()` |
| Parameter | `@Anno ` | Inline is the most common parameter-annotation style (`@JsonKey() String name`) — multi-line parameter annotations exist but are rarer |

**Validation:**
- 225 tests green (was 218, +7 new annotation tests).
- `dart analyze` and `dart format` clean.
- Scout against `flutter/packages/go_router` (117 files): unchanged — 0 crashes, 0 idempotence failures, 78 class clean parses.

**Learned:**
- **Annotation edits are mostly span replacements.** All five operations end up being plain `SourceEdit` calls with computed offsets — no scaffolding, no helpers needed. The interesting work is positioning (where to insert before what, with what surrounding whitespace).
- **Indentation inference works the same way for any "prepend before declaration" operation.** Reusing the `_lineIndentBefore` helper that started in M7.0's `addField` works fine for class-level and member-level annotations. Three current users of that helper inside `ClassStructureEditPlanner` and one in `ListEditHelpers` — the "rule of three" extraction trigger from M7.1's DEVLOG note has now fired but the helper is still duplicated across files. Worth doing as a small cleanup in a future commit.
- **The OutSystems-for-Dart trajectory now has a clear "entity modeling" working surface.** M7.0 + M7.1 + M7.2 + M7.2.1 + M7.3 together let a downstream tool fully manage a Freezed-shaped class — add/remove/rename/retype fields (via factory params), edit annotations, manage method signatures, manage constructors. The same machinery works for json_serializable, Drift columns (as getter-methods), and similar codegen targets.

**Next:** Eric review of the full M6 + M7 series (10 commits since the last review gate). Then M8 (function-body / statement modeling — the next genuinely new shape after constructor trees and class member lists) or fill in remaining M7 gaps as concrete fixtures demand.

### [2026-05-14] M7.2.1 — parameter add/remove
**Worked on:** Completed the parameter editing surface started in M7.2. Add and remove operations handle the cases the M7.2 commit deferred: section-aware insertion at end of an existing section, deletion with separator + (some) bracket awareness.

**`ParameterSection` enum:** `positionalRequired` | `positionalOptional` | `named`. Maps to the three logical sections of a Dart parameter list. The optional-positional (`[...]`) and named (`{...}`) sections are mutually exclusive in any given list, but both can coexist with required positional.

**`appendParameter(parent, newParameterSource, section, source):`**
- Common path: section is non-empty. Find the last param in that section, insert after it with detected separator.
- `positionalRequired` is empty AND list is `()`: insert just after `(`.
- `positionalRequired` is empty AND list has other sections (`({named: 1})`): insert `newParam, ` BEFORE the `{` / `[` opener.
- `named` or `positionalOptional` is empty: throws. Section creation requires inserting `{...}` / `[...]` brackets + the `, ` separator and is deferred to M7.2.2.

Separator detection looks at the gap between two adjacent params if available, else heuristically picks `,\n<indent>` for multi-line or `, ` for single-line lists. Skips natural-separator adoption if the gap contains `//` or `/*` (would duplicate comments on every insert).

**`removeParameter(parameter, source):`** generic intra-section deletion.
- Back-walks for a preceding `,` (through whitespace): if found, deletion includes that `, ...` separator → deletes preceding-separator + param.
- If no preceding `,` (param is first overall, OR first in a section with no required-positional precursors): forward-walks through `,` + whitespace from `param.end`. Stops at section openers (`[`/`{`) so the brackets stay intact.
- Empty-section bracket cleanup is deferred (M7.2.2).

**Edge cases verified by tests:**
- Middle of multi-line named section: clean removal.
- First named in multi-line list (with no positionals): just deletes the param + following `,` and whitespace, leaving the `{}` open at the start of the named section.
- Sole parameter: just deletes the param itself; surrounding parens / brackets remain.
- Append throws on getter (no parameter list) — properly rejected.
- Append throws on empty `named` section — clear error message about deferral.

**Validation:**
- 218 tests green (was 210, +8 new on parameter add/remove).
- `dart analyze` and `dart format` clean.
- Scout against `flutter/packages/go_router` (117 files): unchanged — 0 crashes, 0 idempotence failures, 78 class clean parses. M7.2.1 is edit-only; doesn't change which files parse.

**Learned:**
- **The "first param in list / first in section but not list" distinction is naturally handled by walking source for `,`.** I'd initially worried about needing a section-position concept; the back-walk through whitespace + `,` does the right thing without needing section state.
- **Bracket-cleanup is the genuinely hard part.** Removing `{a}` to get `()` requires removing the `{}` AND the preceding `, ` separator. Removing `[a]` similarly. The current M7.2.1 implementation deliberately leaves empty `{}` / `[]` behind — they re-parse fine, just look ugly. M7.2.2 can clean up.

**Next:** M7.3 (annotation editing) — next commit in this session.

### [2026-05-14] M7.2 — parameter modeling + annotation capture
**Worked on:** Deepened class-structure further by modeling individual parameters within method/constructor parameter lists (replacing M7.1's `parametersSource: String` blob) and by capturing annotations on every modeled scope — class, member, parameter.

**Parameter modeling:**
- `ClassParameterNode` captures name, type, default value (each with span), plus `isRequired` / `isNamed` / `isPositional` / `isOptional` / `isThis` / `isSuper` / `isFinal` / `isConst` flags and per-parameter annotations.
- Both `ClassMethodNode` and `ClassConstructorNode` expose a `parameters: List<ClassParameterNode>` list.
- The raw `parametersSource` is kept alongside for backward compat — callers who just want the verbatim parameter list text still get it; callers who want individual editing get the structured list.

**Annotation modeling:**
- New `AnnotationNode` captures name (`'override'`, `'JsonKey'`, `'freezed'`, etc.), arguments source (`'(name: \'x\')'`, `null` for bare `@override`), plus spans.
- Surfaced on: `ClassMember.annotations` (all four concrete subtypes), `ClassStructureNode.annotations` (class-level), `ClassParameterNode.annotations`.
- M7.2 is capture-only; annotation edit operations are M7.3+.

**Edit-planner additions (parameter ops only — see deferred list):**
- `renameParameter(parameter, newName)`
- `changeParameterType(parameter, newType)` — requires existing type
- `changeParameterDefault(parameter, newDefaultSource)` — requires existing default

Parameter add/remove deliberately deferred to M7.2.1. Adding a parameter requires placement logic: which section does it belong in (required positional / `[optional positional]` / `{named}`), what's the separator pattern, does the existing list have a trailing comma, are the section-delimiter brackets present. Removal has the same complexity in reverse plus an edge case for removing the last named param (do we drop the `{}`?). All solvable; just not for this slice.

**Analyzer 13 surface niceties:**
- `FormalParameter` base type exposes `name`, `type`, `defaultClause`, plus `isRequired` / `isNamed` / `isPositional` / `isOptional` flags directly. The DefaultFormalParameter wrapper from older analyzers is gone — all parameter kinds (regular, field-formal `this.x`, super-formal `super.x`) share the same base API with subtype-only differences for the `this.`/`super.` discrimination.
- `Annotation.name` is an `Identifier` (handles prefixed annotations like `@meta.required`); using `name.toSource()` (or substring of source) gives the full dotted text.
- `AnnotatedNode` interface adds `metadata: NodeList<Annotation>` uniformly to `ClassDeclaration`, every `ClassMember` subtype, and every `FormalParameter` — one capture helper handles all three.

**Fixture:** `test/fixtures/class_freezed_like.dart` — synthetic Freezed-shaped class with `@freezed` class annotation, `@JsonKey(name: '…')` field annotations, and a factory constructor with three parameters using `required` / `this.x` / default-value combinations. Doesn't depend on Freezed at runtime — analyzer parses the syntactic shape regardless of resolution.

**Validation:**
- 210 tests green (was 202, +8 new across parsing + round-trip).
- `dart analyze` and `dart format` clean.
- Scout against `flutter/packages/go_router` (117 files): identical to M7.1 numbers — 0 crashes, 0 idempotence failures, 78 class clean parses.
- CLI `loom parse` on the new fixture prints:
  ```
  ClassStructureModel(class=Person, 3 field(s), 0 method(s), 2 ctor(s), 0 opaque, annotations=[@freezed])
    @JsonKey(name: 'first_name') final String firstName
    @JsonKey(name: 'last_name') final String lastName
    final int age
    const Person({ required this.firstName, required this.lastName, this.age = 0, })
    factory Person.guest()
  ```
  Annotations and parameter info appear inline; user gets enough information to start writing edit operations against the model.

**Learned:**
- **Parameter modeling is genuinely useful even without add/remove.** The `renameParameter` and `changeParameterDefault` ops alone unlock most of what entity-modeling tools need — most edits to existing Freezed/json_serializable classes are "rename this field" or "change this field's default" rather than "add a new field."
- **The analyzer 13 parameter surface is excellent.** Where I'd expected to need pattern-matching on DefaultFormalParameter/SimpleFormalParameter/FieldFormalParameter, almost everything is on the base. Only `isThis` and `isSuper` need `param is FieldFormalParameter` / `is SuperFormalParameter` checks.
- **Backward-compat fields accumulate cheaply.** `parametersSource` (M7.1) stays alongside `parameters` (M7.2) without any tension — both populated at parse time, both useful for different callers. The cost is a few extra fields per node; the benefit is M7.1 tests and callers keep working without churn.

**Next:** Eric review. Then either M7.2.1 (parameter add/remove with placement logic), M7.3 (annotation edit ops, qualifier edit ops), or pivot to M8 (function-body modeling).

### [2026-05-14] M7.1 — class-structure: methods + constructors
**Worked on:** Deepened the class-structure model from M7.0's "fields only" to full member coverage. Methods (including getters/setters/operators) and constructors (including factories) now have dedicated typed nodes.

**Sealed `ClassMember` hierarchy** replaces M7.0's two parallel lists:
- `ClassFieldNode` — extends `ClassMember`; unchanged from M7.0
- `ClassMethodNode` — name + return type + parameters source + body span + flags (isStatic / isAbstract / isGetter / isSetter / isOperator / isAsync / isGenerator)
- `ClassConstructorNode` — class name + optional named-constructor segment + parameters source + initializer-list source + body span + flags (isConst / isFactory)
- `OpaqueClassMember` — catch-all, in practice empty for well-formed Dart

`ClassStructureNode.members` is the new authoritative list (preserves source order; pattern-match for kind). Backward-compat getters `fields` and `opaqueMemberSpans` keep M7.0 callers working without churn.

**Edit-planner additions:**
- `renameMethod(method, newName)` — same shape as `renameField`
- `changeMethodReturnType(method, newReturnType)` — replace return-type span (requires existing return type)
- `removeMember(member, source)` — polymorphic over `ClassMember`. `removeField` now wraps it.
- `addMember(parent, newMemberSource, source)` — polymorphic. `addField` now wraps it.

Parameter editing and qualifier editing remain M7.2 territory — they require either span-level insertion logic (for adding params to a paramless method, etc.) or modeling individual parameter shape.

**Validation:**
- 202 tests green (was 185 → +17 new). `dart analyze` and `dart format` clean.
- New fixture `class_with_constructors.dart` (Money class) exercises four constructor shapes: const default, const named with initializer list, factory with body, factory redirecting `= Money;`. Plus operator overload + override method.
- Scout against flutter/packages/go_router (117 files): **identical numbers to M7.0** — 0 crashes, 0 idempotence failures, 78 class clean parses. M7.1 doesn't change which files parse; it captures more shape inside each.

**Analyzer 13 wrinkles:**
- `ClassMember` name clash: analyzer 13 exports a `ClassMember` AST-node type that clashes with the loom-side sealed type. Resolved with `import 'package:analyzer/dart/ast/ast.dart' hide ClassMember;` on the parser file. Same defensive pattern used elsewhere when domain names overlap with analyzer's vocabulary.
- `ConstructorDeclaration.typeName` is `SimpleIdentifier?` — null when using new-syntax `new C()` form. M7.1 falls back to the constructor's first token for the className anchor in that rare case.
- `MethodDeclaration.body` exposes `isAsynchronous` and `isGenerator` directly — cleaner than reading the body's modifier tokens.

**Learned:**
- **Generic operations land naturally once node types unify under a sealed base.** `removeMember` and `addMember` work for any `ClassMember` without per-kind dispatch because the only state they need (sourceSpan, class body span) is in the sealed type. Type-specific edits (rename, changeReturnType) stay on the concrete subtypes because they touch concrete-only spans.
- **Backward-compat getters are essentially free.** The two getters on `ClassStructureNode` (`fields`, `opaqueMemberSpans`) are 2 lines each and let M7.0 callers keep working unchanged. Worth doing whenever a model widening would otherwise force test churn.
- **The "rule of three" for `_lineIndentBefore` is still pending.** Duplicated across `ListEditHelpers` and `ClassStructureEditPlanner`. Now that M7.1 ships, there are concretely two consumers; a third in M7.2 or M8 will force extraction.

**Next:** Eric review. Then M7.2 (parameter / qualifier / annotation editing) or M8 (function-body modeling).

### [2026-05-14] M7.0 — class-structure modeling (fields only, first slice)
**Worked on:** First non-tree-shaped model in the kernel. M6.x's constructor-tree catalogs were all tree-of-expressions; class structure is a flat list of members. Eric picked the "fields only" scope to keep the slice small while validating that the kernel can absorb a genuinely different shape.

**Architectural decision: separate sealed hierarchy.** `ClassStructureModel` is NOT a `ModelNode` variant. The constructor-tree `ModelNode` (sealed across `WidgetNode` / `RouteNode` / `PipelineNode` / `OpaqueNode` / `MethodReferenceNode`) models trees of expressions with named child slots. A class is fundamentally different: a flat ordered list of members (fields, methods, constructors) each with member-specific shape. Forcing class structure into `ModelNode` would either dilute the constructor-call semantics or contort the model. M7+ may eventually introduce a `LoomModel` umbrella; for now, separate hierarchies are the honest representation.

**Surface added:**
- `lib/src/model/class_structure.dart`: `ClassStructureModel`, `ClassStructureNode`, `ClassFieldNode`. ~140 LOC.
- `lib/src/parsing/class_structure_parser.dart`: `parseClassStructure(source)`. Walks `body.members`; `FieldDeclaration` → `ClassFieldNode` (captures name/type/initializer spans + qualifiers), non-field members → opaque source-span entry. ~100 LOC.
- `lib/src/emission/class_structure_edit_planner.dart`: five operations (`renameField`, `changeFieldType`, `changeFieldInitializer`, `removeField`, `addField`). ~200 LOC.
- `test/fixtures/class_simple.dart` + `test/fixtures/class_with_methods.dart`.
- `test/class_structure_parsing_test.dart` (12 tests) + `test/class_structure_round_trip_test.dart` (10 tests).
- CLI four-way auto-detect; scout per-domain tracking.

**Analyzer 13 API adaptations encountered:**
- `ClassDeclaration.name` (used by older analyzers) became `ClassDeclaration.namePart.typeName`. The `namePart` is a sealed `ClassNamePart` whose `typeName` is the class-name `Token`.
- `ClassDeclaration.body` is now a sealed `ClassBody`. Concrete: `BlockClassBody` (with `leftBracket` / `rightBracket`) for `class Foo {...}`, or `EmptyClassBody` (with `semicolon`) for `class Foo;`. Pattern-match required. M7.0 only supports BlockClassBody; EmptyClassBody is too rare to bother with.

Note: `MethodDeclaration.name` is still a plain `Token` (unchanged), so the existing `BaseVisitor` usage at `base_visitor.dart:189` wasn't affected by this migration.

**Validation:**
- 185 tests green (163 + 22 new). `dart analyze` and `dart format` clean.
- Scout against `flutter/examples` (1,214 files): 0 crashes, 0 idempotence failures, **599 class-structure clean parses**. That's the largest real-world surface we've scouted, and the new parser holds up.
- Scout against `flutter/packages/go_router` (117 files): 78 class-structure clean parses, 0 crashes (route + widget numbers unchanged from M6.2).
- Scout against the loom repo itself: 75 files, 55 class-structure clean parses.

**Five edit operations, with deliberate gaps:** rename, changeType (requires existing type), changeInitializer (requires existing initializer), remove, addField. Excluded for M7.0:
- Adding a type to an untyped field (requires insertion logic, not just span replacement)
- Adding an initializer to a bare field (same reason)
- Reordering fields (would benefit from the `ListEditHelpers` pattern but the class body isn't bracket-delimited the same way)
- Edits to qualifiers (final / var / late / static — each is a separate token to insert/remove)
- Multi-variable single-declaration handling (`final String a, b;` — one source decl maps to two `ClassFieldNode`s sharing the outer span)

These are all incremental and can ship as M7.1 / M7.2 if real-world fixtures demand them.

**Learned:**
- **Constructor-tree generality has limits.** The M6.1 / M6.2 scaffolding (`BaseVisitor`, `ListEditHelpers`, `ConstructorCallSerializer`) doesn't carry over to class structure at all — different shape needs different machinery. The shared primitives (`SourceSpan`, `SourceEdit`, `applySourceEdits`) DO carry over, which is the right level of "shared kernel."
- **Separate sealed hierarchies coexist fine.** Two `ModelNode`-like types in one package isn't confusing as long as the names are domain-clear. `ModelNode` = constructor-call tree node; `ClassStructureNode` = class root with members. Downstream consumers pattern-match within one hierarchy at a time.
- **Real Dart is mostly classes.** 599/1,214 (49%) of flutter/examples files have at least one class. 55/75 (73%) of the loom repo. Class-structure modeling unlocks the most common Dart-file shape — much broader than widget trees alone (588 of those 1,214 files).

**Next:** Eric review. Then M7.1 (deepen class structure with method signatures / constructors / annotations) or pivot to M8 (function-body / statement modeling). M7.1 is the natural extension; M8 is the next genuinely new shape after constructor trees and flat member lists.

### [2026-05-14] M6.2 — third domain catalog (synthetic Pipeline DSL)
**Worked on:** Eric picked M6.2 (more catalogs to stress-test M6.1's scaffolding) over M7 (class-structure modeling). Added a synthetic data-pipeline / workflow DSL as the third domain consumer of the unified kernel, validating that the M6.1 abstractions actually let a third domain plug in.

**The catalog:** Pipeline(name, steps: [...]) → contains Branch(condition, onTrue: [...], onFalse: [...]), ValidateInput(field, required), Transform(name), SaveToDatabase(table), SendEmail(template), LogError(level, message), LogInfo(message). 8 catalog entries, mix of leaf types and one type (Branch) with two list slots. Invented for the demo — not a real package — but representative of where the OutSystems-style trajectory leads.

**Plan deviation worth noting:** the original M6.2 plan in DEVLOG named "test framework (group/test), MaterialApp config trees, Shelf cascades" as candidate catalogs. On closer inspection, none of these actually fit "constructor-tree catalog":
- test framework children live inside function-literal bodies, not in named arguments — requires visitor extensions (M7-shaped work).
- MaterialApp is already in `WidgetCatalog`; not a separate domain.
- Shelf uses cascade method chains, not constructor trees.

Pure-Dart non-Flutter constructor-tree DSLs in real packages are genuinely rare. The synthetic Pipeline DSL is the cleanest demonstration of the kernel's reusability for arbitrary user-provided DSLs, which is the actual point of M6.2.

**Rule-of-three extraction:** writing `PipelineSerializer` revealed that the per-domain `_serializeXxxNode` private method (the ~100-line constructor-call serialization in `WidgetSerializer` and `RouteSerializer`) was identical except for catalog and node-class names. Extracted as `lib/src/emission/constructor_call_serializer.dart`. `WidgetSerializer` / `RouteSerializer` / `PipelineSerializer` are now ~25–30 lines each — domain dispatch + catalog lookup + delegation to the shared helper.

**Sealed hierarchy extended:** `ModelNode` is now sealed with FIVE variants (`WidgetNode | RouteNode | PipelineNode | OpaqueNode | MethodReferenceNode`). Existing pattern-match sites across `bin/loom.dart` (2 printers × 2 switches each), `widget_serializer.dart`, `route_serializer.dart`, `node_path.dart` (3 switches), and `tool/scout.dart` (2 switches) all gained a `PipelineNode` case — most are cross-domain invariant guards that throw on unreachable shapes. The exhaustiveness tax is ~11 lines added across the codebase per new domain; acceptable.

**Validation:**
- 163 tests green (147 + 16 new pipeline tests across parsing + round-trip).
- `dart analyze` and `dart format` clean.
- CLI `loom parse` prints widget, route, and pipeline trees independently if all three are present; gracefully reports if none match.
- Scout against flutter/packages/go_router (117 files): identical to M6.1 — 0 crashes, 0 idempotence failures.
- Scout against loom-repo itself: 68 files, 22 widget / 6 route / 2 pipeline / 40 no-tree / 0 crashes.

**Total non-shared cost of the third domain:** ~250 LOC (node class + catalog + visitor + parser + serializer + edit planner). The M6.1 commit's claim that "a third domain would be ~50 lines" was wrong by ~5x — but the bulk (~150 LOC) is the new node class + edit planner glue, which IS mostly mechanical. The visitor (30 lines) and serializer (30 lines after ConstructorCallSerializer extraction) are genuinely tiny.

**Learned:**
- **"Constructor-tree DSL" is a narrower category than the M6.2 plan assumed.** Most real-world Dart DSLs use other shapes — cascade chains, annotations, top-level decl sequences, function-literal callbacks. Pure constructor-tree DSLs are mostly UI-shaped (widgets and routes). Validates that the kernel as-built is well-suited to UI-shaped work and points toward what's *not* yet ready (function bodies, cascades, class structure).
- **The rule of three is real.** I shipped M6.1 Phase 3 without extracting `ConstructorCallSerializer` because at two copies I judged it premature. The third copy forced the decision and confirmed the right shape — turns out `recurse: ModelNode → String` as a parameter is exactly what's needed to let each domain delegate cleanly. Premature parameterization at two copies might have picked a different (worse) abstraction.
- **Sealed-hierarchy exhaustiveness tax is small per-domain.** ~10 lines of "case X: throw" guards across the codebase, mostly mechanical. Considered re-thinking the sealed design but the compile-time guarantees from exhaustive matching are worth it.

**Next:** Eric reviews M6.0 + M6.0.1 + M6.1 + M6.2. Then likely M7 — class-structure modeling. Constructor-tree catalogs as a shape are well-covered (three working consumers); the next genuine pressure on the kernel is non-tree shapes.

### [2026-05-14] M6.1 — extract loom_core (three-phase refactor)
**Worked on:** Closed the planned M6.1 deduplication of widget- and route-side scaffolding that M6.0 build-alongside intentionally shipped. Split into three commits for reviewability.

**Phase 1 — unify ModelNode hierarchy (commit 47647c1).** Sealed `ModelNode = WidgetNode | RouteNode | OpaqueNode | MethodReferenceNode` replaces the parallel `RouteTreeNode | RouteOpaqueNode | RouteMethodReferenceNode` hierarchy. All four concrete types now live in `lib/src/model/node.dart` (renamed from `widget_node.dart`); `route_node.dart` deleted. `RouteTreeModel.root` typed as `ModelNode`. Pattern-match sites across the codebase gained either a `RouteNode` case (`bin/loom.dart` printers, `widget_serializer.dart`, `node_path.dart`, scout) — most as invariant-violation throws since the widget-side visitors never produce route nodes and vice-versa.

**Phase 2 — extract BaseVisitor scaffold (commit 63b64fe).** `lib/src/parsing/base_visitor.dart` hosts the ~250 lines of shared AST-walking logic. Three domain hooks:
- `specFor(className) → CatalogSpec?` — consult the domain catalog
- `buildModeledNode(...) → ModelNode` — instantiate the concrete `WidgetNode` or `RouteNode`
- `customConstructorPropertyValue(call) → PropertyValue?` — opt-in for widget-side `EdgeInsets.all(N)` / `Color(0x…)`

`CatalogSpec` is the shared spec type (extracted to `lib/src/catalog/catalog_spec.dart`); `WidgetSpec` and `RouteSpec` become typedefs. `ParseException`, `CallInfo` (was private `_CallInfo`), and `extractMethodReturnExpression` move from `widget_visitor.dart` to `base_visitor.dart`. `widget_visitor.dart` re-exports the public ones for backward compat. Parser entry-point method renamed `convertModelNode` / `convertRouteTreeNode` → `convertNode` (shared API on `BaseVisitor`). Net change: `widget_visitor.dart` from ~470 to ~110 lines; `route_visitor.dart` from ~330 to ~45.

**Phase 3 — extract list edit helpers + RouteSerializer (commit 04e4f22).** `lib/src/emission/list_edit_helpers.dart` hosts `insertAt` / `removeAt` / `moveBetween` plus the comment-aware whitespace trim helpers (`_trimEndBeforeComment`, `_trimStartAfterComment`, `_lineIndentBefore`, `_interElementSep`). These take raw `(slotStyle, children, source)` — no node-type dependency, so the same helpers work for any future domain.

The inlined route serializer from `RouteEditPlanner._serializeModelNode` / `_serializeRouteNode` extracted to `lib/src/emission/route_serializer.dart`, mirroring `WidgetSerializer`. `EditPlanner` and `RouteEditPlanner` are now thin per-domain glue (~95 lines each, down from ~414 and ~445): each method picks `slotStyle` + `children` from a `WidgetNode` / `RouteNode` parent, calls the shared helper, and (for inserts) serializes the new child via the domain serializer first.

**Cumulative M6.1 diff:** roughly +1,500 / −2,200 lines across ~15 files. Net code reduction ~700 lines. Every duplicated visitor / edit-planner section between widget- and route-side is now a single shared implementation. The kernel is genuinely reusable for a third domain: implementing M6.2's next catalog means writing ~50 lines (a new `XxxCatalog`, a `XxxVisitor extends BaseVisitor`, an `XxxEditPlanner` mirroring the two existing ones) — no copying scaffolding.

**Validation:**
- 147 tests green throughout all three phases.
- `dart analyze` and `dart format` clean.
- Scout against flutter/packages/go_router (117 files): 0 crashes, 0 idempotence failures, 30 route clean parses — identical to M6.0.1 baseline.

**Learned:**
- **The build-alongside / extract-opportunistically pattern paid off.** The M6.0 duplication revealed the seam concretely — Phase 2's three domain hooks are exactly what the diff between WidgetVisitor and RouteVisitor showed was different. If I'd tried to design the abstraction up-front in M6.0, I would have probably over-parameterized.
- **Dart sealed-class semantics force you to think about library boundaries.** The four concrete `ModelNode` subtypes have to live in one library, which I chose to make one file (`node.dart`). Cross-file `part`/`part of` was the other option, but a single ~300-line file is more idiomatic.
- **CatalogSpec / WidgetSpec / RouteSpec being structurally identical from the start was a real signal.** The build-alongside approach lets you NOTICE this kind of coincidence (vs. designing parameters up front and inevitably making them differ in some way). Typedefs preserve the named API while eliminating the duplication.

**Next:** Eric reviews M6.0 + M6.0.1 + M6.1. Then either:
- **M6.2**: add 2–3 more constructor-tree DSL catalogs (test framework, MaterialApp config trees, possibly Shelf cascades) to stress-test the shared scaffolding's actual reusability.
- **M7**: class-structure modeling — fields, methods, constructors as a *flat list of members*, not a tree. Different shape from constructor trees; pressures the kernel in genuinely new ways.

### [2026-05-14] M6.0.1 — class-field GoRouter entry-point + named_routes fixture
**Worked on:** Closed the M6.0 hardening gap (class-field initializers, 10/18 example files) before the review gate. Extended `route_tree_parser.dart`'s class-walking loop to scan `FieldDeclaration` initializers alongside method returns. Tightened `RouteCatalog.rootClassNames()` from all-catalog-entries to `{GoRouter}` — `GoRoute` and `ShellRoute` are tree-internal, not standalone tree roots, and the looser set was a latent bug for any class that also exposed a `GoRoute` returning helper. Pinned `real_world_go_router_named_routes.dart` (190 LOC) as a second real-world fixture exercising the class-field shape with triple-nested routes.

**Coverage delta (scout on flutter/packages/go_router, 117 files):**
- Before M6.0.1: 8 route clean parses
- After M6.0.1: **30 route clean parses**
- The 22-file jump comes from class-field-initializer files now being detected — including most of the canonical example/ tree and subdirectory variants (books/main.dart, state_restoration/main.dart, etc.).

**Tightening rationale (rootClassNames → {GoRouter}):** Before this change, any class that defined `GoRoute _helper() => GoRoute(...)` would have its helper picked as the route-tree root if it was declared before the actual `GoRouter`. Lucky-ordering accident. The new semantics — `GoRouter` is the only tree root, `GoRoute`/`ShellRoute` are tree-internal — makes the parser pick the right root deterministically and lets helpers returning non-root catalog types fall into `classMethods` for `RouteMethodReferenceNode` resolution. The existing `route_with_helper.dart` fixture covers this exact pattern; tests still pass.

**Validation:**
- 147 tests green (143 + 4 new on the named_routes.dart fixture).
- `dart analyze` clean, `dart format` clean (both fixtures formatted).
- Scout against flutter/packages/go_router: 0 crashes, 0 idempotence failures.

**Learned:**
- **"Catalog entry" and "tree root" are different concepts.** The full catalog includes everything the visitor recognizes mid-tree; the tree-root set is a strict subset (just the things that anchor a parseable tree). M6.0 conflated them. This will matter more as M6.2 adds catalogs with mixed-shape entries (e.g., the `test` framework has `group` as both a root and a tree-internal element).
- **Class-field initializers are arguably the more common shape than class-method returns** for routes in real go_router code (10 vs 2 of the 12 class-based examples). Worth knowing as a default expectation for any future "model X declared inside a class" case.

**Next:** Eric reviews M6.0 + M6.0 hardening + M6.0.1. Then M6.1 — extract `loom_core` (the language-general machinery) into its own sub-namespace, informed by the diff between widget- and route-side scaffolding.

### [2026-05-14] M6.0 hardening — real-world go_router fixture + dual-parser detection
**Worked on:** Eric asked to "add a real GoRouter-using real-world fixture" to tighten M6.0's validation surface (the M6.0 commit had only 4 hand-crafted fixtures, no broad-scout route coverage). Cloned `flutter/packages` from GitHub at HEAD `0ffbde8f622b8dc61e4608483dc4f80f7fab027b`, pinned `packages/go_router/example/lib/main.dart` as `test/fixtures/real_world_go_router_main.dart`. Added 5 parsing tests targeting it (parse correctness, opaque `builder:` function-literal handling, typed list-literal `<RouteBase>[...]` style capture).

**Auto-detect fix:** the M6.0 CLI and scout had a "try widget first, fall back to route" flow — which is wrong because real-world files commonly carry **both** trees (a `build()` method returning `MaterialApp.router(routerConfig: _router)` and a top-level `final GoRouter _router = ...`). The fallback flow let widget detection mask the route tree. Changed both to try both parsers independently and surface whichever succeed. Pure refinement; no behavior change for files with only one tree.

**Broader scout:** ran scout against the entire `packages/go_router` subtree (117 .dart files). Result: 59 widget clean parses, **8 route clean parses**, 0 crashes, 0 idempotence failures. The 8 route detections are all top-level `final GoRouter _router = GoRouter(...)` shape.

**Real-world gap identified:** 10 of 18 example files use `late final GoRouter _router = GoRouter(...)` as a **class-field initializer** rather than a top-level variable. The current parser's entry points (top-level var + class-method-return) don't cover this. Documented as **M6.0.1**: an ~20-line extension to `route_tree_parser.dart`'s class-walking loop to also scan `FieldDeclaration` initializers. Would lift coverage from 8/18 → ~16/18 of canonical go_router examples.

**Validation:**
- 143 tests green (138 + 5 new on the real-world fixture).
- `dart analyze` clean, `dart format` clean.
- Idempotence holds on the new fixture (added to `_routeFixtures` list in `route_round_trip_test.dart`).
- Scout against `flutter/packages/go_router`: 117 files, 0 crashes, 0 idempotence failures.

**Learned:**
- **The "try one, fall back to the other" flow is wrong for catalog-discriminated parsers.** Files commonly have multiple tree shapes; the right behavior is "try each independently and report what's there." This will become more obviously correct as we add more catalogs in M6.2.
- **Class-field initializers are a third common entry-point shape** for catalog roots. The widget side never had this case because widgets always live inside a `build()` method; routes are different. The deferred M6.0.1 fix is mechanical but worth doing before claiming "broad real-world coverage."
- **Typed list literals (`<RouteBase>[...]`) parse identically to untyped lists** in the analyzer AST — the type argument lives in `ListLiteral.typeArguments`, but `leftBracket`/`rightBracket` and the elements list are the same. List-style detection works without modification.

**Next:** Decide on M6.0.1 (extend parser to detect class-field GoRouter initializers — 10/18 example files use this shape) before Eric's review gate, OR proceed to review with the gap explicitly documented. Then M6.1.

### [2026-05-14] M6.0 — Non-Flutter Dart layer (first slice: route DSL)
**Worked on:** Generalized the kernel beyond Flutter widgets by giving it a second consumer. Eric asked to "plan out the non-Flutter Dart layer next" with the long-arc goal of an OutSystems-style multi-domain visual layer over Dart code. M6.0 ships the first slice: a GoRouter-shaped route DSL plugged into the same parse-emit machinery as widgets.

**What was built:**
- `lib/src/model/route_node.dart`: sealed `RouteTreeNode` hierarchy (`RouteNode | RouteOpaqueNode | RouteMethodReferenceNode`) + `RouteTreeModel`.
- `lib/src/catalog/route_catalog.dart`: `RouteCatalog` covering `GoRouter`, `GoRoute`, `ShellRoute`. Single `Map<String, RouteSpec>`, same internal shape as `WidgetCatalog`.
- `lib/src/parsing/route_tree_parser.dart`: `parseRouteTree` — primary entry-point is top-level `final router = GoRouter(...)` declarations; fallback walks class declarations for a method returning a route root (covers `GoRouter get router => GoRouter(...)` and `GoRouter buildRouter() { return GoRouter(...); }`).
- `lib/src/parsing/route_visitor.dart`: copy of `WidgetVisitor` (~290 lines) with the catalog and node-construction types swapped. Widget-only property kinds (EdgeInsets, Color) are intentionally absent — routes don't use those shapes. In-class helper-method resolution carried over verbatim (4th fixture exercises it).
- `lib/src/emission/route_edit_planner.dart`: property / insert / remove / move edits scoped to `RouteNode`. Internal whitespace / comment-trim helpers are duplicated from `EditPlanner`; M6.1 will share them.
- CLI: `bin/loom.dart` auto-detects widget vs route tree in the `parse` subcommand.
- Scout: `tool/scout.dart` extended to dual-mode parser detection; per-file outcome reporting (widget-clean / widget-diag / route-clean / route-diag / none / crash).
- 4 fixtures: `route_simple`, `route_nested`, `route_shell`, `route_with_helper`. 23 tests across `route_parsing_test.dart` + `route_round_trip_test.dart`.

**Sequencing strategy (per the plan): build alongside, extract opportunistically.** `RouteVisitor` and `route_tree_parser.dart` are intentional copies of their widget counterparts. The duplication is the input to M6.1's `loom_core` extraction — pulling out shared code based on evidence rather than guesses.

**Design adjustment from the plan:** the plan said "reuse existing `OpaqueNode` and `MethodReferenceNode`" for the route side. Dart's sealed-class semantics forbid cross-library `implements`, so a single type cannot belong to two sealed hierarchies declared in different libraries. M6.0 instead declares parallel `RouteOpaqueNode` and `RouteMethodReferenceNode` under the new sealed `RouteTreeNode` base. The duplication is small (each is a tiny class), and M6.1 will unify all four under a shared base once the right shape is visible.

**Validation:**
- 137 tests green (114 widget + 23 new route).
- `dart run bin/loom.dart parse` works on both fixture kinds; widget-side regression-free.
- Scout against 1,274 real-world Dart files (loom-repo, lowcode-flutter, flutter/examples): 0 crashes, 0 idempotence failures.
- Note: the originally-planned flutter/codelabs + flutter/samples checkouts from M5.4 were no longer on disk; substituted flutter/examples (1,214 files) as a comparable real-world surface. None of those examples use GoRouter, so route-detection coverage from the broad scout is currently 0 — the 4 fixtures plus 4 hits in the loom-repo scout are the only route-tree validation. M6.2's "more catalogs" milestone will broaden this.

**Learned:**
- **Dart's sealed-class semantics force a duplication decision.** A class can extend `ModelNode` and also `implements RouteTreeNode` only if `RouteTreeNode` is non-sealed (loses exhaustive matching) or both are in the same library (couples the layers tighter than M6.0 wants). The duplication path is small enough to take, and the planned M6.1 unification has clean shape now.
- **The route entry-point is genuinely different from the widget entry-point.** Widgets live inside a `Widget build(BuildContext)` method body, always nested in a class. Routes typically live at top-level (`final router = GoRouter(...);`). Parsing a route tree requires looking at the file's *top-level declarations*, not searching for a method. The class-method fallback handles the less-common shape. This pressures the assumption that "find the modeled root expression" is a single pattern — it's catalog-dependent.
- **Function-literal arguments flow through `OpaquePropertyValue` for free.** The existing widget visitor already opaqued anything that wasn't a simple literal / enum-ref / known constructor. Routes' `builder: (ctx, state) => ...` callbacks just land in the same path without code changes. The opaque-property machinery is genuinely domain-agnostic.

**Headline numbers:** kernel now has two domain consumers (widgets + routes). Public API surface added: `RouteNode`, `RouteTreeModel`, `RouteTreeNode`, `RouteOpaqueNode`, `RouteMethodReferenceNode`, `parseRouteTree`, `RouteEditPlanner`, `RouteCatalog`, `RouteSpec`. 1,274-file scout, 0 crashes, 0 idempotence failures. Same invariants (round-trip + no-op idempotence) hold for route trees as for widget trees.

**Next:** Eric reviews M6.0. Then M6.1: extract `loom_core` against the diff between widget and route layers — pull out source-span / source-edit / list-style / catalog-dispatch / AST-walking scaffolding into a shared core; unify `OpaqueNode` + `RouteOpaqueNode` (and the method-ref pair) under a common sealed base.

### [2026-05-14] M5.5 — analyzer 7.7 → 13.0, visitor adapted, experimental-flags band-aid removed
**Worked on:** Closed the long-term TODO documented in M5.4: bump `analyzer` past 13.0.0 and adapt the visitor to its renamed AST API. The pinned `^7.3.0` was the `_macros` SDK-conflict workaround from M1 scaffolding; moving past it was non-trivial because of breaking AST changes.

**Migration map (analyzer 7.7 → 13.0):**
- `ClassDeclaration.members` is now `ClassDeclaration.body.members`. A new `ClassBody` node wraps the member list.
- `NamedExpression` → `NamedArgument`. The arg-list element type changed from `NodeList<Expression>` to `NodeList<Argument>`, where `Argument` is a sealed type with two subtypes: `NamedArgument` for named args, and `Expression` (which `implements Argument`) for positional. The `NamedArgument` shape is also flatter — `Token name` directly, plus `argumentExpression` (was `Label { label: SimpleIdentifier }` + `expression` in 7.x).
- `NamedType.name2` → `NamedType.name`. Token. The `name2` name in older analyzers was a transition-period accommodation; analyzer 13 drops the suffix.

**Touched files:**
- `widget_visitor.dart`: positional-vs-named arg dispatch in `_buildWidgetNode`. Old code's `if (arg is NamedExpression) {...} else {...}` became `if (arg is NamedArgument) {...} else if (arg is Expression) {...}`. Properties of `NamedArgument` were renamed inline. `_tryExtractCall`'s `NamedType.name2` → `name`.
- `widget_tree_parser.dart`: `declaration.members` → `declaration.body.members`. `_ReferenceCounter._countAtWidgetPosition` got the same NamedExpression → NamedArgument migration. `_extractCall`'s `name2` → `name`. Dropped `import 'package:analyzer/dart/analysis/features.dart';` and the `_enabledExperimentalFlags` constant — no longer needed.
- `pubspec.yaml`: `analyzer: ^7.3.0` → `^13.0.0`. Pub resolved cleanly (the `_macros` SDK conflict that motivated the original 7.3 pin is long gone).

**Combined scout (post-bump) against two repos:**
- `flutter/codelabs` (1068 files): 392 clean / 0 diagnostics / 0 crashes / 0 idempotence failures, 676 expected `ParseException`.
- `flutter/samples` (483 files): 195 clean / 0 diagnostics / 0 crashes / 0 idempotence failures, 288 expected `ParseException`.
- Combined: **1551 .dart files, 587 clean parses, 0 diagnostics, 0 crashes, 0 idempotence failures**. The dot-shorthand files that needed experimental-flag opt-in on analyzer 7.7 now parse clean by default — analyzer 13 has all those features stable.

**Performance note:** 10k-iterations-per-fixture round-trip test went from ~25s to ~156s. The per-call performance benchmark (Global Acceptance #5: parse <100ms, emit <10ms) is still well green, so the per-iteration cost is higher but the spec gates are unchanged. The 6× slowdown comes from analyzer 13's bigger AST walk and validation surface. Acceptable.

**Learned:**
- **The AST migration was smaller than I'd feared.** Six error sites, four of them mechanical renames, two slightly more involved (the named/positional split via the new `Argument` type). Total diff: ~15 lines across two files. The visitor's existing structure (an `_extractCall` helper that normalizes the two constructor-call AST shapes) absorbed the change cleanly.
- **`Expression implements Argument` is a clever bit of design.** It means positional arguments don't need a wrapper — the `ArgumentList.arguments: NodeList<Argument>` can hold raw Expression objects directly. Named args get the `NamedArgument` wrapper because they carry the extra `name: Token` field. Source code looks identical to the old shape at the call-site (`for (final arg in args.arguments)`), only the `is NamedExpression` test pattern changes.
- **Once analyzer matched the SDK, the experimental-flags band-aid vanished.** The `_enabledExperimentalFlags` list from M5.4 became dead code. Removed. The Gotcha entry documenting the version ceiling is no longer load-bearing — kept as historical context but marked superseded.

**Headline numbers:** 114 tests + 1551-file scout, all green. Per-call performance gates still met. Kernel runs on the same analyzer the SDK 3.11.5 ships, removing a class of future Dart-version-drift risk.

**Next:** Eric reviews M5 + M5.1 + M5.2 + M5.3 + M5.4 + M5.5. The kernel is feature-complete, hardened across two review rounds, validated against real-world code at scale, and now on the same analyzer the Dart SDK ships. Nothing left to defer.

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

- **[Superseded 2026-05-14 in M5.5]** The kernel's pinned `analyzer ^7.3.0` lagged the SDK-bundled analyzer; M5.5 bumped to `^13.0.0` and adapted the visitor to the new AST. The migration map (`ClassDeclaration.members` → `.body.members`, `NamedExpression` → `NamedArgument`, `NamedType.name2` → `.name`, `Expression implements Argument`) is in the M5.5 Session Log entry. Keep here as historical context — if a future analyzer version brings another breaking AST change, the same pattern applies.
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
