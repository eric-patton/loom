import 'package:flutter/material.dart';

import '../../../services/kernel_adapter.dart';
import 'materialize_ctx.dart';
import 'node_materializer.dart';

/// Renders an `OpaqueNode` — an expression the kernel couldn't model
/// (ternary, closure, spread, etc.). Shows a compact source snippet so
/// the user can still locate the call site in the file.
class OpaquePlaceholder extends StatelessWidget {
  const OpaquePlaceholder({super.key, required this.node});

  final OpaqueNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = node.sourceText.length > 32
        ? '${node.sourceText.substring(0, 32)}…'
        : node.sourceText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        preview,
        style: theme.textTheme.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Renders a `MethodReferenceNode` — an in-class helper method call
/// (e.g. `_buildHeader()`). Stacks a thin "→ methodName()" label over
/// the resolved body so the user can see both the abstraction and its
/// content.
class MethodRefPlaceholder extends StatelessWidget {
  const MethodRefPlaceholder({
    super.key,
    required this.node,
    required this.body,
  });

  final MethodReferenceNode node;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        children: [
          body,
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              color: theme.colorScheme.secondaryContainer,
              child: Text(
                '→ ${node.methodName}()',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a `WidgetNode` whose className is not in the renderer
/// catalog AND is not resolvable as a user widget. Descends into the
/// node's modeled children so that an unknown wrapper still shows its
/// content (e.g. an obscure layout widget around a known Column).
class UnknownWidgetPlaceholder extends StatelessWidget {
  const UnknownWidgetPlaceholder({
    super.key,
    required this.node,
    required this.path,
    required this.ctx,
  });

  final WidgetNode node;
  final NodePath path;
  final MaterializeCtx ctx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allChildren = <Widget>[];
    for (final entry in node.childSlots.entries) {
      allChildren.addAll(
        NodeMaterializer.materializeChildren(node, entry.key, path, ctx),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (allChildren.isEmpty)
            Text(
              node.className,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: allChildren,
            ),
          Positioned(
            top: -14,
            left: -1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              color: theme.colorScheme.surfaceContainerHigh,
              child: Text(
                node.className,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a user widget that recursively references itself (or
/// transitively): `A → B → A`. Avoids stack overflow.
class CyclePlaceholder extends StatelessWidget {
  const CyclePlaceholder({super.key, required this.className});

  final String className;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        border: Border.all(color: theme.colorScheme.error),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$className (recursive)',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// Renders the depth-limit guard — a user widget hierarchy that
/// nests deeper than the materializer's hard cap (32).
class DepthLimitPlaceholder extends StatelessWidget {
  const DepthLimitPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        border: Border.all(color: theme.colorScheme.tertiary),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'depth limit',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

/// Renders a user widget that the kernel couldn't resolve — either
/// it's not visible from the caller, or it failed to parse.
class UnresolvedPlaceholder extends StatelessWidget {
  const UnresolvedPlaceholder({super.key, required this.className});

  final String className;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(4),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Text(
        className,
        style: theme.textTheme.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
