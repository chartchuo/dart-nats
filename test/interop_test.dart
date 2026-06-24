import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

String findNatsExecutable() {
  if (Platform.isMacOS) {
    if (File('/opt/homebrew/bin/nats').existsSync()) {
      return '/opt/homebrew/bin/nats';
    }
  }
  return 'nats';
}

void main() {
  late String natsExec;

  setUpAll(() {
    natsExec = findNatsExecutable();
  });

  group('NATS CLI Interop Tests', () {
    late Client client;
    late JetStream js;

    setUp(() async {
      client = Client();
      await client.connect(Uri.parse('nats://localhost:4222'), retry: false);
      js = client.jetStream();
    });

    tearDown(() async {
      await client.close();
    });

    test('Standard Pub/Sub Interop: CLI Pub to Dart Sub', () async {
      final subject = 'interop.pubsub.${DateTime.now().millisecondsSinceEpoch}';
      final sub = client.sub(subject);

      final completer = Completer<Message>();
      final streamSub = sub.stream.listen((msg) {
        if (!completer.isCompleted) {
          completer.complete(msg);
        }
      });

      // Run nats pub from CLI
      final res = await Process.run(natsExec, [
        'pub',
        subject,
        'hello-from-cli',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(res.exitCode, equals(0), reason: 'CLI pub failed: ${res.stderr}');

      final msg = await completer.future.timeout(const Duration(seconds: 5));
      expect(msg.string, equals('hello-from-cli'));

      await streamSub.cancel();
      client.unSub(sub);
    });

    test('KeyValue Store Interop: Dart Put -> CLI Get -> CLI Put -> Dart Get',
        () async {
      final bucket = 'interop_kv_${DateTime.now().millisecondsSinceEpoch}';
      final kv = await js.keyValue(bucket, create: true, storage: 'memory');

      // 1. Dart Put
      await kv.putString('mykey', 'dart-value');

      // 2. CLI Get
      final resGet = await Process.run(natsExec, [
        'kv',
        'get',
        bucket,
        'mykey',
        '--raw',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resGet.exitCode, equals(0),
          reason: 'CLI kv get failed: ${resGet.stderr}');
      expect(resGet.stdout.toString().trim(), equals('dart-value'));

      // 3. CLI Put
      final resPut = await Process.run(natsExec, [
        'kv',
        'put',
        bucket,
        'mykey',
        'cli-value',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resPut.exitCode, equals(0),
          reason: 'CLI kv put failed: ${resPut.stderr}');

      // 4. Dart Get
      final entry = await kv.get('mykey');
      expect(entry, isNotNull);
      expect(entry!.string, equals('cli-value'));

      // Clean up bucket
      await js.deleteStream('KV_$bucket');
    });

    test('Object Store Interop: CLI Put -> Dart Get -> Dart Put -> CLI Get',
        () async {
      final bucket = 'interop_obj_${DateTime.now().millisecondsSinceEpoch}';
      final os = await js.objectStore(bucket, create: true, storage: 'memory');

      // Create a temporary file with unique content
      final tempDir = Directory.systemTemp.createTempSync('nats_interop');
      final tempFile = File('${tempDir.path}/test.txt');
      final uniqueContent =
          'Unique content for interop object store: ${DateTime.now().toIso8601String()}';
      tempFile.writeAsStringSync(uniqueContent);

      // 1. CLI Put
      final resPut = await Process.run(natsExec, [
        'object',
        'put',
        bucket,
        tempFile.path,
        '--name',
        'cli-file',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resPut.exitCode, equals(0),
          reason: 'CLI object put failed: ${resPut.stderr}');

      // 2. Dart Get
      final retrievedData = await os.getString('cli-file');
      expect(retrievedData, equals(uniqueContent));

      // 3. Dart Put
      final dartContent = 'Hello from Dart Object Store! ' *
          1000; // ~30KB to ensure chunking is tested a bit
      await os.putString('dart-file', dartContent);

      // 4. CLI Get
      final destFile = File('${tempDir.path}/retrieved.txt');
      final resGet = await Process.run(natsExec, [
        'object',
        'get',
        bucket,
        'dart-file',
        '-O',
        destFile.path,
        '-f',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resGet.exitCode, equals(0),
          reason: 'CLI object get failed: ${resGet.stderr}');
      expect(destFile.readAsStringSync(), equals(dartContent));

      // Cleanup files and bucket
      tempDir.deleteSync(recursive: true);
      await js.deleteStream('OBJ_$bucket');
    });

    test('Standard Pub/Sub Interop: Dart Pub to CLI Sub', () async {
      final subject =
          'interop.pubsub.dart2cli.${DateTime.now().millisecondsSinceEpoch}';

      // Start CLI subscriber that quits after receiving 1 message
      final process = await Process.start(natsExec, [
        'sub',
        subject,
        '--count=1',
        '--raw',
        '-s',
        'nats://localhost:4222',
      ]);

      // Give CLI time to subscribe
      await Future.delayed(const Duration(milliseconds: 300));

      // Publish from Dart client
      await client.pubString(subject, 'hello-from-dart');

      // Wait for process to exit
      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 5));
      expect(exitCode, equals(0), reason: 'CLI sub failed');

      final output = await process.stdout.transform(utf8.decoder).join();
      expect(output.trim(), equals('hello-from-dart'));
    });

    test('Request/Reply Interop: CLI Request to Dart Reply', () async {
      final subject =
          'interop.reqrep.cli2dart.${DateTime.now().millisecondsSinceEpoch}';
      final sub = client.sub(subject);

      final streamSub = sub.stream.listen((msg) {
        msg.respondString('reply-from-dart');
      });

      // Run CLI request
      final res = await Process.run(natsExec, [
        'request',
        subject,
        'hello-from-cli',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(res.exitCode, equals(0),
          reason: 'CLI request failed: ${res.stderr}');
      expect(res.stdout.toString(), contains('reply-from-dart'));

      await streamSub.cancel();
      client.unSub(sub);
    });

    test('Request/Reply Interop: Dart Request to CLI Reply', () async {
      final subject =
          'interop.reqrep.dart2cli.${DateTime.now().millisecondsSinceEpoch}';

      // Start CLI responder that responds and exits after 1 request
      final process = await Process.start(natsExec, [
        'reply',
        subject,
        'reply-from-cli: {{Request}}',
        '--count=1',
        '-s',
        'nats://localhost:4222',
      ]);

      // Give CLI time to start the responder
      await Future.delayed(const Duration(milliseconds: 300));

      // Request from Dart
      final response = await client.request(
        subject,
        Uint8List.fromList(utf8.encode('hello-from-dart')),
        timeout: const Duration(seconds: 5),
      );
      expect(response.string, equals('reply-from-cli: hello-from-dart'));

      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 5));
      expect(exitCode == 0 || exitCode == 1, isTrue,
          reason:
              'CLI responder failed to exit cleanly (exit code: $exitCode)');
    });

    test('JetStream Stream Interop: Created from CLI -> Read/Write in Dart',
        () async {
      final streamName = 'cli_stream_${DateTime.now().millisecondsSinceEpoch}';
      final subject =
          'cli.stream.test.${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create stream from CLI
      final resCreate = await Process.run(natsExec, [
        'stream',
        'add',
        streamName,
        '--subjects',
        subject,
        '--storage',
        'memory',
        '--defaults',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resCreate.exitCode, equals(0),
          reason: 'CLI stream creation failed: ${resCreate.stderr}');

      // 2. Publish from CLI
      final resPub = await Process.run(natsExec, [
        'pub',
        subject,
        'msg-from-cli',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resPub.exitCode, equals(0),
          reason: 'CLI pub to stream failed: ${resPub.stderr}');

      // 3. Verify and read in Dart
      final info = await js.streamInfo(streamName);
      expect(info.config.name, equals(streamName));
      expect(info.state.messages, equals(1));

      // 4. Clean up stream from Dart
      await js.deleteStream(streamName);
    });

    test('JetStream Stream Interop: Created from Dart -> Read/Write from CLI',
        () async {
      final streamName = 'dart_stream_${DateTime.now().millisecondsSinceEpoch}';
      final subject =
          'dart.stream.test.${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create stream in Dart
      await js.createStream(StreamConfig(
        name: streamName,
        subjects: [subject],
        storage: 'memory',
      ));

      // 2. Publish from Dart
      await js.publishString(subject, 'msg-from-dart');

      // 3. Verify and read from CLI
      final resInfo = await Process.run(natsExec, [
        'stream',
        'info',
        streamName,
        '-j',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resInfo.exitCode, equals(0),
          reason: 'CLI stream info failed: ${resInfo.stderr}');
      final Map<String, dynamic> infoMap =
          jsonDecode(resInfo.stdout.toString());
      expect(infoMap['config']['name'], equals(streamName));
      expect(infoMap['state']['messages'], equals(1));

      // 4. Clean up stream
      await js.deleteStream(streamName);
    });

    test('KeyValue Store Interop: Created from CLI -> Read/Write in Dart',
        () async {
      final bucket = 'cli_kv_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create KV bucket from CLI
      final resCreate = await Process.run(natsExec, [
        'kv',
        'add',
        bucket,
        '--storage',
        'memory',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resCreate.exitCode, equals(0),
          reason: 'CLI KV creation failed: ${resCreate.stderr}');

      // 2. Put from CLI
      final resPut = await Process.run(natsExec, [
        'kv',
        'put',
        bucket,
        'mykey',
        'val-from-cli',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resPut.exitCode, equals(0),
          reason: 'CLI KV put failed: ${resPut.stderr}');

      // 3. Bind and Get in Dart
      final kv = await js.keyValue(bucket);
      final entry = await kv.get('mykey');
      expect(entry, isNotNull);
      expect(entry!.string, equals('val-from-cli'));

      // 4. Put in Dart and Get from CLI
      await kv.putString('mykey', 'val-from-dart');

      final resGet = await Process.run(natsExec, [
        'kv',
        'get',
        bucket,
        'mykey',
        '--raw',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resGet.exitCode, equals(0),
          reason: 'CLI KV get failed: ${resGet.stderr}');
      expect(resGet.stdout.toString().trim(), equals('val-from-dart'));

      // Clean up bucket
      await js.deleteKeyValue(bucket);
    });

    test('Object Store Interop: Created from CLI -> Read/Write in Dart',
        () async {
      final bucket = 'cli_obj_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create Object Store bucket from CLI
      final resCreate = await Process.run(natsExec, [
        'object',
        'add',
        bucket,
        '--storage',
        'memory',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resCreate.exitCode, equals(0),
          reason: 'CLI Object Store creation failed: ${resCreate.stderr}');

      // 2. Put from CLI
      final tempDir = Directory.systemTemp.createTempSync('nats_cli_obj');
      final tempFile = File('${tempDir.path}/test_cli.txt');
      tempFile.writeAsStringSync('cli-object-content');

      final resPut = await Process.run(natsExec, [
        'object',
        'put',
        bucket,
        tempFile.path,
        '--name',
        'cli-file-key',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resPut.exitCode, equals(0),
          reason: 'CLI Object Store put failed: ${resPut.stderr}');

      // 3. Bind and Get in Dart
      final os = await js.objectStore(bucket);
      final retrievedData = await os.getString('cli-file-key');
      expect(retrievedData, equals('cli-object-content'));

      // 4. Put in Dart and Get from CLI
      await os.putString('dart-file-key', 'dart-object-content');

      final destFile = File('${tempDir.path}/retrieved.txt');
      final resGet = await Process.run(natsExec, [
        'object',
        'get',
        bucket,
        'dart-file-key',
        '-O',
        destFile.path,
        '-f',
        '-s',
        'nats://localhost:4222',
      ]);
      expect(resGet.exitCode, equals(0),
          reason: 'CLI Object Store get failed: ${resGet.stderr}');
      expect(destFile.readAsStringSync(), equals('dart-object-content'));

      // Clean up files and bucket
      tempDir.deleteSync(recursive: true);
      await js.deleteStream('OBJ_$bucket');
    });
  });
}
