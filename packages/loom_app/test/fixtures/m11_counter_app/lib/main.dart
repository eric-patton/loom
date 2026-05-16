import 'package:flutter/material.dart';

import 'widgets/counter.dart';

void main() {
  runApp(const CounterApp());
}

class CounterApp extends StatelessWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Counter Demo',
      home: Counter(),
    );
  }
}
