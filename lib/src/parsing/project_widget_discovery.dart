import 'package:analyzer/dart/ast/ast.dart';

import '../catalog/widget_catalog.dart';

/// Walks the top-level class declarations of [unit] and returns a map of
/// class-name → `WidgetSpec` for every class whose `extends` clause names
/// a superclass ending in `Widget` (`StatelessWidget`, `StatefulWidget`,
/// `ConsumerWidget`, `HookWidget`, `InheritedWidget`, `RenderObjectWidget`,
/// `PreferredSizeWidget`, etc.).
///
/// The returned `WidgetSpec` is intentionally empty — no `childSlots`, no
/// `positionalToProperty`. The parser uses this map purely to RECOGNIZE
/// project-defined widget classes so they classify as `WidgetNode` rather
/// than `OpaqueNode`; their children, if any, end up as opaque properties.
/// Slot inference from constructor signatures is a future phase.
///
/// Limitations:
///   * Only direct `extends Foo` matches. Transitive widget bases (a class
///     that extends `_PrivateBase` where `_PrivateBase extends StatelessWidget`)
///     are NOT recognized — we don't follow chains without resolved types.
///   * `State<X>`-extending classes are explicitly excluded — they have a
///     `build()` method but aren't themselves widgets to be referenced.
///   * Cross-file widget discovery (recognizing `MyImportedWidget` from
///     another file) is a separate phase that needs `ProjectModel`.
Map<String, WidgetSpec> discoverIntraFileWidgets(CompilationUnit unit) {
  final discovered = <String, WidgetSpec>{};
  for (final decl in unit.declarations) {
    if (decl is! ClassDeclaration) continue;
    final extendsClause = decl.extendsClause;
    if (extendsClause == null) continue;
    final superTypeName = extendsClause.superclass.name.lexeme;
    if (_looksLikeWidgetBase(superTypeName)) {
      discovered[decl.namePart.typeName.lexeme] = const WidgetSpec();
    }
  }
  return discovered;
}

bool _looksLikeWidgetBase(String superName) {
  // The unambiguous heuristic: ends in "Widget". Catches all framework
  // widget bases (`StatelessWidget`, `StatefulWidget`, `InheritedWidget`,
  // `RenderObjectWidget`, `LeafRenderObjectWidget`, `MultiChildRenderObjectWidget`,
  // `SingleChildRenderObjectWidget`, `ProxyWidget`, `PreferredSizeWidget`,
  // `ComponentWidget`) plus the common third-party bases that conventionally
  // follow the same naming (`ConsumerWidget`, `HookWidget`,
  // `ConsumerStatefulWidget`, `StatefulHookConsumerWidget`).
  //
  // Crucially, `State<X>` does NOT end in "Widget", so the State half of a
  // StatefulWidget pair is excluded — we register the StatefulWidget itself,
  // not its State.
  return superName.endsWith('Widget');
}
