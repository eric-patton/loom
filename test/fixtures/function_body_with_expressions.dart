// Sample function body for M8.2 — exercises modeled expression
// kinds (identifier, literal, method invocation, binary) as
// top-level statement expressions.

void demo(int x) {
  print(x);
  log('hello');
  doStuff();
  x.toString();
  x;
  42;
  'literal';
  true;
  null;
  x + 1;
  x == 0;
}

void print(Object o) {}
void log(Object o) {}
void doStuff() {}
