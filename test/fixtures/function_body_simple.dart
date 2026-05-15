// Sample function body for M8.0a — exercises variable declarations,
// expression statements, and return statements.

int registerUser(String email) {
  final normalized = email.toLowerCase();
  final id = nextId();
  log('registering: $normalized');
  saveUser(id, normalized);
  return id;
}

int nextId() => 42;
void log(String message) {}
void saveUser(int id, String email) {}
