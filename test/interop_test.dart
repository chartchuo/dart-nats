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

    test('KeyValue Store Interop: Dart Put -> CLI Get -> CLI Put -> Dart Get', () async {
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
      expect(resGet.exitCode, equals(0), reason: 'CLI kv get failed: ${resGet.stderr}');
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
      expect(resPut.exitCode, equals(0), reason: 'CLI kv put failed: ${resPut.stderr}');

      // 4. Dart Get
      final entry = await kv.get('mykey');
      expect(entry, isNotNull);
      expect(entry!.string, equals('cli-value'));

      // Clean up bucket
      await js.deleteStream('KV_$bucket');
    });

    test('Object Store Interop: CLI Put -> Dart Get -> Dart Put -> CLI Get', () async {
      final bucket = 'interop_obj_${DateTime.now().millisecondsSinceEpoch}';
      final os = await js.objectStore(bucket, create: true, storage: 'memory');

      // Create a temporary file with unique content
      final tempDir = Directory.systemTemp.createTempSync('nats_interop');
      final tempFile = File('${tempDir.path}/test.txt');
      final uniqueContent = 'Unique content for interop object store: ${DateTime.now().toIso8601String()}';
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
      expect(resPut.exitCode, equals(0), reason: 'CLI object put failed: ${resPut.stderr}');

      // 2. Dart Get
      final retrievedData = await os.getString('cli-file');
      expect(retrievedData, equals(uniqueContent));

      // 3. Dart Put
      final dartContent = 'Hello from Dart Object Store! ' * 1000; // ~30KB to ensure chunking is tested a bit
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
      expect(resGet.exitCode, equals(0), reason: 'CLI object get failed: ${resGet.stderr}');
      expect(destFile.readAsStringSync(), equals(dartContent));

      // Cleanup files and bucket
      tempDir.deleteSync(recursive: true);
      await js.deleteStream('OBJ_$bucket');
    });
  });
}
