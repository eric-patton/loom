import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';
import '../state/providers.dart';

/// Edits a `NumLiteralValue` (int or double). The `isDouble` source
/// hint is preserved so the byte diff stays minimal — `8` stays `8`,
/// `8.0` stays `8.0`. Typing a decimal forces double form even when
/// the source was an int.
class NumPropertyEditor extends ConsumerStatefulWidget {
  const NumPropertyEditor({
    super.key,
    required this.documentUri,
    required this.propertyName,
    required this.value,
  });

  final String documentUri;
  final String propertyName;
  final NumLiteralValue value;

  @override
  ConsumerState<NumPropertyEditor> createState() => _NumPropertyEditorState();
}

class _NumPropertyEditorState extends ConsumerState<NumPropertyEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastCommittedText;

  static String _displayValue(NumLiteralValue v) {
    if (v.isDouble) {
      final s = v.value.toString();
      return s.contains('.') ? s : '$s.0';
    }
    return v.value.toInt().toString();
  }

  @override
  void initState() {
    super.initState();
    _lastCommittedText = _displayValue(widget.value);
    _controller = TextEditingController(text: _lastCommittedText);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(NumPropertyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _displayValue(widget.value);
    if (next != _lastCommittedText && !_focusNode.hasFocus) {
      _controller.text = next;
      _lastCommittedText = next;
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
    final text = _controller.text.trim();
    final parsed = num.tryParse(text);
    if (parsed == null) {
      // Revert silently. Validation pill arrives in M12.
      _controller.text = _lastCommittedText;
      return;
    }
    final isDouble = widget.value.isDouble || text.contains('.');
    if (parsed == widget.value.value && isDouble == widget.value.isDouble) {
      return;
    }
    _lastCommittedText = text;
    final newValue = NumLiteralValue(
      value: parsed,
      isDouble: isDouble,
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
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      onSubmitted: (_) {
        _commit();
        _focusNode.unfocus();
      },
    );
  }
}
