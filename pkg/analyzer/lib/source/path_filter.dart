// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library source.path_filter;

import 'package:glob/glob.dart' as glob;
import 'package:path/path.dart';

/// Filter paths against a set of [ignorePatterns] relative to a [root]
/// directory. Paths outside of [root] are also ignored.
class PathFilter {
  /// The path context to use when manipulating paths.
  final Context pathContext;

  /// Path that all ignore patterns are relative to.
  final String root;

  /// List of ignore patterns that paths are tested against.
  final List<glob.Glob> _ignorePatterns = new List<glob.Glob>();

  /// Construct a new path filter rooted at [root] with [ignorePatterns].
  PathFilter(this.pathContext, this.root, List<String> ignorePatterns) {
    setIgnorePatterns(ignorePatterns);
  }

  /// Returns true if [path] should be ignored. A path is ignored if it is not
  /// contained in [root] or matches one of the ignore patterns.
  /// [path] is absolute or relative to [root].
  bool ignored(String path) {
    path = _canonicalize(path);
    return !_contained(path) || _match(path);
  }

  /// Set the ignore patterns.
  void setIgnorePatterns(List<String> ignorePatterns) {
    _ignorePatterns.clear();
    if (ignorePatterns != null) {
      for (var ignorePattern in ignorePatterns) {
        _ignorePatterns.add(new glob.Glob(ignorePattern));
      }
    }
  }

  /// Returns the absolute path of [path], relative to [root].
  String _canonicalize(String path) =>
      pathContext.normalize(pathContext.join(root, path));

  /// Returns true when [path] is contained inside [root].
  bool _contained(String path) => path.startsWith(root);

  /// Returns true if [path] matches any ignore patterns.
  bool _match(String path) {
    path = _relative(path);
    for (var glob in _ignorePatterns) {
      if (glob.matches(path)) {
        return true;
      }
    }
    return false;
  }

  /// Returns the relative portion of [path] from [root].
  String _relative(String path) => pathContext.relative(path, from: root);
}
