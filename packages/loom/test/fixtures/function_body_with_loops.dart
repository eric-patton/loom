// Sample function body for M8.0c — exercises for + while loops.

int sumUpTo(int n) {
  var total = 0;
  for (var i = 0; i < n; i++) {
    total = total + i;
  }
  var remaining = total;
  while (remaining > 100) {
    remaining = remaining - 100;
  }
  return remaining;
}
