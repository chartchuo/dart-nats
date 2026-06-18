import 'dart:async';
import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('JetStream Integration', () {
    late Client client;
    late JetStream js;

    setUp(() async {
      client = Client();
      await client.connect(Uri.parse('nats://localhost:4222'));
      js = client.jetStream();
    });

    tearDown(() async {
      await client.close();
    });

    test('Full JetStream lifecycle: Stream, Pub, Consumer, Fetch, Ack',
        () async {
      final streamName = 'test-lifecycle-stream';
      final subjectFilter = 'test-lifecycle-subject.*';

      // 1. Create a Stream config
      final streamConfig = StreamConfig(
        name: streamName,
        subjects: [subjectFilter],
        storage: 'memory', // Use memory storage for ephemeral tests
      );

      // 2. Create the Stream
      final JsStream stream = await js.createStream(streamConfig);
      expect(stream.name, equals(streamName));

      // 3. Publish messages to Stream and verify PubAck
      final pubAck1 =
          await js.publishString('test-lifecycle-subject.a', 'hello-1');
      expect(pubAck1.stream, equals(streamName));
      expect(pubAck1.sequence, equals(1));
      expect(pubAck1.duplicate, isFalse);

      final pubAck2 =
          await js.publishString('test-lifecycle-subject.b', 'hello-2');
      expect(pubAck2.stream, equals(streamName));
      expect(pubAck2.sequence, equals(2));

      // 4. Create a Pull Consumer on the Stream
      final consumerName = 'test-lifecycle-consumer';
      final consumerConfig = ConsumerConfig(
        durable: consumerName,
        ackPolicy: 'explicit',
        deliverPolicy: 'all',
      );

      final Consumer consumer =
          await stream.createConsumer(consumerConfig);
      expect(consumer.name, equals(consumerName));

      // 5. Fetch messages using the consumer
      final messages = await consumer.fetch(batch: 2);
      expect(messages.length, equals(2));
      expect(messages[0].string, equals('hello-1'));
      expect(messages[1].string, equals('hello-2'));

      // 6. Acknowledge messages
      final ackResult1 = messages[0].ack();
      final ackResult2 = messages[1].ack();
      expect(ackResult1, isTrue);
      expect(ackResult2, isTrue);

      // Allow NATS some time to process acks
      await Future.delayed(const Duration(milliseconds: 200));

      // 7. Pulling again should yield no messages
      final emptyMessages = await consumer.fetch(
        batch: 1,
        timeout: const Duration(milliseconds: 500),
      );
      expect(emptyMessages.length, equals(0));

      // 8. Clean up Consumer and Stream
      final deleteConsumerResult =
          await js.deleteConsumer(streamName, consumerName);
      expect(deleteConsumerResult, isTrue);

      final deleteStreamResult = await js.deleteStream(streamName);
      expect(deleteStreamResult, isTrue);
    });

    test(
        'JetStream error handling: Delete non-existent stream throws NatsException',
        () async {
      expect(
        () => js.deleteStream('non-existent-stream-xyz'),
        throwsA(isA<NatsException>()),
      );
    });

    test('JetStream message processing: NAK triggers redelivery', () async {
      final streamName = 'test-nak-stream';
      final subjectFilter = 'test-nak-subject.*';
      final consumerName = 'test-nak-consumer';

      final stream = await js.createStream(StreamConfig(
        name: streamName,
        subjects: [subjectFilter],
        storage: 'memory',
      ));

      await js.publishString('test-nak-subject.a', 'hello-nak');

      final consumer = await stream.createConsumer(
        ConsumerConfig(
          durable: consumerName,
          ackPolicy: 'explicit',
          deliverPolicy: 'all',
        ),
      );

      // 1. Pull the message
      var messages = await consumer.fetch(batch: 1);
      expect(messages.length, equals(1));
      expect(messages[0].string, equals('hello-nak'));

      // 2. Call NAK
      expect(messages[0].nak(), isTrue);

      // Allow NATS a brief moment to process NAK and make message available
      await Future.delayed(const Duration(milliseconds: 100));

      // 3. Pull again -> should receive the message again due to NAK
      var redeliveredMessages =
          await consumer.fetch(batch: 1);
      expect(redeliveredMessages.length, equals(1));
      expect(redeliveredMessages[0].string, equals('hello-nak'));

      // 4. Acknowledge and cleanup
      expect(redeliveredMessages[0].ack(), isTrue);
      await js.deleteConsumer(streamName, consumerName);
      await js.deleteStream(streamName);
    });

    test('JetStream message processing: TERM prevents redelivery', () async {
      final streamName = 'test-term-stream';
      final subjectFilter = 'test-term-subject.*';
      final consumerName = 'test-term-consumer';

      final stream = await js.createStream(StreamConfig(
        name: streamName,
        subjects: [subjectFilter],
        storage: 'memory',
      ));

      await js.publishString('test-term-subject.a', 'hello-term');

      final consumer = await stream.createConsumer(
        ConsumerConfig(
          durable: consumerName,
          ackPolicy: 'explicit',
          deliverPolicy: 'all',
        ),
      );

      // 1. Pull the message
      var messages = await consumer.fetch(batch: 1);
      expect(messages.length, equals(1));
      expect(messages[0].string, equals('hello-term'));

      // 2. Call TERM
      expect(messages[0].term(), isTrue);

      // Allow NATS a brief moment to process TERM
      await Future.delayed(const Duration(milliseconds: 100));

      // 3. Pull again -> should NOT receive the message again
      var emptyMessages = await consumer.fetch(
        batch: 1,
        timeout: const Duration(milliseconds: 500),
      );
      expect(emptyMessages.length, equals(0));

      // 4. Cleanup
      await js.deleteConsumer(streamName, consumerName);
      await js.deleteStream(streamName);
    });

    test('New APIs: accountInfo, streamNameBySubject, createOrUpdateStream, createOrUpdateConsumer', () async {
      // 1. Test accountInfo
      final accInfo = await js.accountInfo();
      expect(accInfo.tier.memory, isNotNull);

      // 2. Test createOrUpdateStream & streamNameBySubject
      final streamName = 'test-update-stream';
      final subjectFilter = 'test-update-subject.*';

      final stream = await js.createOrUpdateStream(StreamConfig(
        name: streamName,
        subjects: [subjectFilter],
        storage: 'memory',
      ));
      expect(stream.name, equals(streamName));

      // Verify streamNameBySubject
      final foundName = await js.streamNameBySubject('test-update-subject.item');
      expect(foundName, equals(streamName));

      // Update config and verify update works
      final updatedStream = await js.createOrUpdateStream(StreamConfig(
        name: streamName,
        subjects: [subjectFilter, 'test-update-subject-extra.*'],
        storage: 'memory',
      ));
      final info = await updatedStream.info();
      expect(info.config.subjects, contains('test-update-subject-extra.*'));

      // 3. Test createOrUpdateConsumer
      final consumerConfig = ConsumerConfig(
        durable: 'test-update-consumer',
        ackPolicy: 'explicit',
      );
      final consumer = await js.createOrUpdateConsumer(streamName, consumerConfig);
      expect(consumer.name, equals('test-update-consumer'));

      final consumerInfo = await consumer.info();
      expect(consumerInfo.name, equals('test-update-consumer'));

      // Cleanup
      await js.deleteConsumer(streamName, 'test-update-consumer');
      await js.deleteStream(streamName);
    });
  });
}
