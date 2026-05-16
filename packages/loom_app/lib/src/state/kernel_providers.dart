import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/edit_history_service.dart';
import '../services/file_system_service.dart';
import '../services/format_service.dart';
import '../services/kernel_adapter.dart';
import '../services/widget_filter_service.dart';

/// Single instance of the kernel seam. Stateless; the `const` constructor
/// lets it live for the lifetime of the app.
final kernelAdapterProvider =
    Provider<KernelAdapter>((ref) => const KernelAdapter());

/// Stateless filesystem service. Lives as long as the app.
final fileSystemServiceProvider =
    Provider<FileSystemService>((ref) => const FileSystemService());

/// File-classification helper; depends on the kernel seam for parsing.
final widgetFilterServiceProvider = Provider<WidgetFilterService>(
  (ref) => WidgetFilterService(ref.watch(kernelAdapterProvider)),
);

/// M11 stub format service (no-op). M12 replaces with `package:dart_style`.
final formatServiceProvider =
    Provider<FormatService>((ref) => const FormatService());

/// M11 stub edit-history service (records nothing). M12 wires Ctrl+Z/Y.
final editHistoryServiceProvider =
    Provider<EditHistoryService>((ref) => const EditHistoryService());
