// Sample function body for M8.0h — exercises the remaining 8 pattern
// kinds (list, map, relational, null-check, null-assert, cast,
// parenthesized, logical-and).

String catalog(Object value) {
  switch (value) {
    case [int a, int b]:
      return 'pair:$a,$b';
    case [int first, ...]:
      return 'starts:$first';
    case [int head, ...List<int> tail]:
      return 'head=$head,tail=$tail';
    case {'name': String name}:
      return 'named:$name';
    case > 100:
      return 'big';
    case == 'zero':
      return 'zero-text';
    case var x? when x is num:
      return 'non-null-num:$x';
    case var y!:
      return 'asserted:$y';
    case var z as int:
      return 'cast:$z';
    case (1 || 2 || 3):
      return 'small-parens';
    case int n && > 0:
      return 'positive-int:$n';
    default:
      return 'other';
  }
}
