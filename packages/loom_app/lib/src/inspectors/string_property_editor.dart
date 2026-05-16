import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';
import '../state/providers.dart';

/// Edits a `StringLiteralValue`. Commits on Enter or focus-loss. The
/// quote-style (`'…'` vs `"…"`) is preserved from the source so byte-
/// minimal diffs survive non-content changes.
class StringPropertyEditor extends ConsumerStatefulWidget {
  const StringPropertyEditor({
    super.key,
    required this.documentUri,
    required this.propertyName,
    required this.value,
  });

  final String documentUri;
  final String propertyName;
  final StringLiteralValue value;

  @override
  ConsumerState<StringPropertyEditor> createState() =>
      _StringPropertyEditorState();
}

class _StringPropertyEditorState extends ConsumerState<StringPropertyEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _lastCommittedText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.value);
    _lastCommittedText = widget.value.value;
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(StringPropertyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.value != _lastCommittedText && !_focusNode.hasFocus) {
      _controller.text = widget.value.value;
      _lastCommittedText = widget.value.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  Future<void> _commit() async {
    final newText = _controller.text;
    if (newText == _lastCommittedText) return;
    _lastCommittedText = newText;
    final newValue = StringLiteralValue(
      value: newText,
      usesDoubleQuotes: widget.value.usesDoubleQuotes,
      span: widget.value.span,
    );
    await ref.read(workspaceControllerProvider).applyPropertyEdit(
          uri: widget.documentUri,
          oldValue: widget.value,
          newValue: newValue,
        );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      onSubmitted: (_) {
        _commit();
        _focusNode.unfocus();
      },
    );
  }
}
