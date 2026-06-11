/// Worker side of `useMacros` — runs inside a spawned isolate.
///
/// A `useMacros("...dart")` directive loads a Dart macro library without any
/// `tool/dmacro.dart` entry point. Since Dart has no runtime reflection and
/// closures cannot cross isolate boundaries, the library is loaded in a child
/// isolate that owns its own macro registry. The parent registers a thin proxy
/// per macro name; each proxy round-trips one `(name, args) → Node` call here.
///
/// The parent's expander drives all recursion, so this worker only ever
/// evaluates a single macro call per request — it never expands the result.
///
/// A generated bootstrap (see `macro_loader.dart`) imports the user library and
/// calls [runMacroWorker] from its `main(args, SendPort)`.
library;

import 'dart:isolate';

import 'async_expand.dart';
import 'core.dart';
import 'node_codec.dart';

/// Entry point for the worker isolate. [register] callbacks populate this
/// isolate's macro registry (by calling `defmacro` / `defAsyncMacro`); their
/// registered names are reported back to the parent over [handshake].
///
/// Protocol:
///   parent ← {'port': SendPort, 'names': List<String>}   (handshake)
///   parent → {'id': int, 'name': String, 'args': encoded, 'reply': SendPort}
///   parent ← {'id': int, 'ok': encodedNode}  |  {'id': int, 'err': String}
///   parent → 'shutdown'  (closes the worker)
Future<void> runMacroWorker(
  SendPort handshake,
  List<void Function()> register,
) async {
  for (final r in register) {
    r();
  }

  final requests = ReceivePort();
  handshake.send({
    'port': requests.sendPort,
    'names': {...asyncMacroNames(), ...syncMacroNames()}.toList(),
  });

  await for (final message in requests) {
    if (message == 'shutdown') {
      requests.close();
      break;
    }
    final req = message as Map;
    final reply = req['reply'] as SendPort;
    final id = req['id'];
    try {
      final name = req['name'] as String;
      final args = decodeNode(req['args']) as List;
      final result = await invokeMacroOnce(name, args);
      reply.send({'id': id, 'ok': encodeNode(result)});
    } catch (e) {
      reply.send({'id': id, 'err': '$e'});
    }
  }
}
