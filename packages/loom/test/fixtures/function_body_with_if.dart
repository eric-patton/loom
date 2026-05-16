// Sample function body for M8.0b — exercises if/else control flow.

String classify(int score) {
  final clamped = score.clamp(0, 100);
  log('classifying: $clamped');
  if (clamped >= 90) {
    log('grade A path');
    return 'A';
  } else {
    return 'lower';
  }
}

void log(String message) {}
