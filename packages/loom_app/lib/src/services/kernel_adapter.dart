/// The single seam between Loom's visual editor and the kernel package.
///
/// Everything else under `lib/src/` imports this file rather than
/// `package:loom/loom.dart` directly. The file re-exports the kernel's
/// public surface for type access, then wraps the verbs (parse / plan /
/// apply) on [KernelAdapter] so the editor side has one place to swap
/// implementations when the kernel eventually moves out of process.
library;

import 'package:loom/loom.dart';

export 'package:loom/loom.dart';

/// Outcome of parsing a single Dart source file's widget tree.
///
/// Modeled when [parseWidgetTree] succeeded; failed when the file has no
/// `build()` method, descends into an unsupported expression at the
/// visitor, or hits an analyzer error that prevents recovery.
sealed class WidgetTreeParseResult {
  const WidgetTreeParseResult();

  /// Convenience factory for a successful parse.
  factory WidgetTreeParseResult.modeled(WidgetTreeModel model) =
      WidgetTreeParseModeled;

  /// Convenience factory for a parse failure with a [message] describing
  /// the cause.
  factory WidgetTreeParseResult.failure(String message) =
      WidgetTreeParseFailure;
}

class WidgetTreeParseModeled extends WidgetTreeParseResult {
  const WidgetTreeParseModeled(this.model);
  final WidgetTreeModel model;
}

class WidgetTreeParseFailure extends WidgetTreeParseResult {
  const WidgetTreeParseFailure(this.message);
  final String message;
}

class KernelAdapter {
  const KernelAdapter();

  ProjectModel buildProject(Map<String, String> sources) =>
      ProjectModel.fromSources(sources);

  ProjectWidgetIndex buildWidgetIndex(ProjectModel project) =>
      ProjectWidgetIndex.build(project);

  /// Parses [source] and returns the widget tree model.
  ///
  /// [projectWidgets] should be the result of
  /// `ProjectWidgetIndex.widgetsVisibleFrom(path)` for cross-file widget
  /// recognition.
  WidgetTreeParseResult parseWidgetTreeFor({
    required String source,
    Map<String, WidgetSpec> projectWidgets = const <String, WidgetSpec>{},
  }) {
    try {
      final model = parseWidgetTree(source, projectWidgets: projectWidgets);
      return WidgetTreeParseResult.modeled(model);
    } on ParseException catch (e) {
      return WidgetTreeParseResult.failure(e.message);
    } on Object catch (e) {
      return WidgetTreeParseResult.failure(e.toString());
    }
  }

  /// Resolves a user-defined widget [className] (visible from [fromFile])
  /// to its build-body widget tree, so the canvas can recursively render
  /// what's inside a user widget instead of stopping at a placeholder.
  /// Returns a `WidgetTreeParseFailure` when the class isn't visible, has
  /// no build, or the parse fails.
  WidgetTreeParseResult resolveBuildTreeFor({
    required ProjectWidgetIndex index,
    required String className,
    required String fromFile,
  }) {
    try {
      final model = index.resolveBuildTree(
        className: className,
        fromFile: fromFile,
      );
      if (model == null) {
        return WidgetTreeParseResult.failure(
          'Could not resolve build tree for $className',
        );
      }
      return WidgetTreeParseResult.modeled(model);
    } on ParseException catch (e) {
      return WidgetTreeParseResult.failure(e.message);
    } on Object catch (e) {
      return WidgetTreeParseResult.failure(e.toString());
    }
  }

  /// Plans a property edit at [oldValue.span] in [source] and returns the
  /// resulting source. Throws if applying the planned edit fails (e.g.
  /// stale span).
  String applyPropertyEdit({
    required String source,
    required PropertyValue oldValue,
    required PropertyValue newValue,
  }) {
    final edit =
        EditPlanner.propertyEdit(oldValue: oldValue, newValue: newValue);
    return applySourceEdits(source, <SourceEdit>[edit]);
  }
}
