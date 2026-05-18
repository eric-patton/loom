import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/kernel_adapter.dart';
import '../../state/providers.dart';
import 'inline_text_edit_state.dart';

/// Overlay `TextField` positioned at a `Text` widget's rectangle.
/// Commits the new literal through the same workspace controller as
/// the inspector's `StringPropertyEditor` (so undo/redo + format-on-
/// save behavior is identical), and closes itself afterward.
///
/// Since M13.5 the editor is positioned by its parent (a
/// `Positioned`/`_PositionedFollowingKey` over the materialized Text
/// node's probe rect); it no longer takes its own `rect` parameter.
class InlineTextEditor extends ConsumerStatefulWidget {
  const InlineTextEditor({super.key, required this.target});

  final InlineTextEditTarget target;

  @override
  ConsumerState<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends ConsumerState<InlineTextEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _lastCommitted = '';
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.target.original.value);
    _lastCommitted = widget.target.original.value;
    _focusNode = FocusNode()..addListener(_onFocusChange);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && !_committing) {
      _commitAndClose();
    }
  }

  Future<void> _commitAndClose() async {
    if (_committing) return;
    _committing = true;
    final newText = _controller.text;
    if (newText != _lastCommitted) {
      _lastCommitted = newText;
      final newValue = StringLiteralValue(
        value: newText,
        usesDoubleQuotes: widget.target.original.usesDoubleQuotes,
        span: widget.target.original.span,
      );
      await ref.read(workspaceControllerProvider).applyPropertyEdit(
            uri: widget.target.documentUri,
            oldValue: widget.target.original,
            newValue: newValue,
          );
    }
    if (!mounted) return;
    ref.read(inlineTextEditProvider.notifier).state = null;
  }

  void _cancel() {
    ref.read(inlineTextEditProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (event.logicalKey.keyLabel == 'Escape') _cancel();
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          onSubmitted: (_) {
            _commitAndClose();
          },
        ),
      ),
    );
  }
}
