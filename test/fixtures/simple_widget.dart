import 'package:flutter/material.dart';

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Hello, world!'),
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Welcome to Loom.'),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Edit the source; the model follows.'),
        ),
        Text('Final entry without const'),
      ],
    );
  }
}
