import '../model/list_slot_style.dart';
import '../model/property_value.dart';
import '../model/node.dart';
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
  ///
  /// `newChild` may be any `ModelNode` — a `WidgetNode` is freshly
  /// serialized, an `OpaqueNode` emits its captured `sourceText`, and a
  /// `MethodReferenceNode` emits `methodName()` (the helper must already
  /// exist in the source for the call to resolve at the inserted site).
  static SourceEdit insertChildEdit({
    required WidgetNode parent,
    required String slotName,
    required int index,
    required ModelNode newChild,
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
      // First: target + the separator to children[1]. Always delete the
      // full element; trim only the SEPARATOR zone (after the element)
      // if it contains a comment, so the comment is preserved.
      final next = children[1];
      final separatorEnd = _trimEndBeforeComment(
        target.sourceSpan.end,
        next.sourceSpan.offset,
        source,
      );
      return SourceEdit(
        offset: target.sourceSpan.offset,
        length: separatorEnd - target.sourceSpan.offset,
        replacement: '',
      );
    }
    if (index == children.length - 1) {
      // Last: preceding separator + target. Trim only the separator
      // zone (before the element) — element source bytes are not
      // scanned for comments, so `//` or `/*` inside a string literal
      // inside the element doesn't confuse the trim.
      final prev = children[index - 1];
      final separatorStart = _trimStartAfterComment(
        prev.sourceSpan.end,
        target.sourceSpan.offset,
        source,
      );
      // When a comment was preserved in the separator, the comma
      // between prev and target remains in source and now functions as
      // a trailing comma of the contracted list. If the original list
      // ALSO had a trailing comma after target, that comma is now
      // orphan (yielding `[A, // c\n  ,]`, which analyzer error-recovers
      // as a list with an empty second element — a direct invariant
      // violation). Extend the deletion to consume that orphan comma.
      // No comment preserved → the inter-element comma IS deleted, so
      // the original trailing-comma-after-target naturally lands as
      // the trailing comma of the contracted list; no extension needed.
      var deleteEnd = target.sourceSpan.end;
      final commentPreserved = separatorStart > prev.sourceSpan.end;
      if (commentPreserved) {
        var probe = target.sourceSpan.end;
        while (probe < source.length) {
          final ch = source.codeUnitAt(probe);
          if (ch == 0x20 || ch == 0x09) {
            probe++;
          } else {
            break;
          }
        }
        if (probe < source.length && source.codeUnitAt(probe) == 0x2C) {
          deleteEnd = probe + 1;
        }
      }
      return SourceEdit(
        offset: separatorStart,
        length: deleteEnd - separatorStart,
        replacement: '',
      );
    }
    // Middle: target + the separator to the following element. Same
    // separator-only trim as the first-element case.
    final next = children[index + 1];
    final separatorEnd = _trimEndBeforeComment(
      target.sourceSpan.end,
      next.sourceSpan.offset,
      source,
    );
    return SourceEdit(
      offset: target.sourceSpan.offset,
      length: separatorEnd - target.sourceSpan.offset,
      replacement: '',
    );
  }

  /// Given a candidate deletion range `[start, end)`, returns a new
  /// `end` that stops just before any `//` or `/*` comment found inside
  /// the range. Trailing whitespace immediately preceding the comment
  /// is also dropped from the deletion. If no comment is found, `end`
  /// is returned unchanged.
  static int _trimEndBeforeComment(int start, int end, String source) {
    for (var i = start; i + 1 < end; i++) {
      final c = source.codeUnitAt(i);
      if (c != 0x2F) {
        continue;
      }
      final n = source.codeUnitAt(i + 1);
      if (n != 0x2F && n != 0x2A) {
        continue;
      }
      // Comment starts at i. Walk back over horizontal whitespace.
      var trim = i;
      while (trim > start) {
        final ch = source.codeUnitAt(trim - 1);
        if (ch == 0x20 || ch == 0x09) {
          trim--;
        } else {
          break;
        }
      }
      return trim;
    }
    return end;
  }

  /// Mirror of `_trimEndBeforeComment` for the last-element case:
  /// given `[start, end)`, returns a new `start` that begins just AFTER
  /// any comment block in the range. Trailing whitespace AFTER the
  /// comment (up to the start of the element being removed) is also
  /// dropped from the deletion. If no comment is found, `start` is
  /// returned unchanged.
  static int _trimStartAfterComment(int start, int end, String source) {
    var lastCommentEnd = -1;
    for (var i = start; i + 1 < end; i++) {
      final c = source.codeUnitAt(i);
      if (c != 0x2F) {
        continue;
      }
      final n = source.codeUnitAt(i + 1);
      if (n == 0x2F) {
        // Line comment to end of line (or end of range).
        var j = i + 2;
        while (j < end && source.codeUnitAt(j) != 0x0A) {
          j++;
        }
        lastCommentEnd = j;
        i = j;
      } else if (n == 0x2A) {
        // Block comment to '*/'.
        var j = i + 2;
        while (j + 1 < end) {
          if (source.codeUnitAt(j) == 0x2A &&
              source.codeUnitAt(j + 1) == 0x2F) {
            j += 2;
            break;
          }
          j++;
        }
        lastCommentEnd = j;
        i = j - 1; // -1 because the for-loop increments
      }
    }
    if (lastCommentEnd < 0) {
      return start;
    }
    // Skip whitespace after the comment.
    var trim = lastCommentEnd;
    while (trim < end) {
      final ch = source.codeUnitAt(trim);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D) {
        trim++;
      } else {
        break;
      }
    }
    return trim;
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
        // Anchor the insertion just AFTER the opening `[` so the
        // existing newline + whitespace before `]` naturally becomes the
        // closing-bracket indent — no double-indent. The element's
        // indent is inferred from the line containing `[` plus 2 spaces.
        //
        // No trailing comma is emitted: an empty list literal always
        // has `hasTrailingComma=false` (the visitor reads it from the
        // token before `]`, which is `[` itself), and `insertChild` on
        // the model doesn't change that flag, so a trailing-comma flip
        // here would make the in-memory model disagree with the reparse.
        final openOff = style.bracketsSpan.offset;
        final outerIndent = _lineIndentBefore(openOff, source);
        final elementIndent = '$outerIndent  ';
        return SourceEdit(
          offset: openOff + 1,
          length: 0,
          replacement: '\n$elementIndent$newSourceText',
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
    List<ModelNode> children,
    ListSlotStyle style,
  ) {
    if (children.length >= 2) {
      final raw = source.substring(
        children[0].sourceSpan.end,
        children[1].sourceSpan.offset,
      );
      // Fall back to a default separator if the natural one contains a
      // comment — duplicating that comment on every insert would
      // misrepresent the source.
      if (!raw.contains('//') && !raw.contains('/*')) {
        return raw;
      }
    }
    if (!style.isMultiLine) {
      return ', ';
    }
    // Multi-line fallback: infer the indent from the first element's
    // line so the inserted element lands at the same column. Hardcoding
    // two spaces would push trailing siblings out of column whenever the
    // real list indent is something else (e.g., 6 spaces inside a nested
    // widget).
    final firstIndent = _lineIndentBefore(
      children.first.sourceSpan.offset,
      source,
    );
    return ',\n$firstIndent';
  }

  /// Returns the run of horizontal whitespace immediately preceding
  /// `offset` on its line — i.e. the indentation of `offset`'s line.
  /// Used to choose indents for inserted elements in multi-line lists.
  static String _lineIndentBefore(int offset, String source) {
    var lineStart = offset;
    while (lineStart > 0 && source.codeUnitAt(lineStart - 1) != 0x0A) {
      lineStart--;
    }
    var i = lineStart;
    while (i < offset) {
      final ch = source.codeUnitAt(i);
      if (ch == 0x20 || ch == 0x09) {
        i++;
      } else {
        break;
      }
    }
    return source.substring(lineStart, i);
  }
}
