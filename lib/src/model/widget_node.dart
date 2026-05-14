import 'list_slot_style.dart';
import 'property_value.dart';
import 'source_span.dart';
import 'style_hints.dart';

/// Synthetic property-key prefix used by the visitor when capturing
/// positional arguments that have no `positionalToProperty` mapping in
/// the catalog. The serializer recognizes the same prefix and emits
/// those entries as positional args in numeric-suffix order, interleaved
/// with the catalog's modeled positionals.
const String kPositionalOpaqueKeyPrefix = '__positional';

/// A node in the visual model.
///
/// Sealed: every node is either a `WidgetNode` (modeled constructor call,
/// editable via the kernel API) or an `OpaqueNode` (verbatim source range
/// the kernel does not model — closures, ternaries, helper-method calls
/// returning Widget, comprehensions, etc.). M4 introduced the split.
///
/// All `ModelNode`s carry a `sourceSpan`. The two subtypes diverge in
/// what else they carry and in whether the kernel exposes mutation on
/// them: `WidgetNode`'s properties and child slots are editable;
/// `OpaqueNode`'s content is byte-preserved and any path that descends
/// into one throws at edit time.
sealed class ModelNode {
  const ModelNode();
  SourceSpan get sourceSpan;
}

/// A call to an in-class helper method that returns a widget. The
/// `body` field holds the resolved widget tree from the helper's return
/// expression; edits to `body` translate to `SourceEdit`s targeted at the
/// helper's own source location, not the call site. Introduced in M5.
///
/// Scope (M5 first pass):
///   - In-class helpers only. Cross-file helpers stay as `OpaqueNode`.
///   - Helpers with zero arguments only. Helpers with arguments stay as
///     `OpaqueNode` (we don't model argument expressions in general).
///   - Cycle detection: a method that resolves back to itself becomes an
///     `OpaqueNode` at the inner reference; the outer `MethodReferenceNode`
///     still wraps the non-cyclic part.
class MethodReferenceNode extends ModelNode {
  const MethodReferenceNode({
    required this.methodName,
    required this.callSourceSpan,
    required this.body,
  });

  /// Name of the helper method (e.g. `'_buildHeader'`).
  final String methodName;

  /// Source range of the CALL site (the `_buildHeader()` text in the
  /// enclosing `build()` body). Distinct from the body's source range —
  /// the body's nodes carry their own spans pointing into the helper's
  /// definition.
  final SourceSpan callSourceSpan;

  /// The resolved widget tree rooted at the helper's return expression.
  /// May be a `WidgetNode`, an `OpaqueNode` (helper itself returned an
  /// unmodelable expression, or a cycle was hit), or a nested
  /// `MethodReferenceNode` (helper calls another helper).
  final ModelNode body;

  @override
  SourceSpan get sourceSpan => callSourceSpan;

  // No `==` / `hashCode` override: all `ModelNode` subtypes default to
  // identity. `StructuralEquivalence.equal` is the official oracle for
  // semantic comparison — see `lib/src/equivalence/model_equivalence.dart`.
  // Mixing identity for `WidgetNode` and structural for opaque/method-ref
  // was previously inconsistent in subtle ways (e.g., a `MethodReferenceNode`
  // with a `WidgetNode` body fell back to identity on the body, but with
  // an `OpaqueNode` body fell back to structural — depending on the
  // referenced helper's content). Uniform identity removes that footgun.

  @override
  String toString() => 'MethodReferenceNode($methodName -> $body)';
}

/// A region of source the kernel does not model. Edits cannot touch its
/// content; structural edits to the slot CONTAINING an `OpaqueNode` can
/// still move or remove the node as an opaque unit.
///
/// Carries `sourceText` (the verbatim bytes) in addition to `sourceSpan`,
/// because equivalence comparison after a round-trip needs a stable
/// identity for the opaque content — spans shift in re-parsed source
/// while content is invariant.
class OpaqueNode extends ModelNode {
  const OpaqueNode({required this.sourceSpan, required this.sourceText});

  @override
  final SourceSpan sourceSpan;

  /// Verbatim source bytes for this opaque region.
  final String sourceText;

  // No `==` / `hashCode` override: see `MethodReferenceNode` for the
  // rationale. `StructuralEquivalence.equal` compares by `sourceText`.

  @override
  String toString() {
    final preview = sourceText.length > 30
        ? '${sourceText.substring(0, 30)}...'
        : sourceText;
    final escaped = preview.replaceAll('\n', '\\n');
    return 'OpaqueNode(@${sourceSpan.offset}+${sourceSpan.length}, "$escaped")';
  }
}

