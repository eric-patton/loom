import 'package:flutter/widgets.dart';

import '../../../services/kernel_adapter.dart';
import '../../../state/project_providers.dart';
import '../../../state/user_widget_resolution_provider.dart';
import 'materialize_ctx.dart';
import 'placeholders.dart';
import 'widget_renderers.dart';

/// Recursive entry point: turns a `ModelNode` into a real Flutter
/// `Widget`. Each materialized node is wrapped in a stable-keyed
/// `KeyedSubtree` so the selection overlay can measure its render box,
/// and registers itself in `ctx.probes` for the interaction layer's
/// hit-testing.
class NodeMaterializer {
  /// Maximum recursion depth through user widgets before bailing out
  /// with a placeholder. Real apps rarely nest user widgets deeper
  /// than a handful; 32 is a generous cap that still rules out
  /// pathological cycles missed by the explicit visited set (e.g. a
  /// chain `A → B → C → A` that's caught by the visited set, vs. a
  /// linear `A → B → C → ...` chain hundreds deep).
  static const int _maxUserWidgetDepth = 32;

  /// Materializes [node] at NodePath [path] within the current
  /// document context. The result is wrapped in a `KeyedSubtree` keyed
  /// by `(documentUri, path)` and registered in `ctx.probes`.
  static Widget materialize(
    ModelNode node,
    NodePath path,
    MaterializeCtx ctx,
  ) {
    final selection = (documentUri: ctx.sourceDocumentUri, path: path);
    final registryKey = MaterializeCtx.probeRegistryKey(selection);
    final probeKey = GlobalObjectKey(registryKey);

    final Widget content = switch (node) {
      WidgetNode() => _materializeWidget(node, path, ctx),
      OpaqueNode() => OpaquePlaceholder(node: node),
      MethodReferenceNode() => MethodRefPlaceholder(
          node: node,
          body: materialize(node.body, path, ctx),
        ),
      // RouteNode / PipelineNode don't appear in widget trees parsed
      // by `parseWidgetTree`, but the sealed `ModelNode` admits them.
      // If one ever surfaces here, render it as an opaque marker
      // rather than crashing.
      _ => _unknownNodePlaceholder(node),
    };

    ctx.probes[registryKey] = ProbeEntry(
      selection: selection,
      node: node,
      key: probeKey,
      depth: ctx.depth + path.length,
    );

    return KeyedSubtree(key: probeKey, child: content);
  }

  /// Convenience: materialize the first child in [parent]'s [slot], or
  /// return null if the slot has no children. Single-child slots like
  /// `child`, `body`, `home` use this.
  static Widget? materializeChild(
    WidgetNode parent,
    String slot,
    NodePath parentPath,
    MaterializeCtx ctx,
  ) {
    final children = parent.childSlots[slot];
    if (children == null || children.isEmpty) return null;
    return materialize(
      children.first,
      [...parentPath, (slot: slot, index: 0)],
      ctx,
    );
  }

  /// Convenience: materialize every child in [parent]'s [slot]. List
  /// slots like `children`, `actions` use this.
  static List<Widget> materializeChildren(
    WidgetNode parent,
    String slot,
    NodePath parentPath,
    MaterializeCtx ctx,
  ) {
    final children = parent.childSlots[slot];
    if (children == null || children.isEmpty) return const <Widget>[];
    return [
      for (var i = 0; i < children.length; i++)
        materialize(
          children[i],
          [...parentPath, (slot: slot, index: i)],
          ctx,
        ),
    ];
  }

  static Widget _materializeWidget(
    WidgetNode node,
    NodePath path,
    MaterializeCtx ctx,
  ) {
    final renderer = widgetRenderers[node.className];
    if (renderer != null) {
      return renderer(node, path, ctx);
    }
    return _materializeUserWidget(node, path, ctx);
  }

  static Widget _materializeUserWidget(
    WidgetNode node,
    NodePath path,
    MaterializeCtx ctx,
  ) {
    final className = node.className;
    if (ctx.resolvingUserWidgets.contains(className)) {
      return CyclePlaceholder(className: className);
    }
    if (ctx.depth >= _maxUserWidgetDepth) {
      return const DepthLimitPlaceholder();
    }
    final resolution = ctx.ref.read(
      userWidgetResolutionProvider((
        className: className,
        fromUri: ctx.sourceDocumentUri,
      )),
    );
    if (resolution is! WidgetTreeParseModeled) {
      // Unresolved (not visible, not parseable, or no project open):
      // fall back to the unknown-widget placeholder which still
      // descends into modeled children. This keeps the canvas honest:
      // even if we can't render Counter's internals, we still show
      // any explicit children passed via its `child:` slot.
      if (node.childSlots.isEmpty) {
        return UnresolvedPlaceholder(className: className);
      }
      return UnknownWidgetPlaceholder(node: node, path: path, ctx: ctx);
    }
    final declaringUri = _declaringFileUri(ctx, className);
    if (declaringUri == null) {
      return UnresolvedPlaceholder(className: className);
    }
    final innerCtx = ctx.forResolvedUserWidget(
      className: className,
      newSourceDocumentUri: declaringUri,
    );
    return materialize(resolution.model.root, const [], innerCtx);
  }

  static String? _declaringFileUri(MaterializeCtx ctx, String className) {
    final index = ctx.ref.read(projectWidgetIndexProvider);
    return index?.declaringFileOf(className);
  }

  static Widget _unknownNodePlaceholder(ModelNode node) {
    return UnresolvedPlaceholder(className: node.runtimeType.toString());
  }
}
