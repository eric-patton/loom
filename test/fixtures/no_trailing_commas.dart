// Style hint check: this fixture deliberately uses no trailing commas
// anywhere, so `hasTrailingComma` must be `false` on every node.

import 'package:flutter/material.dart';

class NoTrailingCommas extends StatelessWidget {
  const NoTrailingCommas({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [const Text('a'), const Text('b'), const Text('c')]);
  }
}
