import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/kernel_adapter.dart';
import '../../../state/selection_providers.dart';

/// One entry per materialized node. Captures the node's selection
/// (`(documentUri, path)`) plus a stable `GlobalKey` that lets the
/// selection/hover overlay measure the node's screen rect, and a depth
/// counter so hit-tests can pick the deepest match at a point.
class ProbeEntry {
  ProbeEntry({
    required this.selection,
    required this.node,
    required this.key,
    required this.depth,
  });

  final NodeSelection selection;
  final ModelNode node;
  final GlobalKey key;

  /// Total nesting depth (counting through resolved user widgets), used
  /// to pick the "deepest" hit when several probes' rects contain the
  /// click point. Higher = more nested.
  final int depth;
}

/// Per-frame state threaded through the materializer. Carries:
///   * the source document URI for the current sub-tree (changes when
///     we recurse through a resolved user widget),
///   * a cycle guard (set of user-widget class names currently being
///     materialized higher up the stack),
///   * a depth counter for the depth-limit guard,
///   * a `WidgetRef` for kernel-resolution provider lookups,
///   * the shared probe registry the viewport reads from.
class MaterializeCtx {
  MaterializeCtx({
    required this.sourceDocumentUri,
    required this.ref,
    required this.probes,
    this.resolvingUserWidgets = const <String>{},
    this.depth = 0,
  });

  final String sourceDocumentUri;
  final WidgetRef ref;
  final Set<String> resolvingUserWidgets;
  final int depth;

  /// Filled in during materialization, read by the interaction layer
  /// and selection overlay. Keyed by `(documentUri, path-string)` so
  /// identical materializations across rebuilds reuse the same entry.
  final Map<String, ProbeEntry> probes;

  /// Builds a ctx for recursing through a resolved user widget — the
  /// inner tree's NodePaths are rooted at the resolved widget's
  /// declaring document, not at the caller's.
  MaterializeCtx forResolvedUserWidget({
    required String className,
    required String newSourceDocumentUri,
  }) =>
      MaterializeCtx(
        sourceDocumentUri: newSourceDocumentUri,
        ref: ref,
        probes: probes,
        resolvingUserWidgets: <String>{...resolvingUserWidgets, className},
        depth: depth + 1,
      );

  /// Stable key for a `(documentUri, path)` pair so multiple frames
  /// reuse the same `GlobalKey` and the selection overlay's render-box
  /// lookups don't churn.
  static String probeRegistryKey(NodeSelection selection) =>
      '${selection.documentUri}|${_pathToKey(selection.path)}';

  static String _pathToKey(NodePath path) {
    final buffer = StringBuffer();
    for (final segment in path) {
      buffer
        ..write(segment.slot)
        ..write(':')
        ..write(segment.index)
        ..write('/');
    }
    return buffer.toString();
  }
}
