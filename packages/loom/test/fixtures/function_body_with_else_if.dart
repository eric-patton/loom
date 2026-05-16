// Sample function body for M8.0c — exercises else-if chains.

String tier(int score) {
  final clamped = score.clamp(0, 100);
  if (clamped >= 90) {
    return 'A';
  } else if (clamped >= 80) {
    return 'B';
  } else if (clamped >= 70) {
    return 'C';
  } else {
    return 'F';
  }
}
