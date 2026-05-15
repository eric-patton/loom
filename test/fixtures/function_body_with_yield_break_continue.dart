// Sample function body for M8.1 — exercises yield, yield*, break,
// continue, and labeled statements.

Iterable<int> walk(List<int> xs) sync* {
  outer:
  for (var i = 0; i < xs.length; i++) {
    final v = xs[i];
    if (v < 0) {
      continue outer;
    }
    if (v == 99) {
      break outer;
    }
    yield v;
    yield* [v + 100, v + 200];
  }
}
