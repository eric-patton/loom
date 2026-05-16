// Sample function body for M8.0d — exercises a do-while loop.

int countDownTo(int start, int floor) {
  var n = start;
  do {
    n = n - 1;
  } while (n > floor);
  return n;
}
