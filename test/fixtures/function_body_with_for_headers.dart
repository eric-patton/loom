// Sample function body for M8.2 — exercises c-style + for-each
// for-loop header shapes.

int demo(List<int> xs) {
  var total = 0;
  for (var i = 0; i < xs.length; i++) {
    total = total + xs[i];
  }
  for (final user in xs) {
    total = total + user;
  }
  for (int x in xs) {
    total = total + x;
  }
  return total;
}
