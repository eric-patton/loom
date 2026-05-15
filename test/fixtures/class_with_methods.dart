class Person {
  final String firstName;
  final String lastName;
  int age = 0;

  Person({required this.firstName, required this.lastName, this.age = 0});

  String get fullName => '$firstName $lastName';

  bool isAdult() {
    return age >= 18;
  }

  static const String species = 'Homo sapiens';
}
