import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';
import 'kernel_providers.dart';
import 'project_providers.dart';

/// Key for the user-widget resolution cache. Pairs the widget's
/// `className` with the URI of the file from which it's being
/// referenced — the latter is needed because visibility through Dart's
/// import semantics is per-caller.
typedef ResolveBuildTreeKey = ({String className, String fromUri});

/// Resolves the build-body tree of a user-defined widget on demand.
///
/// The canvas materializer reads this provider when it encounters a
/// `WidgetNode` whose `className` is not in the framework renderer
/// catalog (presumed to be a user widget): it asks the kernel for that
/// class's tree so the canvas can recurse into it instead of showing a
/// placeholder. Riverpod's `autoDispose.family` keeps each resolved
/// tree alive only as long as the canvas (or another consumer) watches
/// it, and re-resolves on project rebuild via the watched
/// [projectWidgetIndexProvider] / [projectModelProvider].
///
/// Returns null when no project is open. Otherwise returns a
/// [WidgetTreeParseResult] — `WidgetTreeParseModeled` on success, or
/// `WidgetTreeParseFailure` when the class isn't visible / parseable.
final userWidgetResolutionProvider = Provider.family
    .autoDispose<WidgetTreeParseResult?, ResolveBuildTreeKey>((ref, key) {
  final index = ref.watch(projectWidgetIndexProvider);
  final project = ref.watch(projectModelProvider);
  if (index == null || project == null) return null;
  final adapter = ref.read(kernelAdapterProvider);
  return adapter.resolveBuildTreeFor(
    index: index,
    className: key.className,
    fromFile: key.fromUri,
  );
});
