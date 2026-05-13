import '../model/property_value.dart';
import 'property_serializer.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual model changes.
///
/// M2 surface: single-property edits only. M3 will add structural edits
/// (child insert/remove/reorder); M2 leaves those out of scope.
class EditPlanner {
  EditPlanner._();

  /// Returns the `SourceEdit` that replaces the source range of
  /// `oldValue` with the serialized form of `newValue`. The result is
  /// minimal-diff by construction — the only bytes touched are those of
  /// the old value's expression.
  ///
  /// The caller is responsible for locating `oldValue` in the model
  /// (e.g. via `WidgetTreeModel.nodeAt(path).properties[name]`). The new
  /// value's own `span` is ignored — only its value-semantics matter,
  /// since the new source range is determined by the new serialized text.
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
}
