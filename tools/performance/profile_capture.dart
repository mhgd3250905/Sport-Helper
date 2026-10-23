// Internal profile VM-service capture; uses only Dart's standard library.
// Reads the local flutter-run log so callers need not copy a VM-service token.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart profile_capture.dart <flutter-run.log> '
      '<snapshot|reset|scenario|end|timeline-start|timeline-stop> [name|output]',
    );
    exitCode = 2;
    return;
  }
  final log = await File(arguments[0]).readAsString();
  final matches = RegExp(
    r'available at: (http://127\.0\.0\.1:[^\s]+/)',
  ).allMatches(log);
  if (matches.isEmpty) throw StateError('No local profile VM service in log');
  final endpoint = Uri.parse(matches.first.group(1)!);
  final socket = await WebSocket.connect(
    endpoint.replace(scheme: 'ws', path: '${endpoint.path}ws').toString(),
  );
  var requestId = 0;
  final pending = <int, Completer<Map<String, dynamic>>>{};
  final subscription = socket.listen((event) {
    final message = jsonDecode(event as String) as Map<String, dynamic>;
    final id = message['id'];
    if (id is int) pending.remove(id)?.complete(message);
  });
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final id = ++requestId;
    final completer = Completer<Map<String, dynamic>>();
    pending[id] = completer;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final response = await completer.future.timeout(
      const Duration(seconds: 20),
    );
    if (response['error'] != null) throw StateError('${response['error']}');
    return response['result'] as Map<String, dynamic>;
  }

  try {
    final vm = await rpc('getVM');
    final isolates = vm['isolates'] as List;
    final mainIsolate = isolates.cast<Map>().firstWhere(
      (i) => i['name'] == 'main',
    );
    final isolateId = mainIsolate['id'] as String;
    Map<String, dynamic> result;
    switch (arguments[1]) {
      case 'timeline-start':
        await rpc('clearVMTimeline');
        result = await rpc('setVMTimelineFlags', {
          'recordedStreams': ['Dart', 'Embedder', 'GC'],
        });
      case 'timeline-stop':
        result = await rpc('getVMTimeline');
        await rpc('setVMTimelineFlags', {'recordedStreams': <String>[]});
      case 'snapshot':
      case 'reset':
      case 'scenario':
      case 'end':
        result = await rpc('ext.smartfit.performance', {
          'isolateId': isolateId,
          'action': arguments[1] == 'end' ? 'endScenario' : arguments[1],
          if (arguments[1] == 'scenario' && arguments.length > 2)
            'scenario': arguments[2],
        });
      default:
        throw ArgumentError('Unknown capture action');
    }
    if ((arguments[1] == 'snapshot' || arguments[1] == 'timeline-stop') &&
        arguments.length > 2) {
      final file = File(arguments[2]);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
      );
      stdout.writeln('Saved ${arguments[1]} capture to ${file.path}');
    } else {
      stdout.writeln(
        jsonEncode({
          'action': arguments[1],
          'recordedFrameCount': result['recordedFrameCount'],
          'currentPage': result['currentPage'],
          'currentScenario': result['currentScenario'],
        }),
      );
    }
  } finally {
    await socket.close().timeout(const Duration(seconds: 2));
    await subscription.cancel();
  }
}
