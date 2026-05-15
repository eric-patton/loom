// Synthetic Freezed/json_serializable-shaped fixture. Doesn't actually
// depend on Freezed at runtime — the analyzer only needs to parse the
// shape. Exercises M7.2's parameter modeling + annotation capture:
// class-level annotations (@freezed), member-level annotations
// (@JsonKey), and factory-constructor parameters with default values,
// `required`, named, and `this.x` field-formal forms.

@freezed
class Person {
  @JsonKey(name: 'first_name')
  final String firstName;

  @JsonKey(name: 'last_name')
  final String lastName;

  final int age;

  const Person({
    required this.firstName,
    required this.lastName,
    this.age = 0,
  });

  factory Person.guest() = _GuestPerson;
}
