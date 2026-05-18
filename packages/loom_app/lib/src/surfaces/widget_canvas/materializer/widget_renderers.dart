import 'package:flutter/material.dart';

import '../../../services/kernel_adapter.dart';
import 'materialize_ctx.dart';
import 'node_materializer.dart';
import 'property_resolver.dart';

/// Type signature of a renderer. Reads typed properties via
/// [PropertyResolver], recurses through `childSlots` via
/// [NodeMaterializer.materializeChild] / [NodeMaterializer.materializeChildren],
/// returns a Flutter widget. Renderers must never throw on opaque or
/// missing data — they fall back to the widget's natural default.
typedef WidgetRenderer = Widget Function(
  WidgetNode node,
  NodePath path,
  MaterializeCtx ctx,
);

const _prop = PropertyResolver();

const _mainAxisAlignment = <String, MainAxisAlignment>{
  'start': MainAxisAlignment.start,
  'end': MainAxisAlignment.end,
  'center': MainAxisAlignment.center,
  'spaceBetween': MainAxisAlignment.spaceBetween,
  'spaceAround': MainAxisAlignment.spaceAround,
  'spaceEvenly': MainAxisAlignment.spaceEvenly,
};

const _crossAxisAlignment = <String, CrossAxisAlignment>{
  'start': CrossAxisAlignment.start,
  'end': CrossAxisAlignment.end,
  'center': CrossAxisAlignment.center,
  'stretch': CrossAxisAlignment.stretch,
  'baseline': CrossAxisAlignment.baseline,
};

/// The renderer catalog. Adding a new widget is a one-line entry here
/// plus a private function below.
final Map<String, WidgetRenderer> widgetRenderers = <String, WidgetRenderer>{
  'MaterialApp': _renderMaterialApp,
  'Scaffold': _renderScaffold,
  'AppBar': _renderAppBar,
  'Center': _renderCenter,
  'Column': _renderColumn,
  'Row': _renderRow,
  'Text': _renderText,
  'SizedBox': _renderSizedBox,
  'Padding': _renderPadding,
  'ElevatedButton': _renderElevatedButton,
  'FloatingActionButton': _renderFloatingActionButton,
  'Visibility': _renderVisibility,
  'Container': _renderContainer,
  'IconButton': _renderIconButton,
};

Widget _renderMaterialApp(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final home = NodeMaterializer.materializeChild(node, 'home', path, ctx);
  // We discard MaterialApp.title / theme / routes etc. — the editor's
  // outer MaterialApp already provides theming; the canvas just renders
  // the home subtree. Wrapping in another MaterialApp would risk
  // theme/Directionality issues; the viewport already sets those.
  return home ?? const SizedBox.shrink();
}

Widget _renderScaffold(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final body = NodeMaterializer.materializeChild(node, 'body', path, ctx);
  final fab = NodeMaterializer.materializeChild(
    node,
    'floatingActionButton',
    path,
    ctx,
  );
  final bottom = NodeMaterializer.materializeChild(
    node,
    'bottomNavigationBar',
    path,
    ctx,
  );
  final appBarWidget = NodeMaterializer.materializeChild(
    node,
    'appBar',
    path,
    ctx,
  );
  final PreferredSizeWidget? appBar;
  if (appBarWidget == null) {
    appBar = null;
  } else if (appBarWidget is PreferredSizeWidget) {
    appBar = appBarWidget;
  } else {
    // The user's appBar slot holds something we couldn't fully
    // materialize as a PreferredSizeWidget (e.g. a user widget that
    // resolves to a wrapper). Coerce to a sensible default height so
    // Scaffold accepts it.
    appBar = PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: appBarWidget,
    );
  }
  return Scaffold(
    appBar: appBar,
    body: body,
    floatingActionButton: fab,
    bottomNavigationBar: bottom,
  );
}

