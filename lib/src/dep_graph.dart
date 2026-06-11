/// Dependency graph for dmacro's watch mode.
///
/// When file A contains `importMacros("B")` or `useMacros("C")`, A depends on
/// B and C. If B or C changes, A must be recompiled.
///
/// The graph is populated during compilation via [recordDependency] and queried
/// by the watch mode via [dependentsOf].
library;

import 'dart:io';

/// Records dependency edges and answers reverse-dep queries.
class DependencyGraph {
  // Forward: source → set of files it imports/useMacros
  final _forward = <String, Set<String>>{};
  // Reverse: dependency → set of source files that depend on it
  final _reverse = <String, Set<String>>{};

  /// Record that [sourceFile] depends on [dependencyFile].
  /// Both paths should be absolute.
  void recordDependency(String sourceFile, String dependencyFile) {
    (_forward[sourceFile] ??= {}).add(dependencyFile);
    (_reverse[dependencyFile] ??= {}).add(sourceFile);
  }

  /// Returns all source files that (directly or transitively) depend on
  /// [changedFile], in topological order (dependents before their dependents).
  /// The changed file itself is not included.
  List<String> dependentsOf(String changedFile) {
    final visited = <String>{};
    final result = <String>[];

    void visit(String file) {
      final deps = _reverse[file];
      if (deps == null) return;
      for (final dep in deps) {
        if (visited.add(dep)) {
          result.add(dep);
          visit(dep); // transitive
        }
      }
    }

    visit(changedFile);
    return result;
  }

  /// Returns the set of files that [sourceFile] directly depends on.
  List<String> importsOf(String sourceFile) =>
      List<String>.from(_forward[sourceFile] ?? const []);

  /// Clears all recorded edges for [sourceFile] before recompiling it.
  /// Call this each time a file is recompiled so stale edges don't persist.
  void clearSource(String sourceFile) {
    final oldDeps = _forward.remove(sourceFile);
    if (oldDeps != null) {
      for (final dep in oldDeps) {
        _reverse[dep]?.remove(sourceFile);
        if (_reverse[dep]?.isEmpty ?? false) _reverse.remove(dep);
      }
    }
  }
}

/// Process-level singleton so `_compileSingle` and `_watchCmd` share the
/// same graph without threading it through every call.
final depGraph = DependencyGraph();

/// Normalises a path from a macro directive to an absolute path.
/// [sourceFile] is the file containing the directive; [target] is the raw
/// string passed to `importMacros` / `useMacros` — either absolute or
/// relative to the working directory (dmacro resolves from CWD, not from
/// the source file's directory, matching the existing behaviour).
String resolveDepPath(String target) {
  final f = File(target);
  return f.isAbsolute ? f.path : f.absolute.path;
}
