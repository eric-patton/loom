// Exercises every M1 PropertyValue variant the simple fixture didn't reach:
// BoolLiteralValue, NullLiteralValue, ColorValue, and EnumReferenceValue
// (Icons.X, MainAxisAlignment.X, TextDirection.X).

import 'package:flutter/material.dart';

class EnumAndBool extends StatelessWidget {
  const EnumAndBool({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Variants demo',
      debugShowCheckedModeBanner: false,
      home: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Text with explicit direction',
            textDirection: TextDirection.ltr,
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Container(color: Color(0xFF112233)),
          ),
          IconButton(
            icon: Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: null,
          ),
          FloatingActionButton(
            tooltip: 'Add',
            onPressed: null,
            child: Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
