/// A byte range in the source string.
///
/// Offsets and lengths are UTF-16 code units, matching `package:analyzer`'s
/// `Token.offset` / `Token.length` convention and Dart `String` semantics.
class SourceSpan {
  const SourceSpan({required this.offset, required this.length});

  final int offset;
  final int length;

  int get end => offset + length;

  @override
  bool operator ==(Object other) =>
      other is SourceSpan && other.offset == offset && other.length == length;

  @override
  int get hashCode => Object.hash(offset, length);

  @override
  String toString() => 'SourceSpan(@$offset+$length)';
}
