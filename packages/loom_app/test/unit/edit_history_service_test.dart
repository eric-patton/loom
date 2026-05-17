import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/edit_history_service.dart';
import 'package:loom_app/src/state/providers.dart';

void main() {
  group('EditHistoryService notifier', () {
    late ProviderContainer container;
    late EditHistoryService notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(editHistoryProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('starts empty', () {
      expect(container.read(editHistoryProvider), isEmpty);
      expect(notifier.canUndo('file:///a.dart'), isFalse);
      expect(notifier.canRedo('file:///a.dart'), isFalse);
    });

    test('record pushes onto undo stack and leaves redo empty', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'edit 1',
        beforeSource: 'A',
        afterSource: 'B',
      );
      final history = container.read(editHistoryProvider)['file:///a.dart']!;
      expect(history.undoStack, hasLength(1));
      expect(history.undoStack.single.beforeSource, 'A');
      expect(history.undoStack.single.afterSource, 'B');
      expect(history.redoStack, isEmpty);
      expect(notifier.canUndo('file:///a.dart'), isTrue);
      expect(notifier.canRedo('file:///a.dart'), isFalse);
    });

    test('record with identical before/after is a no-op', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'noop',
        beforeSource: 'same',
        afterSource: 'same',
      );
      expect(container.read(editHistoryProvider), isEmpty);
    });

    test('popUndo returns the most recent entry and moves it to redo', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'e1',
        beforeSource: 'A',
        afterSource: 'B',
      );
      notifier.record(
        uri: 'file:///a.dart',
        label: 'e2',
        beforeSource: 'B',
        afterSource: 'C',
      );
      final popped = notifier.popUndo('file:///a.dart');
      expect(popped, isNotNull);
      expect(popped!.label, 'e2');
      expect(popped.beforeSource, 'B');
      expect(popped.afterSource, 'C');

      final history = container.read(editHistoryProvider)['file:///a.dart']!;
      expect(history.undoStack, hasLength(1));
      expect(history.undoStack.single.label, 'e1');
      expect(history.redoStack, hasLength(1));
      expect(history.redoStack.single.label, 'e2');
    });

    test('popRedo moves entry back onto undo stack', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'e1',
        beforeSource: 'A',
        afterSource: 'B',
      );
      notifier.popUndo('file:///a.dart');
      final popped = notifier.popRedo('file:///a.dart');
      expect(popped, isNotNull);
      expect(popped!.label, 'e1');
      final history = container.read(editHistoryProvider)['file:///a.dart']!;
      expect(history.undoStack, hasLength(1));
      expect(history.redoStack, isEmpty);
    });

    test('a fresh record clears the redo stack', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'e1',
        beforeSource: 'A',
        afterSource: 'B',
      );
      notifier.popUndo('file:///a.dart');
      expect(notifier.canRedo('file:///a.dart'), isTrue);

      notifier.record(
        uri: 'file:///a.dart',
        label: 'e2',
        beforeSource: 'A',
        afterSource: 'C',
      );
      expect(notifier.canRedo('file:///a.dart'), isFalse);
    });

    test('popUndo on empty stack returns null and does not mutate state', () {
      final result = notifier.popUndo('file:///a.dart');
      expect(result, isNull);
      expect(container.read(editHistoryProvider), isEmpty);
    });

    test('per-URI isolation: edits on one doc do not affect another', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'a-edit',
        beforeSource: 'A0',
        afterSource: 'A1',
      );
      notifier.record(
        uri: 'file:///b.dart',
        label: 'b-edit',
        beforeSource: 'B0',
        afterSource: 'B1',
      );
      expect(notifier.canUndo('file:///a.dart'), isTrue);
      expect(notifier.canUndo('file:///b.dart'), isTrue);

      notifier.popUndo('file:///a.dart');
      expect(notifier.canUndo('file:///a.dart'), isFalse);
      expect(notifier.canUndo('file:///b.dart'), isTrue);
    });

    test('clear drops only the specified URI', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'e1',
        beforeSource: 'A',
        afterSource: 'B',
      );
      notifier.record(
        uri: 'file:///b.dart',
        label: 'e1',
        beforeSource: 'A',
        afterSource: 'B',
      );
      notifier.clear('file:///a.dart');
      expect(
          container.read(editHistoryProvider).keys, <String>['file:///b.dart']);
    });

    test('clearAll wipes everything', () {
      notifier.record(
        uri: 'file:///a.dart',
        label: 'e1',
        beforeSource: 'A',
        afterSource: 'B',
      );
      notifier.clearAll();
      expect(container.read(editHistoryProvider), isEmpty);
    });

    test('DocumentHistory.canUndo/canRedo reflect stack contents', () {
      const empty = DocumentHistory();
      expect(empty.canUndo, isFalse);
      expect(empty.canRedo, isFalse);

      const withUndo = DocumentHistory(
        undoStack: <HistoryEntry>[
          HistoryEntry(label: 'e', beforeSource: '', afterSource: ''),
        ],
      );
      expect(withUndo.canUndo, isTrue);
      expect(withUndo.canRedo, isFalse);
    });
  });
}
