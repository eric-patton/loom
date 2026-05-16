/// Barrel: every provider in one import. Shell widgets reach into the
/// state layer via this file so refactoring (splitting / merging the
/// individual provider files) doesn't ripple through the UI.
library;

export 'document_providers.dart';
export 'kernel_providers.dart';
export 'models/open_document.dart';
export 'notifiers/open_documents_notifier.dart';
export 'project_providers.dart';
export 'selection_providers.dart';
