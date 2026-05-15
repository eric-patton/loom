// Sample compilation unit exercising every directive form.

library example.directives;

import 'dart:async';
import 'dart:io' as io;
import 'package:foo/bar.dart' show foo, bar;
import 'package:bar/baz.dart' hide quux;
import 'package:lib/deferred.dart' deferred as d;

export 'src/api.dart';
export 'src/legacy.dart' hide Old;

part 'helper.dart';

void main() {}
