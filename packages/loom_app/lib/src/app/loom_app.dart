import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// The Loom editor's top-level `Widget`. Wraps the shell in a
/// `ProviderScope` and the standard Material theme.
class LoomApp extends StatelessWidget {
  const LoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Loom',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: buildRoot(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
