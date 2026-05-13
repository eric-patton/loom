# DEVLOG — Loom

Running record of decisions, milestone progress, and lessons learned for the Loom kernel. Exists so future sessions — human and AI — can pick up without re-litigating settled questions.

**Update protocol:** every working session ends with at least one entry in the Session Log. Entries are append-only; corrections go in new entries that reference the original. Never edit history. The Current State block at the top is the only section that gets rewritten in place.

---

## Current State

**Active milestone:** M1 — Parse only
**Last touched:** 2026-05-13 — scaffolding landed (deps, lints, CI, round-trip harness)
**Blockers:** none
**Next action:** Propose M1 implementation plan and ratify Open Questions Q1, Q3, Q5 (the ones M1 hits). Q2 and Q4 stay deferred to M3/M4.

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

### [2026-05-13] Package and CLI named `loom`, not `twoway_kernel` / `twoway`
**Question:** PROJECT_SPEC.md names the library `twoway_kernel` and the CLI `twoway`, while the repo and DEVLOG use the project codename "Loom". Two-name story (per spec) or one-name story (rename to `loom` across repo, Dart package, and CLI binary)?
**Decision:** One name. The Dart package is `loom` (`lib/loom.dart`, imports as `package:loom/...`), the CLI binary is `loom` (`bin/loom.dart`).
**Rationale:** Simpler to remember, type at the shell, and grep for. The `twoway`/`twoway_kernel` names in the spec predate "Loom" as the project name; carrying both forward adds friction with no benefit. Trade-off: any future external docs referring to `twoway`/`twoway_kernel` (none yet exist) need updating; reverting later would require a coordinated import-line rewrite across the codebase.
**Revisit if:** A separate Dart package or CLI ever ships under the `twoway` name and the two need to coexist.

---

## Open Questions Status

Mirrors the spec's Open Questions section. Update the status field as each resolves.

1. **`const` and `new` keyword handling** — _Unresolved (spec default: preserve)_
2. **Trailing comma detection scope** — _Unresolved (spec default: per-list)_
3. **AST equivalence definition** — _Unresolved (spec default: structural, ignoring trivia)_
4. **Parse errors in the source** — _Unresolved (spec default: partial model + unparseable flag)_
5. **Imports and top-level declarations** — _Unresolved (spec default: not modeled, preserved by non-touching)_

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
- [ ] `loom parse <file>` CLI command implemented (stub exists; renamed from spec's `twoway parse`)
- [ ] Passes on 5 hand-crafted fixtures
- [ ] Passes on 3 real-world Flutter files (record which ones)
- [ ] Every leaf node has valid `SourceSpan`
- [ ] Style hints captured: trailing comma presence, `const` keyword presence
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
| _(none yet)_ | | | |

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

- **analyzer 6.5.0–7.2.x are broken on current Dart SDKs.** They pull in `package:macros` which depends on `_macros` from the SDK, which the SDK no longer ships. Use `analyzer: ^7.3.0` (and `dart_style: ^3.0.0` so it picks a compatible analyzer). If you see a `version solving failed` error mentioning `_macros 0.x.y from sdk`, this is what you're looking at.

---

## References Consulted

Things read during the work that turned out useful. Helps future sessions avoid re-discovering the same resources.

- _(none yet)_
