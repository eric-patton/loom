// Sample function body for M8.4 — exercises 5 more expression kinds:
// prefixed identifier, index, instance creation, as, is.

int demo(Map<String, int> m, List<int> xs, Object value) {
  final x = m['key'];
  final list = List<int>.filled(3, 0);
  final pi = Math.pi;
  final cast = value as int;
  final isNum = value is num;
  final notString = value is! String;
  final box = Box(1, 2);
  final first = xs[0];
  return cast + first;
}

class Box {
  final int a;
  final int b;
  const Box(this.a, this.b);
}

class Math {
  static const double pi = 3.14;
}
