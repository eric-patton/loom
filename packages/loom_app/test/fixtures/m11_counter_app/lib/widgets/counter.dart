import 'package:flutter/material.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Hello',
            ),
            SizedBox(
              height: 16,
              width: 100,
            ),
            Text(
              'World',
            ),
            SizedBox(
              height: 8.0,
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Click me',
              ),
            ),
            Visibility(
              visible: true,
              child: Text(
                'Visible',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
