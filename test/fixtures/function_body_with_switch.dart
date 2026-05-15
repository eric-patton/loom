// Sample function body for M8.0e — exercises switch with legacy +
// pattern cases, a `when` guard, and a default.

String describe(Object value) {
  switch (value) {
    case 0:
      return 'zero';
    case int n when n < 0:
      return 'negative';
    case int n when n > 100:
      return 'big';
    case String s:
      return 'string:$s';
    default:
      return 'unknown';
  }
}