Widget _renderAppBar(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final title = NodeMaterializer.materializeChild(node, 'title', path, ctx);
  final leading = NodeMaterializer.materializeChild(node, 'leading', path, ctx);
  final actions =
      NodeMaterializer.materializeChildren(node, 'actions', path, ctx);
  return AppBar(
    title: title,
    leading: leading,
    actions: actions.isEmpty ? null : actions,
  );
}

Widget _renderCenter(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final child = NodeMaterializer.materializeChild(node, 'child', path, ctx);
  return Center(child: child);
}

Widget _renderColumn(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final children =
      NodeMaterializer.materializeChildren(node, 'children', path, ctx);
  return Column(
    mainAxisAlignment: _prop.enumValue(
          node.properties['mainAxisAlignment'],
          _mainAxisAlignment,
        ) ??
        MainAxisAlignment.start,
    crossAxisAlignment: _prop.enumValue(
          node.properties['crossAxisAlignment'],
          _crossAxisAlignment,
        ) ??
        CrossAxisAlignment.center,
    children: children,
  );
}

Widget _renderRow(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final children =
      NodeMaterializer.materializeChildren(node, 'children', path, ctx);
  return Row(
    mainAxisAlignment: _prop.enumValue(
          node.properties['mainAxisAlignment'],
          _mainAxisAlignment,
        ) ??
        MainAxisAlignment.start,
    crossAxisAlignment: _prop.enumValue(
          node.properties['crossAxisAlignment'],
          _crossAxisAlignment,
        ) ??
        CrossAxisAlignment.center,
    children: children,
  );
}

Widget _renderText(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  return Text(_prop.string(node.properties['data']) ?? '');
}

Widget _renderSizedBox(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final child = NodeMaterializer.materializeChild(node, 'child', path, ctx);
  return SizedBox(
    width: _prop.doubleOf(node.properties['width']),
    height: _prop.doubleOf(node.properties['height']),
    child: child,
  );
}

Widget _renderPadding(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final child = NodeMaterializer.materializeChild(node, 'child', path, ctx);
  return Padding(
    padding: _prop.edgeInsets(node.properties['padding']) ?? EdgeInsets.zero,
    child: child,
  );
}

Widget _renderElevatedButton(
  WidgetNode node,
  NodePath path,
  MaterializeCtx ctx,
) {
  final child = NodeMaterializer.materializeChild(node, 'child', path, ctx);
  return ElevatedButton(
    // Non-null so the button paints enabled. We never run user
    // callbacks; the canvas does not execute user code.
    onPressed: () {},
    child: child ?? const SizedBox.shrink(),
  );
}

Widget _renderFloatingActionButton(
  WidgetNode node,
  NodePath path,
  MaterializeCtx ctx,
) {
  final child = NodeMaterializer.materializeChild(node, 'child', path, ctx);
  return FloatingActionButton(
    onPressed: () {},
    child: child,
  );
}

Widget _renderVisibility(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final child = NodeMaterializer.materializeChild(node, 'child', path, ctx);
  return Visibility(
    visible: _prop.boolean(node.properties['visible']) ?? true,
    // The child stays in the tree even when invisible so it remains
    // selectable via the outline.
    maintainState: true,
    maintainSize: true,
    maintainAnimation: true,
    child: child ?? const SizedBox.shrink(),
  );
}

Widget _renderContainer(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final child = NodeMaterializer.materializeChild(node, 'child', path, ctx);
  return Container(
    width: _prop.doubleOf(node.properties['width']),
    height: _prop.doubleOf(node.properties['height']),
    color: _prop.color(node.properties['color']),
    padding: _prop.edgeInsets(node.properties['padding']),
    child: child,
  );
}

Widget _renderIconButton(WidgetNode node, NodePath path, MaterializeCtx ctx) {
  final icon = NodeMaterializer.materializeChild(node, 'icon', path, ctx);
  return IconButton(
    onPressed: () {},
    icon: icon ?? const Icon(Icons.help_outline),
  );
}
