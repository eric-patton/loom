import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../services/widget_filter_service.dart';
import '../../../state/providers.dart';

/// Right-pane Interface tab: lists every Dart file in the open project,
/// classified by `WidgetFilterService` into modeled / opaque-root /
/// no-build / parse-error. Modeled files are clickable; everything
/// else is greyed-out with an indicator dot. Clicking a modeled file
/// opens a tab in the center pane.
class InterfaceTab extends ConsumerWidget {
  const InterfaceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = ref.watch(projectControllerProvider);
    final theme = Theme.of(context);
    if (ps == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No project open.\n'
            'Use File → Open Project to start.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    final filter = ref.watch(widgetFilterServiceProvider);
    final widgetIndex = ref.watch(projectWidgetIndexProvider);
    final uris = ps.sources.keys.toList()..sort();

    return ListView.builder(
      itemCount: uris.length,
      itemBuilder: (context, i) {
        final uri = uris[i];
        final source = ps.sources[uri]!;
        final visible = widgetIndex?.widgetsVisibleFrom(uri) ?? const {};
        final classification = filter.classify(
          uri: uri,
          source: source,
          projectWidgets: visible,
        );
        final shortName = _relativeFromRoot(uri, ps.snapshot.rootPath);
        return InkWell(
          onTap: classification.isModeled
              ? () => ref.read(workspaceControllerProvider).openFile(uri)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _colorFor(classification.kind, theme.colorScheme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shortName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: classification.isModeled
                          ? null
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Color _colorFor(FileWidgetRootKind kind, ColorScheme scheme) =>
      switch (kind) {
        FileWidgetRootKind.modeled => Colors.green,
        FileWidgetRootKind.opaqueRoot => Colors.amber,
        FileWidgetRootKind.noBuild => scheme.outlineVariant,
        FileWidgetRootKind.parseError => scheme.error,
      };

  static String _relativeFromRoot(String uri, String rootPath) {
    try {
      final path = Uri.parse(uri).toFilePath();
      final rel = p.relative(path, from: rootPath);
      return rel.replaceAll(r'\', '/');
    } on Object {
      return uri;
    }
  }
}
