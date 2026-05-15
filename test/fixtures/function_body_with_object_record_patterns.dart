// Sample function body for M8.0g — exercises object + record patterns
// with positional, explicit-named, and shorthand fields.

String classify(Object value) {
  switch (value) {
    case Point(x: 0, y: 0):
      return 'origin';
    case Point(x: var x, y: var y) when x == y:
      return 'diagonal:$x';
    case Rect(:var width, :var height):
      return 'rect:${width}x$height';
    case (int a, int b):
      return 'pair:$a,$b';
    case (x: var x, y: var y):
      return 'named:$x,$y';
    default:
      return 'other';
  }
}

class Point {
  final int x;
  final int y;
  const Point({required this.x, required this.y});
}

class Rect {
  final int width;
  final int height;
  const Rect({required this.width, required this.height});
}
