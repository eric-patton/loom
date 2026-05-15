class Money {
  final int cents;
  final String currency;

  const Money(this.cents, this.currency);

  const Money.zero()
      : cents = 0,
        currency = 'USD';

  factory Money.fromString(String input) {
    final parts = input.split(' ');
    return Money(int.parse(parts[0]), parts[1]);
  }

  factory Money.usd(int cents) = Money;

  Money operator +(Money other) {
    return Money(cents + other.cents, currency);
  }

  @override
  String toString() => '$cents $currency';
}
