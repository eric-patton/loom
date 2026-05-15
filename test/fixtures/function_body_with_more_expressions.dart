// Sample function body for M8.3 — exercises expressions in more
// positions (initializer, return, throw, yield, if/while/do conditions)
// AND the 6 new expression kinds (assignment, conditional, await,
// prefix, postfix, property access).

Future<int> demo(int n) async {
  final doubled = n * 2;
  if (n > 0) {
    n += 1;
  }
  while (n < 100) {
    n++;
  }
  do {
    n--;
  } while (n > 50);
  final tag = n > 0 ? 'pos' : 'neg';
  final result = await fetch();
  final negated = -n;
  final accessed = n.toString();
  if (n == 0) {
    throw StateError('zero');
  }
  return doubled + result;
}

Future<int> fetch() async => 42;
