import 'package:flutter/material.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});

  Widget _buildTitle() {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Text('Page title'),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        const Text('Line one'),
        const Text('Line two'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTitle(),
        _buildContent(),
      ],
    );
  }
}
