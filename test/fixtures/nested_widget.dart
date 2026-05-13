import 'package:flutter/material.dart';

class DeeplyNested extends StatelessWidget {
  const DeeplyNested({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(4.0),
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: Padding(
          padding: EdgeInsets.all(12.0),
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: Text('Deeply nested.')),
          ),
        ),
      ),
    );
  }
}
