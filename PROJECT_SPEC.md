# Two-Way Flutter Editor — Kernel Spec

A pure Dart library and CLI that round-trips Flutter widget source code through a structured model, with byte-level fidelity in unedited regions. Foundation for a future visual editor (and eventually an OutSystems-style governance layer on top).

This document is the working spec. It defines what to build, what not to build, what "done" means at each milestone, and the invariants that govern the whole effort.

> **Implementation status (read this first)**: this spec was written **before** the kernel was built. The implementation tracked it closely but diverged in some places. **`DEVLOG.md` is the canonical record of what actually shipped and why** — start there for current state, settled open questions, and milestone gates. Specific deltas you should know:
>
> - Package + CLI named `loom`, not `twoway_kernel` / `twoway` (Settled Decision [2026-05-13]).
> - File consolidations: `opaque_node.dart` lives inside `widget_node.dart` (sealed-subtype requirement); `ast_equivalence.dart` → `model_equivalence.dart` (Q3 settled at the model level); `formatter.dart` deleted; `dart_style` and `glados`/`checks` dev deps dropped — none earned their keep.
> - `WidgetTreeModel.root` widened from `WidgetNode` to `ModelNode` (M5.3), so `build() => _helper()` and bare-helper roots resolve. `WidgetTreeModel.diagnostics` carries analyzer parse errors (Q4 settled).
> - Catalog covers 17 widgets (Column, Row, Padding, Center, SizedBox, Container, Expanded, GestureDetector, InkWell, Material, SafeArea, MaterialApp, Scaffold, AppBar, DefaultTabController, TabBar, TabBarView, Tab, Text, Icon, IconButton, FloatingActionButton). Anything else opaques.
> - **M6.0**: kernel generalizes beyond widgets. `RouteCatalog` + `parseRouteTree` + `RouteEditPlanner` model non-widget constructor-tree DSLs (initial coverage: GoRouter / GoRoute / ShellRoute). Loom is **not Flutter-coupled** — the widget catalog is one of several pluggable upper layers on top of a shared parse-emit kernel. See DEVLOG M6.0 for the M6.1 → M10+ roadmap toward an OutSystems-style multi-domain visual layer.
>
> When this spec and `DEVLOG.md` disagree, `DEVLOG.md` is authoritative.

---

## North Star

**The .dart source files are the source of truth. The visual model is a view over the AST. Every edit is a minimal-diff `SourceEdit` against the existing source.**

If a user opens their project in this tool, makes ten property changes, and looks at `git diff`, they see exactly ten lines changed and nothing else — no reformatted whitespace, no shuffled imports, no lost comments, no rewritten string quotes.

Two non-negotiable invariants govern every commit to this repo:

1. **Round-trip stability**: `parse(apply(edits, source))` produces an AST equivalent to the editor's model after those edits.
2. **No-op idempotence**: `apply([], source) == source` byte-for-byte.

If a change breaks either invariant on the fixture corpus, it does not ship. No "we'll fix it later." The whole product proposition collapses without these.

---

## Scope of This Work — The Kernel Only

This spec covers the **kernel**: the AST ↔ visual model bridge. No UI, no widget rendering, no DevTools integration, no LSP server, no live preview. The deliverable is a pure Dart library (`twoway_kernel`) and a CLI demo tool.

The bet: 80% of the technical risk lives in the kernel. Once it's solid, everything else (UI, governance, multi-file, state visualization) is conventional engineering on top of it. Build the hard thing first, alone, with tests.

**In scope:**
- Parse a Dart source file containing a Flutter widget tree
- Build a `WidgetTreeModel` mapping visual nodes to AST source ranges
- Accept structured edits to the model (property changes, child insertion/removal/reorder)
- Emit `SourceEdit` lists that, when applied, produce a source string matching the new model
- Round-trip property tests that exercise the invariants exhaustively
- A `twoway` CLI that demonstrates parse → edit → emit → re-parse on real files

