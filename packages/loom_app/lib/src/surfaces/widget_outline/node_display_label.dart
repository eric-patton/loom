import 'package:flutter/material.dart';

import '../../services/kernel_adapter.dart';

/// Text label for a node in the outline. Pure formatting — the visible
/// glyph for `WidgetNode`, `MethodReferenceNode`, `OpaqueNode`, etc.
/// Kept stand-alone so unit tests can assert label text without
/// pumping a widget.
class NodeDisplayLabel extends StatelessWidget {
  const NodeDisplayLabel({super.key, required this.node});

  final ModelNode node;

  /// String form of [node]'s label. Switch over the sealed hierarchy
  /// keeps M11 honest — adding a kernel variant must add a case here.
  static String labelFor(ModelNode node) {
    return switch (node) {
      WidgetNode(:final className, :final namedConstructor) =>
        namedConstructor == null ? className : '$className.$namedConstructor',
      MethodReferenceNode(:final methodName) => 'method $methodName()',
      OpaqueNode() => '« opaque »',
      // RouteNode and PipelineNode aren't shown in the widget-tree
      // outline (the kernel does not produce them inside a
      // `WidgetTreeModel`), but a defensive label keeps the switch
      // exhaustive without throwing if a future kernel rework lands one
      // here unexpectedly.
      _ => '« ${node.runtimeType} »',
    };
  }

  static Color _colorFor(ModelNode node, ColorScheme scheme) {
    return switch (node) {
      WidgetNode() => scheme.onSurface,
      MethodReferenceNode() => scheme.primary,
      OpaqueNode() => scheme.onSurfaceVariant,
      _ => scheme.error,
    };
  }

  static FontStyle? _styleFor(ModelNode node) =>
      node is OpaqueNode ? FontStyle.italic : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      labelFor(node),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: _colorFor(node, theme.colorScheme),
        fontStyle: _styleFor(node),
      ),
    );
  }
}
