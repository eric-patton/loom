import '../model/list_slot_style.dart';
import '../model/property_value.dart';
import '../model/widget_node.dart';
import 'property_serializer.dart';
import 'source_edit.dart';
import 'widget_serializer.dart';

/// Plans `SourceEdit`s for individual model changes.
///
/// M2 surface: single-property edits.
/// M3 surface: structural edits on list-shaped child slots (insert /
/// remove / reorder). Style preservation per `ListSlotStyle`.
class EditPlanner {
  EditPlanner._();

  /// Returns the `SourceEdit` that replaces the source range of
  /// `oldValue` with the serialized form of `newValue`. Minimal-diff by
  /// construction.
  static SourceEdit propertyEdit({
    required PropertyValue oldValue,
    required PropertyValue newValue,
  }) {
    return SourceEdit(
      offset: oldValue.span.offset,
      length: oldValue.span.length,
      replacement: PropertySerializer.serialize(newValue),
    );
  }

  /// Inserts `newChild` at `index` of `parent.childSlots[slotName]`.
  /// Indices in `[0, children.length]` are valid; `children.length`
  /// appends. The list's existing style (trailing-comma + single/multi-line)
  /// is preserved.
  static SourceEdit insertChildEdit({
    required WidgetNode parent,
    required String slotName,
    required int index,
    required WidgetNode newChild,
    required String source,
  }) =>
      _insertAt(
        parent: parent,
        slotName: slotName,
        index: index,
        newSourceText: WidgetSerializer.serialize(newChild),
        source: source,
      );

  /// Removes the child at `index` of `parent.childSlots[slotName]`.
  /// Removing the only element contracts the list to `[]`. The
  /// trailing-comma state (if present) is preserved for non-emptying
  /// removals.
  static SourceEdit removeChildEdit({
    required WidgetNode parent,
    required String slotName,
    required int index,
    required String source,
  }) {
    final style = _requireListStyle(parent, slotName);
    final children = parent.childSlots[slotName] ?? const <WidgetNode>[];
    if (index < 0 || index >= children.length) {
      throw ArgumentError(
        'Remove index $index out of range [0, ${children.length})',
      );
    }
    final target = children[index];
    final closeOff = style.bracketsSpan.offset + style.bracketsSpan.length - 1;

    if (children.length == 1) {
      // Contract to empty single-line `[]`.
      return SourceEdit(
        offset: style.bracketsSpan.offset + 1,
        length: closeOff - (style.bracketsSpan.offset + 1),
        replacement: '',
      );
    }
    if (index == 0) {
      // First: target + the separator to children[1].
      final next = children[1];
      return SourceEdit(
        offset: target.sourceSpan.offset,
        length: next.sourceSpan.offset - target.sourceSpan.offset,
        replacement: '',
      );
    }
    if (index == children.length - 1) {
      // Last: preceding separator + target. Any list trailing-comma stays.
      final prev = children[index - 1];
      return SourceEdit(
        offset: prev.sourceSpan.end,
        length: target.sourceSpan.end - prev.sourceSpan.end,
        replacement: '',
      );
    }
    // Middle: target + the separator to the following element.
    final next = children[index + 1];
    return SourceEdit(
      offset: target.sourceSpan.offset,
      length: next.sourceSpan.offset - target.sourceSpan.offset,
      replacement: '',
    );
  }

  /// Moves the child at `from` to position `to` in the same slot.
  /// Returns a `(remove, insert)` pair of non-overlapping `SourceEdit`s.
  /// The moved bytes are byte-copied verbatim from the source — internal
  /// formatting is preserved across the move.
  static List<SourceEdit> moveChildEdits({
    required WidgetNode parent,
    required String slotName,
    required int from,
    required int to,
    required String source,
  }) {
    if (from == to) {
      return const <SourceEdit>[];
    }
    final children = parent.childSlots[slotName] ?? const <WidgetNode>[];
    if (from < 0 || from >= children.length) {
      throw ArgumentError(
        'Move source $from out of range [0, ${children.length})',
      );
    }
    if (to < 0 || to >= children.length) {
      throw ArgumentError(
        'Move destination $to out of range [0, ${children.length})',
      );
    }
    final moved = children[from];
    final movedText = source.substring(
      moved.sourceSpan.offset,
      moved.sourceSpan.end,
    );
    final removeEdit = removeChildEdit(
      parent: parent,
      slotName: slotName,
      index: from,
      source: source,
    );
    // When from < to, removing `from` shifts later indices left by one,
    // so to address the *original-list* index that corresponds to the
    // user's `to`, we step one past it.
    final insertIndex = from < to ? to + 1 : to;
    final insertEdit = _insertAt(
      parent: parent,
      slotName: slotName,
      index: insertIndex,
      newSourceText: movedText,
      source: source,
    );
    return <SourceEdit>[removeEdit, insertEdit];
  }

  static SourceEdit _insertAt({
    required WidgetNode parent,
    required String slotName,
    required int index,
    required String newSourceText,
    required String source,
  }) {
    final style = _requireListStyle(parent, slotName);
    final children = parent.childSlots[slotName] ?? const <WidgetNode>[];
    if (index < 0 || index > children.length) {
      throw ArgumentError(
        'Insert index $index out of range [0, ${children.length}]',
      );
    }
    final closeOff = style.bracketsSpan.offset + style.bracketsSpan.length - 1;

    if (children.isEmpty) {
      if (style.isMultiLine) {
        return SourceEdit(
          offset: closeOff,
          length: 0,
          replacement: '  $newSourceText,\n',
        );
      }
      return SourceEdit(
        offset: closeOff,
        length: 0,
        replacement: newSourceText,
      );
    }

    final sep = _interElementSep(source, children, style);

    if (index < children.length) {
      // Insert before existing element at `index`.
      return SourceEdit(
        offset: children[index].sourceSpan.offset,
        length: 0,
        replacement: '$newSourceText$sep',
      );
    }
    // index == children.length: append after the current last element.
    return SourceEdit(
      offset: children.last.sourceSpan.end,
      length: 0,
      replacement: '$sep$newSourceText',
    );
  }

  static ListSlotStyle _requireListStyle(WidgetNode parent, String slotName) {
    final style = parent.childSlotStyles[slotName];
    if (style == null) {
      throw ArgumentError(
        '${parent.className}.$slotName is not a list-shaped slot or its '
        'style was not captured; cannot plan a structural edit.',
      );
    }
    return style;
  }

  static String _interElementSep(
    String source,
    List<WidgetNode> children,
    ListSlotStyle style,
  ) {
    if (children.length >= 2) {
      return source.substring(
        children[0].sourceSpan.end,
        children[1].sourceSpan.offset,
      );
    }
    return style.isMultiLine ? ',\n  ' : ', ';
  }
}
