import 'kernel_adapter.dart';

/// How a file's widget root parses, viewed through the kernel's lens:
///
///   - [modeled] — root is a `WidgetNode` (or a `MethodReferenceNode`
///     resolving to one). The Interface tab marks the file as editable.
///   - [opaqueRoot] — the file has a `build()` method but the kernel
///     couldn't model its return expression (e.g., an unrecognized
///     widget or a closure / ternary at the root).
///   - [noBuild] — no class with a `build()` method exists in the file.
///   - [parseError] — analyzer reported syntax errors the visitor could
///     not error-recover from.
enum FileWidgetRootKind { modeled, opaqueRoot, noBuild, parseError }

/// One file's classification: what kind of root, plus any error text
/// surfaced to the user.
class FileClassification {
  const FileClassification({
    required this.uri,
    required this.kind,
    this.errorMessage,
  });

  final String uri;
  final FileWidgetRootKind kind;
  final String? errorMessage;

  bool get isModeled => kind == FileWidgetRootKind.modeled;
}

/// Decides whether a file's widget tree is "modeled enough" for the
/// Interface tab to show it as editable. Reads only through the
/// [KernelAdapter] seam.
class WidgetFilterService {
  const WidgetFilterService(this._adapter);

  final KernelAdapter _adapter;

  FileClassification classify({
    required String uri,
    required String source,
    Map<String, WidgetSpec> projectWidgets = const <String, WidgetSpec>{},
  }) {
    final result = _adapter.parseWidgetTreeFor(
      source: source,
      projectWidgets: projectWidgets,
    );
    if (result is WidgetTreeParseFailure) {
      final message = result.message;
      if (message.contains('No build() method found')) {
        return FileClassification(
          uri: uri,
          kind: FileWidgetRootKind.noBuild,
        );
      }
      return FileClassification(
        uri: uri,
        kind: FileWidgetRootKind.parseError,
        errorMessage: message,
      );
    }
    final model = (result as WidgetTreeParseModeled).model;
    return FileClassification(
      uri: uri,
      kind: _kindOfRoot(model.root),
    );
  }

  static FileWidgetRootKind _kindOfRoot(ModelNode root) {
    var node = root;
    while (node is MethodReferenceNode) {
      node = node.body;
    }
    if (node is WidgetNode) return FileWidgetRootKind.modeled;
    return FileWidgetRootKind.opaqueRoot;
  }
}
