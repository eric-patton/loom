import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/state/models/open_document.dart';
import 'package:loom_app/src/state/notifiers/open_documents_notifier.dart';

void main() {
  late ProviderContainer container;
  late NotifierProvider<OpenDocumentsNotifier, Map<String, OpenDocument>>
      provider;

  setUp(() {
    provider =
        NotifierProvider<OpenDocumentsNotifier, Map<String, OpenDocument>>(
            OpenDocumentsNotifier.new);
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  OpenDocument doc(String uri, {String source = 'a'}) => OpenDocument(
        uri: uri,
        pathOnDisk: uri,
        diskSource: source,
        workingSource: source,
      );

  test('starts empty', () {
    expect(container.read(provider), isEmpty);
  });

  test('open() adds a new entry', () {
    container.read(provider.notifier).open(doc('file://a.dart'));
    expect(container.read(provider), hasLength(1));
    expect(container.read(provider).containsKey('file://a.dart'), isTrue);
  });

  test('close() removes the entry', () {
    final n = container.read(provider.notifier);
    n.open(doc('file://a.dart'));
    n.open(doc('file://b.dart'));
    n.close('file://a.dart');
    expect(container.read(provider).keys, ['file://b.dart']);
  });

  test('reset() clears all entries', () {
    final n = container.read(provider.notifier);
    n.open(doc('file://a.dart'));
    n.open(doc('file://b.dart'));
    n.reset();
    expect(container.read(provider), isEmpty);
  });

  test('updateWorking changes only the working source', () {
    final n = container.read(provider.notifier);
    n.open(doc('file://a.dart', source: 'disk'));
    n.updateWorking('file://a.dart', 'working');
    final after = container.read(provider)['file://a.dart']!;
    expect(after.diskSource, 'disk');
    expect(after.workingSource, 'working');
    expect(after.isDirty, isTrue);
  });

  test('markSaved syncs both disk and working sources', () {
    final n = container.read(provider.notifier);
    n.open(doc('file://a.dart', source: 'before'));
    n.updateWorking('file://a.dart', 'after');
    n.markSaved('file://a.dart', 'after');
    final saved = container.read(provider)['file://a.dart']!;
    expect(saved.diskSource, 'after');
    expect(saved.workingSource, 'after');
    expect(saved.isDirty, isFalse);
  });

  test('updateWorking on unknown URI is a no-op', () {
    final before = container.read(provider);
    container.read(provider.notifier).updateWorking('missing', 'x');
    expect(container.read(provider), same(before));
  });
}
