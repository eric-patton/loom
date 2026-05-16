import 'package:flutter/material.dart';

void main() {
  runApp(const LoomApp());
}

class LoomApp extends StatelessWidget {
  const LoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loom',
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Loom — visual editor (M11 placeholder)'),
        ),
      ),
    );
  }
}