**Out of scope (deliberately deferred):**
- Any GUI
- Widget rendering or live preview
- VM service / DevTools integration
- Cross-file refactoring
- State management visualization (Riverpod, Bloc, etc.)
- Multi-file project model
- LSP server hosting
- Governance layer (audit, RBAC, environment promotion)
- A widget catalog richer than what's needed for parsing

---

## Architecture

Three layers, strictly directional:

**Source layer** — the actual .dart file on disk, as a `String`. Treated as immutable from the kernel's perspective. The kernel produces `SourceEdit` operations; the caller applies them.

**AST layer** — `package:analyzer`'s `CompilationUnit`. Built fresh from the source string on each parse. Token offsets in the AST are the bridge between the model and the source. We never modify the AST in place; we walk it to build the model, then plan edits in terms of source offsets.

**Model layer** — `WidgetTreeModel`, the editor's domain object. Each `WidgetNode` holds:
- The Flutter widget class name (`Container`, `Column`, `Text`, etc.)
- A `Map<String, PropertyValue>` of named arguments
- A list of child nodes
- A `SourceSpan { offset, length }` referencing the AST node range — this is what makes minimal-diff editing possible
- A `StyleHints` record capturing trivia like trailing comma presence, `const` keyword, single-line vs multi-line formatting

The flow:

```
source: String
   ↓ parse()
CompilationUnit (analyzer)
   ↓ walk()
WidgetTreeModel
   ↓ user mutations
WidgetTreeModel'
   ↓ plan()
List<SourceEdit>
   ↓ apply() + dart_format (scoped)
source': String
   ↓ parse() ── compared against ──→ WidgetTreeModel'  (round-trip test)
```

The model is generated from source on every open; it is **never persisted**. The source file is the database. There is no "project file" the editor maintains alongside the user's code.

---

## Tech Stack

- Dart 3.x (latest stable)
- `package:analyzer` — parsing, AST, token offsets, resolved type info
- `package:dart_style` — post-edit formatting, scoped to edited ranges only
- `package:test` and `package:checks` — unit and integration tests
- `package:glados` — property-based testing for round-trip invariants
- `package:path` — file utilities

No Flutter dependency in the kernel itself. The kernel is pure Dart, runs headless, and must remain platform-independent and CI-friendly. A future Flutter UI will *consume* the kernel as a library.

---

## Project Structure

```
twoway/
├── pubspec.yaml
├── README.md
├── PROJECT_SPEC.md                  # this file
├── analysis_options.yaml            # strict lints; treat warnings as errors
├── lib/
│   ├── twoway_kernel.dart           # public API surface
│   └── src/
│       ├── parsing/
│       │   ├── widget_tree_parser.dart
│       │   └── widget_visitor.dart
│       ├── model/
│       │   ├── widget_node.dart
│       │   ├── property_value.dart
│       │   ├── source_span.dart
│       │   ├── style_hints.dart
│       │   └── opaque_node.dart
│       ├── emission/
│       │   ├── source_edit.dart
│       │   ├── edit_planner.dart
│       │   └── formatter.dart
│       ├── equivalence/
│       │   └── ast_equivalence.dart # semantic AST comparison
│       └── catalog/
│           └── widget_catalog.dart  # minimal known-widget metadata
├── bin/
│   └── twoway.dart                  # CLI demo
└── test/
    ├── parsing_test.dart
    ├── emission_test.dart
    ├── round_trip_test.dart         # the critical one
    ├── equivalence_test.dart
    └── fixtures/
        ├── simple_widget.dart
        ├── nested_widget.dart
        ├── conditional_widget.dart
        ├── trailing_commas_present.dart
        ├── trailing_commas_absent.dart
        └── real_world_*.dart        # pinned from open-source apps
```

---

## Milestones

Each milestone has hard acceptance criteria. M(N+1) does not begin until M(N) passes its criteria on the fixture corpus. No skipping ahead.

### M1 — Parse only (read path)

Given a Dart file containing a `Widget build(BuildContext context)` method whose body returns a tree of widget constructors, produce a `WidgetTreeModel` capturing the tree. Support literal arguments: strings, numbers, booleans, `null`, `EdgeInsets.all(N)`, simple `Color(0x...)` constructors, basic enum references like `MainAxisAlignment.center`.

