/// Integration test for `dmacro watch`, locking in per-file macro isolation
/// across recompiles.
///
/// Watch mode is a long-lived process that recompiles individual files on
/// change. Each recompile must start from a clean macro registry — so if a user
/// deletes a `defmacro` and saves, the now-undefined macro must stop resolving
/// instead of lingering from the previous compile's global registration.
///
/// This drives the real `bin/dmacro.dart watch` subprocess and polls the
/// generated output, rather than fixed sleeps, to stay reliable.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Polls [check] every 50ms until it returns true or [timeout] elapses.
Future<bool> _until(bool Function() check,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return check();
}

void main() {
  test('a removed defmacro stops resolving on watch recompile', () async {
    final dir = Directory.systemTemp.createTempSync('dmacro_watch_');
    final src = File('${dir.path}/m.dmacro');
    final out = File('${dir.path}/m.dart');

    // Version 1: defines `tag` and uses it.
    src.writeAsStringSync('''
defmacro tag(x) {
  unless (x) { throw Exception("untagged"); }
}
void use(bool b) { tag(b); }
''');

    final proc = await Process.start(
      'dart',
      ['run', 'bin/dmacro.dart', 'watch', dir.path],
      workingDirectory: Directory.current.path,
    );

    try {
      // Initial build: `tag` resolves, so the throw is inlined.
      final builtV1 = await _until(
          () => out.existsSync() && out.readAsStringSync().contains('throw Exception("untagged")'));
      expect(builtV1, isTrue,
          reason: 'initial watch build should expand the tag macro');

      // Version 2: the macro definition is removed but a call remains. The
      // watcher recompiles; with per-file isolation the stale `tag` must be
      // gone, leaving a bare `tag(b);` call (not a re-expansion).
      src.writeAsStringSync('''
void use(bool b) { tag(b); }
''');

      final recompiled = await _until(() {
        if (!out.existsSync()) return false;
        final text = out.readAsStringSync();
        // The new source has no `defmacro`, so the marker of the new content is
        // the absence of the old expansion plus presence of the bare call.
        return text.contains('tag(b);') &&
            !text.contains('throw Exception("untagged")');
      });
      expect(recompiled, isTrue,
          reason: 'after removing the defmacro, the macro must not keep '
              'resolving from a stale global registration');
    } finally {
      proc.kill(ProcessSignal.sigkill);
      await proc.exitCode;
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
