# Loom

Two-way visual editor kernel for Flutter widget source. Pure Dart, headless, CI-friendly. The `.dart` source files are the source of truth; this kernel exposes a structured `WidgetTreeModel` over the AST and emits minimal-diff `SourceEdit`s back, with byte-level fidelity in unedited regions.

Canonical references:

- [`PROJECT_SPEC.md`](PROJECT_SPEC.md) — scope, architecture, milestones, acceptance criteria, invariants
- [`DEVLOG.md`](DEVLOG.md) — settled decisions, milestone progress, session log

No GUI, no Flutter dependency, no live preview, no LSP — this is the kernel. A future Flutter UI consumes it as a library.
