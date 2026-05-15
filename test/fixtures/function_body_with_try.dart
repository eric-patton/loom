// Sample function body for M8.0d — exercises try / on T catch / finally.

int parseOrDefault(String text, int fallback) {
  var result = fallback;
  try {
    result = int.parse(text);
  } on FormatException catch (e) {
    log('format: $e');
    result = fallback;
  } catch (e, s) {
    log('other: $e at $s');
    result = fallback;
  } finally {
    log('done');
  }
  return result;
}

void log(Object msg) {}