Acceptance:
- `twoway parse <file>` prints the widget tree as indented text matching the source structure
- Passes on 5 hand-crafted fixtures plus 3 real-world Flutter files
- Every leaf node has a valid `SourceSpan` pointing at its constructor call in the source
- Style hints (trailing comma present, `const` keyword present) are captured

### M2 — Property edit (write path, simplest case)

Change a single literal property on a single node and emit a `SourceEdit` that, when applied, produces source whose re-parsed model has the new value and is otherwise identical to the original.

Acceptance:
- Round-trip property test passes for 1,000 random property edits on the M1 fixture set
- `git diff` after any single edit shows exactly one changed line (or one changed contiguous range within a line)
- No comments, blank lines, or whitespace outside the edited token change
- `apply([], source) == source` always

### M3 — Structural edits

Insert, remove, and reorder children in a `children:` list. Handle trailing commas correctly per the existing style of the list being edited — if the list has trailing commas, new entries get them; if not, they don't.

Acceptance:
- Round-trip property tests pass for sequences of up to 10 mixed structural edits applied in arbitrary order
- Trailing comma style is detected per-list and preserved across edits
- Single-line vs multi-line list style is detected and preserved (a one-child list stays single-line; a multi-child list stays multi-line)
- Empty-list → non-empty and non-empty → empty transitions handled

### M4 — Opaque blocks

When the parser encounters Dart it doesn't model (closures, conditional expressions, method calls returning Widget, `.map().toList()` patterns, comprehensions, ternaries), insert an `OpaqueNode` in the model holding the verbatim source range. Edits to opaque nodes are forbidden by the API; their content round-trips identically.

Acceptance:
- Parse a complex real-world Flutter file with conditional rendering, `.map()` patterns, and helper method calls without crashing
- Every non-trivially-handled construct becomes an `OpaqueNode`, not a parse failure
- Opaque node content is preserved byte-for-byte through any sequence of edits to surrounding nodes
- The `WidgetNode` API throws on any attempt to mutate an opaque node

### M5 — Helper method following

When a widget tree contains a call to a method like `_buildHeader()` defined in the same class, the model represents it as a `MethodReferenceNode` pointing at that method's tree. The caller can navigate into the referenced method and edit it; edits update the helper's source.

Acceptance:
- Edits to a referenced helper method update the helper's source via `SourceEdit`s targeted at the helper's location
- Round-trip invariants hold across method boundaries
- Cyclic references (helper calls itself) are detected and represented without infinite recursion
- Cross-file helper references are out of scope for M5 — they become opaque nodes

---

## Global Acceptance Criteria

The kernel ships (i.e., is considered ready to build a UI on top of) when it passes these gates on a corpus of **20 hand-picked real-world Flutter files**: a mix from `flutter/samples`, 5+ popular open-source Flutter apps, and at least 5 hand-crafted edge cases (deeply nested, heavy trailing commas, heavy conditionals, mixed const/non-const, etc.).

1. **Parse coverage**: every file in the corpus parses without crashing. Unmodelable constructs become `OpaqueNode`s.
2. **Round-trip stability**: 10,000 random valid edit sequences across the corpus produce zero invariant failures in CI.
3. **Diff minimality**: every single-property edit produces a `git diff` of exactly the changed property.
4. **Format preservation**: comments, blank lines, trailing commas, and whitespace in unedited regions are preserved byte-for-byte.
5. **Performance**: parsing a 1,000-line file completes in under 100ms; emitting an edit completes in under 10ms.

---

## Testing Strategy

Three tiers. All three run in CI on every PR. A red light in any tier blocks merge.

**Unit tests** — individual parsers, emitters, model operations. Fast (<1s for the full suite). Run on every save during development.

**Round-trip property tests** — the most important tier and the easiest to skimp on. For each fixture, generate random valid edit sequences using `package:glados`, apply them, re-parse, compare ASTs. Properties under test:

