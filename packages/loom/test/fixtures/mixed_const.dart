import 'package:flutter/material.dart';

class MixedConst extends StatelessWidget {
  const MixedConst({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('I am const'),
        Text('I am not const'),
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Const padding, inner Text inherits const'),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: const Text('Non-const padding, inner Text explicitly const'),
        ),
      ],
    );
  }
}
