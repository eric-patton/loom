// Sample function body for M8.0h — exercises switch expressions in
// variable initializers and return expressions.

String describe(int x) {
  final tier = switch (x) {
    0 => 'zero',
    1 || 2 || 3 => 'small',
    int n when n > 100 => 'big',
    _ => 'other',
  };
  return tier;
}

String describeReturn(int x) {
  return switch (x) {
    < 0 => 'negative',
    0 => 'zero',
    _ => 'positive',
  };
}