- `parse(emit(M)) ≅ M` (AST equivalence, not byte equality, after applying emitted edits)
- `emit([]) == source` (byte equality on no-op)
- `apply(emit(M ⊕ Δ₁ ⊕ Δ₂), source) == apply(emit(...Δ₂), apply(emit(...Δ₁), source))` (edit composition is well-defined)
- For any opaque node `O` in `M`, the source range of `O` is byte-identical in `source` and `apply(emit(M'), source)` for any `M'` not touching `O`

CI runs at least **10,000 iterations per fixture per run**. Local development can run smaller counts; CI does not.

**Fixture corpus tests** — pin the 20 real-world files. Run the full round-trip gauntlet against each. Any change to the kernel that breaks any fixture is reverted, not patched around. New fixtures are added when bugs are found in the wild.

---

## Open Questions

Flag these explicitly when encountered rather than silently picking a side:

1. **`const` and `new` keyword handling**: preserve as a property of the node, or recompute on emit? Preserving is safer for round-trip; recomputing is cleaner. **Default position: preserve. Document the choice.**

2. **Trailing comma detection scope**: per-list, per-file, or per-line? Real Flutter style guides usually mean per-list. **Default position: per-list, detected from the existing list being edited.**

3. **AST equivalence definition**: precise enough that two ASTs that "should be the same" compare equal, but strict enough to catch real bugs. **Default position: structural equivalence ignoring trivia (whitespace, comments), but preserving constant-vs-non-constant distinctions and explicit `new` keywords.** Implement in `lib/src/equivalence/ast_equivalence.dart` with extensive tests.

4. **What to do with parse errors in the source**: the user's Dart is sometimes mid-edit and won't parse. **Default position: return a partial model with an `unparseable` flag on the affected region; do not crash. Edits to unparseable regions are forbidden.**

5. **Imports and top-level declarations**: M1–M5 ignore them entirely. They're preserved because the kernel never touches them, but they're not modeled. **Confirm this is OK for the MVP; flag if any milestone needs to reference them.**

---

## Non-Goals (Restated, Because Drift Is the Enemy)

- **No GUI.** Not even a debug visualization. Output of M1–M5 is a library API and CLI.
- **No Flutter runtime integration.** No `flutter run`, no VM service, no DevTools. The kernel never executes user code.
- **No state management awareness.** Riverpod, Bloc, etc. are opaque.
- **No multi-file work.** One file at a time. Cross-file is a later concern.
- **No widget catalog beyond parsing needs.** We don't need to know every Flutter widget's full signature to round-trip it. We just preserve its constructor call structure.
- **No package management or scaffolding.** The kernel assumes a Dart file exists; it doesn't create projects.

---

## References

- `package:analyzer` API — https://pub.dev/packages/analyzer
- `package:dart_style` — how it scopes formatting to ranges
- Dart Analysis Server protocol — for understanding `SourceEdit` semantics
- Plasmic (React analog) — their "Plasmic Loader" docs on hand-edited code interop
- Android Studio Layout Editor — closest existing analog to true two-way sync for a typed UI framework
- Flutter SDK's own tests — best reference for how widget construction should look

---

## First Task

Scaffold the project structure exactly as laid out in "Project Structure" above. Set up `analysis_options.yaml` with strict lints (treat-as-error on unused imports, unused variables, missing return types). Get `package:test`, `package:checks`, and `package:glados` installed. Add a CI workflow (GitHub Actions or whatever) that runs all three test tiers.

Then implement M1 against a single hand-crafted fixture: a 30-line `MyHomePage` widget with a `Column` containing `Text` and `Padding` widgets with literal properties.

**Critical**: stand up the round-trip property test infrastructure in `test/round_trip_test.dart` before writing any emission code. The property tests are the safety harness for everything that follows. Even with only M1 (parse-only) implemented, the test should at least verify `emit([]) == source` for the parse-then-no-op-emit case.

Do not begin M2 until M1 passes its acceptance criteria on at least 5 fixtures, reviewed.
