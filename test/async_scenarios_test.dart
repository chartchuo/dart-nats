import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  final protocols = {
    'TCP Connection': Uri.parse('nats://localhost:4222'),
    'WebSocket Connection': Uri.parse('ws://localhost:8080'),
  };

  for (final entry in protocols.entries) {
    final name = entry.key;
    final uri = entry.value;

    group('Async Scenarios [$name]', () {
      late Client client;
      late JetStream js;

      setUp(() async {
        client = Client();
        await client.connect(uri, retry: false);
        js = client.jetStream();
      });

      tearDown(() async {
        await client.close();
      });

      test('Pub/Sub Scenario', () async {
        final subject =
            'async.pubsub.${name.hashCode}.${DateTime.now().millisecondsSinceEpoch}';
        final sub = client.sub(subject);
        final receivedMessages = <String>[];

        final streamSub = sub.stream.listen((msg) {
          receivedMessages.add(msg.string);
        });

        // Publish multiple messages asynchronously
        await client.pubString(subject, 'msg1');
        await client.pubString(subject, 'msg2');
        await client.pub(subject, Uint8List.fromList(utf8.encode('msg3')));

        // Wait for messages to arrive
        await Future.delayed(const Duration(milliseconds: 100));

        expect(receivedMessages, containsAll(['msg1', 'msg2', 'msg3']));

        await streamSub.cancel();
        client.unSub(sub);
      });

      test('JetStream Stream lifecycle', () async {
        final uniqueId = DateTime.now().millisecondsSinceEpoch;
        final streamName = 'stream_${name.hashCode}_$uniqueId';
        final subjectFilter = 'js.async.${name.hashCode}.$uniqueId.*';

        final config = StreamConfig(
          name: streamName,
          subjects: [subjectFilter],
          storage: 'memory',
        );

        final stream = await js.createStream(config);
        expect(stream.name, equals(streamName));

        // Publish to JetStream
        await js.publishString(
            'js.async.${name.hashCode}.$uniqueId.one', 'payload-1');
        await js.publishString(
            'js.async.${name.hashCode}.$uniqueId.two', 'payload-2');

        // Create Pull Consumer
        final consumerName = 'consumer_${name.hashCode}';
        final consumerConfig = ConsumerConfig(
          durable: consumerName,
          ackPolicy: 'explicit',
        );

        final consumer = await stream.createConsumer(consumerConfig);
        expect(consumer.name, equals(consumerName));

        // Fetch messages asynchronously
        final messages = await consumer.fetch(batch: 2);
        expect(messages.length, equals(2));
        expect(messages[0].string, equals('payload-1'));
        expect(messages[1].string, equals('payload-2'));

        // Ack messages
        expect(messages[0].ack(), isTrue);
        expect(messages[1].ack(), isTrue);

        // Clean up stream
        final deleted = await js.deleteStream(streamName);
        expect(deleted, isTrue);
      });

      test('JetStream Key-Value (KV) Store scenario', () async {
        final bucket =
            'bucket_${name.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
        final kv = await js.keyValue(bucket, create: true, storage: 'memory');

        // Put keys
        final rev1 = await kv.putString('setting.theme', 'dark');
        expect(rev1, equals(1));

        final rev2 = await kv.putString('setting.language', 'en');
        expect(rev2, equals(2));

        // Get key
        final entry = await kv.get('setting.theme');
        expect(entry, isNotNull);
        expect(entry!.string, equals('dark'));

        // Update key
        final rev3 = await kv.putString('setting.theme', 'light');
        expect(rev3, equals(3));

        final entryUpdated = await kv.get('setting.theme');
        expect(entryUpdated!.string, equals('light'));

        // Clean up KV backing stream
        await js.deleteStream('KV_$bucket');
      });

      test('JetStream Object Store scenario', () async {
        final bucket =
            'store_${name.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
        final os =
            await js.objectStore(bucket, create: true, storage: 'memory');

        final testData =
            Uint8List.fromList(utf8.encode('NATS Object Store Content!'));
        final info =
            await os.put('my-file.txt', testData, description: 'Test object');

        expect(info.name, equals('my-file.txt'));
        expect(info.size, equals(testData.length));

        // Retrieve object metadata
        final retrievedInfo = await os.getInfo('my-file.txt');
        expect(retrievedInfo, isNotNull);
        expect(retrievedInfo!.description, equals('Test object'));

        // Retrieve object data
        final data = await os.get('my-file.txt');
        expect(data, equals(testData));

        // Retrieve object string data
        final strData = await os.getString('my-file.txt');
        expect(strData, equals('NATS Object Store Content!'));

        // List objects
        final objects = await os.list();
        expect(objects.length, equals(1));
        expect(objects[0].name, equals('my-file.txt'));

        // Clean up Object Store backing stream
        await js.deleteStream('OBJ_$bucket');
      });
    });
  }
}
