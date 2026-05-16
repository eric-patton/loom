// Sample function body for M8.0d — exercises a top-level throw statement.

int requirePositive(int n) {
  if (n <= 0) {
    throw ArgumentError('n must be positive');
  }
  return n;
}
