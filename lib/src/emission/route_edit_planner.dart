import '../catalog/route_catalog.dart';
import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import 'property_serializer.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual route-model changes.
///
/// Parallel to `EditPlanner` on the widget side, scoped to `RouteNode`.
/// Same source-span math; different node type. M6.0 build-alongside: the
/// internal whitespace / comment-trimming helpers are duplicated verbatim
/// from `EditPlanner` (language-general; M6.1 will share them).
class RouteEditPlanner {
  RouteEditPlanner._();

  /// Returns the `SourceEdit` that replaces the source range of
  /// `oldValue` with the serialized form of `newValue`.
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
  static SourceEdit insertChildEdit({
    required RouteNode parent,
    required String slotName,
    required int index,
    required ModelNode newChild,
    required String source,
  }) =>
      _insertAt(
        parent: parent,
        slotName: slotName,
        index: index,
        newSourceText: _serializeModelNode(newChild),
        source: source,
      );

  /// Removes the child at `index` of `parent.childSlots[slotName]`.
  static SourceEdit removeChildEdit({
    required RouteNode parent,
    required String slotName,
    required int index,
    required String source,
  }) {
    final style = _requireListStyle(parent, slotName);
    final children = parent.childSlots[slotName] ?? const <ModelNode>[];
    if (index < 0 || index >= children.length) {
      throw ArgumentError(
        'Remove index $index out of range [0, ${children.length})',
      );
    }
    final target = children[index];
    final closeOff = style.bracketsSpan.offset + style.bracketsSpan.length - 1;

    if (children.length == 1) {
      return SourceEdit(
        offset: style.bracketsSpan.offset + 1,
        length: closeOff - (style.bracketsSpan.offset + 1),
        replacement: '',
      );
    }
    if (index == 0) {
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
      final prev = children[index - 1];
      final separatorStart = _trimStartAfterComment(
        prev.sourceSpan.end,
        target.sourceSpan.offset,
        source,
      );
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

  /// Moves the child at `from` to position `to` in the same slot.
  static List<SourceEdit> moveChildEdits({
    required RouteNode parent,
    required String slotName,
    required int from,
    required int to,
    required String source,
  }) {
    if (from == to) {
      return const <SourceEdit>[];
    }
    final children = parent.childSlots[slotName] ?? const <ModelNode>[];
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

  // ---------------------------------------------------------------------
  // Internal helpers. Copies of the widget-side EditPlanner helpers; M6.1
  // will pull these into a shared core module.
  // ---------------------------------------------------------------------

  static SourceEdit _insertAt({
    required RouteNode parent,
    required String slotName,
    required int index,
    required String newSourceText,
    required String source,
  }) {
    final style = _requireListStyle(parent, slotName);
    final children = parent.childSlots[slotName] ?? const <ModelNode>[];
    if (index < 0 || index > children.length) {
      throw ArgumentError(
        'Insert index $index out of range [0, ${children.length}]',
      );
    }
    final closeOff = style.bracketsSpan.offset + style.bracketsSpan.length - 1;

    if (children.isEmpty) {
      if (style.isMultiLine) {
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
      return SourceEdit(
        offset: children[index].sourceSpan.offset,
        length: 0,
        replacement: '$newSourceText$sep',
      );
    }
    return SourceEdit(
      offset: children.last.sourceSpan.end,
      length: 0,
      replacement: '$sep$newSourceText',
    );
  }

  static ListSlotStyle _requireListStyle(RouteNode parent, String slotName) {
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
      if (!raw.contains('//') && !raw.contains('/*')) {
        return raw;
      }
    }
    if (!style.isMultiLine) {
      return ', ';
    }
    final firstIndent = _lineIndentBefore(
      children.first.sourceSpan.offset,
      source,
    );
    return ',\n$firstIndent';
  }

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

  static int _trimStartAfterComment(int start, int end, String source) {
    var lastCommentEnd = -1;
    for (var i = start; i + 1 < end; i++) {
      final c = source.codeUnitAt(i);
      if (c != 0x2F) {
        continue;
      }
      final n = source.codeUnitAt(i + 1);
      if (n == 0x2F) {
        var j = i + 2;
        while (j < end && source.codeUnitAt(j) != 0x0A) {
          j++;
        }
        lastCommentEnd = j;
        i = j;
      } else if (n == 0x2A) {
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
        i = j - 1;
      }
    }
    if (lastCommentEnd < 0) {
      return start;
    }
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

  /// Inlined route-tree serializer for the insert path. M6.1 Phase 3 will
  /// promote this to a standalone `RouteSerializer` sibling of
  /// `WidgetSerializer`. `WidgetNode` in the switch is unreachable in
  /// practice — the route visitor never produces one — but the sealed
  /// `ModelNode` hierarchy now includes it, so we throw to make the
  /// invariant explicit.
  static String _serializeModelNode(ModelNode node) => switch (node) {
        final RouteNode r => _serializeRouteNode(r),
        final OpaqueNode o => o.sourceText,
        final MethodReferenceNode m => '${m.methodName}()',
        WidgetNode() => throw ArgumentError(
            'RouteEditPlanner cannot serialize a WidgetNode',
          ),
      };

  static String _serializeRouteNode(RouteNode node) {
    final spec = RouteCatalog.specFor(node.className);
    if (spec == null) {
      throw ArgumentError(
        'No catalog entry for ${node.className}; cannot serialize',
      );
    }

    final buf = StringBuffer();
    if (node.styleHints.hasConst) {
      buf.write('const ');
    } else if (node.styleHints.hasNew) {
      buf.write('new ');
    }
    buf.write(node.className);
    buf.write('(');

    final parts = <String>[];

    final reverseLookup = <String, int>{
      for (final entry in spec.positionalToProperty.entries)
        entry.value: entry.key,
    };
    final positionalByIndex = <int, String>{};
    for (final entry in spec.positionalToProperty.entries) {
      final value = node.properties[entry.value];
      if (value != null) {
        positionalByIndex[entry.key] = PropertySerializer.serialize(value);
      }
    }
    for (final entry in node.properties.entries) {
      if (!entry.key.startsWith(kPositionalOpaqueKeyPrefix)) {
        continue;
      }
      final idx = int.tryParse(
        entry.key.substring(kPositionalOpaqueKeyPrefix.length),
      );
      if (idx == null) {
        continue;
      }
      if (positionalByIndex.containsKey(idx)) {
        final mapped = spec.positionalToProperty[idx];
        throw ArgumentError(
          'Conflicting positional argument at index $idx on '
          '${node.className}: catalog maps index to "$mapped" and '
          'properties also contains "${entry.key}". Drop one.',
        );
      }
      positionalByIndex[idx] = PropertySerializer.serialize(entry.value);
    }
    final sortedPositional = positionalByIndex.keys.toList()..sort();
    for (final idx in sortedPositional) {
      parts.add(positionalByIndex[idx]!);
    }

    final namedParts = <String, String>{};
    for (final entry in node.properties.entries) {
      if (reverseLookup.containsKey(entry.key)) {
        continue;
      }
      if (entry.key.startsWith(kPositionalOpaqueKeyPrefix)) {
        continue;
      }
      namedParts[entry.key] =
          '${entry.key}: ${PropertySerializer.serialize(entry.value)}';
    }
    for (final entry in node.childSlots.entries) {
      final shape = spec.childSlots[entry.key];
      if (shape == ChildSlotShape.list) {
        final inner = entry.value.map(_serializeModelNode).join(', ');
        namedParts[entry.key] = '${entry.key}: [$inner]';
      } else {
        if (entry.value.isEmpty) {
          continue;
        }
        namedParts[entry.key] =
            '${entry.key}: ${_serializeModelNode(entry.value.first)}';
      }
    }
    final sortedNamedKeys = namedParts.keys.toList()..sort();
    for (final key in sortedNamedKeys) {
      parts.add(namedParts[key]!);
    }

    buf.write(parts.join(', '));
    if (node.styleHints.hasTrailingComma && parts.isNotEmpty) {
      buf.write(',');
    }
    buf.write(')');
    return buf.toString();
  }
}
