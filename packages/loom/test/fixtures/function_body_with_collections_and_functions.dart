// Sample function body for M8.5 — exercises collection literals
// (list, set, map), record literal, function expression, cascade.

int demo() {
  final xs = [1, 2, 3];
  final typedList = <int>[10, 20];
  final s = {1, 2, 3};
  final m = {'a': 1, 'b': 2};
  final r = (1, 'two', x: 3);
  final f = (int x) => x + 1;
  final blockFn = (int x) {
    return x * 2;
  };
  final sb = StringBuffer()
    ..write('hello')
    ..write(' ')
    ..write('world');
  return xs.length;
}
