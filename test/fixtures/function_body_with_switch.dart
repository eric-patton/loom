// Sample function body for M8.0e/f — exercises switch with legacy +
// pattern cases, a `when` guard, a logical-or alternative, a wildcard,
// and a default.

String describe(Object value) {
  switch (value) {
    case 0:
      return 'zero';
    case 1 || 2 || 3:
      return 'small';
    case int n when n < 0:
      return 'negative';
    case int n when n > 100:
      return 'big';
    case String s:
      return 'string:$s';
    case int _:
      return 'other int';
    default:
      return 'unknown';
  }
}