/// A modeled constructor call. One `WidgetNode` per Flutter widget the
/// kernel recognizes.
///
/// Stores enough information to render an indented tree (M1), to emit
/// minimal-diff `SourceEdit`s for property/child changes (M2/M3), and to
/// compare against a re-parsed model under the M2 round-trip property test
/// (Settled Decisions Q3, DEVLOG.md).
class WidgetNode extends ModelNode {
  WidgetNode({
    required this.className,
    required Map<String, PropertyValue> properties,
    required Map<String, List<ModelNode>> childSlots,
    required this.sourceSpan,
    required this.styleHints,
    Map<String, ListSlotStyle> childSlotStyles =
        const <String, ListSlotStyle>{},
  })  : properties = Map.unmodifiable(properties),
        childSlots = Map.unmodifiable({
          for (final entry in childSlots.entries)
            entry.key: List<ModelNode>.unmodifiable(entry.value),
        }),
        childSlotStyles = Map.unmodifiable(childSlotStyles);

  /// Class name of the constructor invoked — e.g. `'Column'`.
  final String className;

  /// Modeled literal properties keyed by the named-argument label they came
  /// from. Children are NOT in this map; they live in `childSlots`.
  final Map<String, PropertyValue> properties;

  /// Widget-valued named arguments grouped by their slot name. A
  /// list-shaped slot (e.g. `Column.children`) holds the elements in source
  /// order; a single-shaped slot (e.g. `Padding.child`) holds a one-element
  /// list. Each entry may be either a `WidgetNode` (modeled child) or an
  /// `OpaqueNode` (unmodelable expression preserved verbatim). The catalog
  /// declares which slots a widget has and which shape each takes — see
  /// `lib/src/catalog/widget_catalog.dart`.
  final Map<String, List<ModelNode>> childSlots;

  /// Per-list-slot style hints captured at parse time. Only list-shaped
  /// slots (those with bracketed `[...]` source) have entries; single-
  /// shaped slots don't. Used by M3 structural edits to preserve the
  /// list's trailing-comma and single-/multi-line shape across
  /// insertions, removals, and reorderings.
  final Map<String, ListSlotStyle> childSlotStyles;

  /// Byte range of the constructor call (including any leading
  /// `const`/`new` keyword and the trailing `)`).
  @override
  final SourceSpan sourceSpan;

  final StyleHints styleHints;

  @override
  String toString() {
    final totalChildren = childSlots.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    return 'WidgetNode($className @${sourceSpan.offset}+${sourceSpan.length}, '
        '${properties.length} prop(s), ${childSlots.length} slot(s), '
        '$totalChildren child(ren))';
  }
}

/// Public root of the visual model.
///
/// `root` is a `ModelNode` (not just `WidgetNode`) so that `build()` methods
/// whose top-level return is a helper-method call (`build() => _helper()`)
/// or an unmodelable expression land as `MethodReferenceNode` / `OpaqueNode`
/// at the root rather than throwing at parse time. The kernel API still
/// enforces what's editable per subtype (property edits on a `WidgetNode`,
/// no edits descending into an `OpaqueNode`, etc.).
///
/// `diagnostics` carries any analyzer parse errors recovered from the
/// source (Settled Decision Q4): the model still represents what the
/// analyzer could error-recover, so callers — especially UI consumers —
/// can show a "this file has syntax errors" warning or refuse edits
/// while a file is mid-edit and not parseable.
class WidgetTreeModel {
  const WidgetTreeModel({
    required this.root,
    this.diagnostics = const <ParseDiagnostic>[],
  });

  final ModelNode root;

  /// Analyzer diagnostics gathered while parsing the source. Non-empty
  /// when the source had syntax errors; the model still reflects what
  /// could be error-recovered, but downstream callers may want to
  /// refuse edits or show a warning until the diagnostics list is empty.
  final List<ParseDiagnostic> diagnostics;

  @override
  String toString() => 'WidgetTreeModel(rootType=${root.runtimeType}'
      '${diagnostics.isEmpty ? '' : ', ${diagnostics.length} diagnostic(s)'})';
}

/// A single analyzer parse diagnostic, surfaced on `WidgetTreeModel`.
/// Mirrors the subset of `package:analyzer`'s `AnalysisError` shape that
/// the kernel cares about — source span, severity-blind message — without
/// pulling analyzer types into the kernel's public API.
class ParseDiagnostic {
  const ParseDiagnostic({required this.span, required this.message});

  final SourceSpan span;
  final String message;

  @override
  String toString() =>
      'ParseDiagnostic($message @${span.offset}+${span.length})';
}
