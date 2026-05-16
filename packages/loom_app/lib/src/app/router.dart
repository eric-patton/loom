import 'package:flutter/material.dart';

import '../shell/main_shell_screen.dart';

/// Returns the single root screen for the M11 editor.
///
/// The file exists so M12+ can introduce a full router (multiple
/// windows, settings, about, etc.) without rewiring `LoomApp`.
Widget buildRoot() => const MainShellScreen();
