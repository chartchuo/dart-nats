import 'package:dart_nats/dart_nats.dart';

void main() async {
  // 1. Create a client and connect to the local NATS server.
  // Make sure NATS is running with JetStream enabled (e.g. nats-server -js)
  final client = Client();
  print('Connecting to NATS...');
  await client.connect(Uri.parse('nats://localhost:4222'));
  print('Connected!');

  // 2. Initialize the JetStream context from the client
  final js = client.jetStream();

  final streamName = 'example-stream';
  final subjectFilter = 'example-subject.*';
  final consumerName = 'example-pull-consumer';

  try {
    // 3. Create a Stream Configuration
    final streamConfig = StreamConfig(
      name: streamName,
      subjects: [subjectFilter],
      storage: 'memory', // Use memory storage for transient example data
    );

    print('Creating stream "$streamName" for subjects matching "$subjectFilter"...');
    final streamAdded = await js.addStream(streamConfig);
    if (streamAdded) {
      print('Stream created successfully.');
    }

    // 4. Publish messages to the stream
    print('Publishing messages...');
    
    // Normal publish
    final ack1 = await js.publishString('example-subject.news', 'NATS JetStream is awesome!');
    print('Published message 1. Stream: ${ack1.stream}, Sequence: ${ack1.sequence}');

    // Publish with Deduplication using Msg-ID (exactly-once delivery semantics)
    final ack2 = await js.publishString(
      'example-subject.alerts',
      'Alert: CPU usage high',
      opts: PubOpts(msgId: 'alert-unique-id-101'),
    );
    print('Published message 2 (with Msg-ID). Stream: ${ack2.stream}, Sequence: ${ack2.sequence}, Duplicate: ${ack2.duplicate}');

    // Publishing again with the SAME Msg-ID is recognized as duplicate by the server
    final ack3 = await js.publishString(
      'example-subject.alerts',
      'Alert: CPU usage high',
      opts: PubOpts(msgId: 'alert-unique-id-101'),
    );
    print('Published duplicate message. Stream: ${ack3.stream}, Sequence: ${ack3.sequence}, Duplicate: ${ack3.duplicate}');

    // 5. Create a Pull Consumer
    final consumerConfig = ConsumerConfig(
      durable: consumerName,
      ackPolicy: 'explicit',
      deliverPolicy: 'all',
    );

    print('Creating pull consumer "$consumerName"...');
    final consumerAdded = await js.addConsumer(streamName, consumerConfig);
    if (consumerAdded) {
      print('Consumer created successfully.');
    }

    // 6. Pull messages from the consumer in batches
    print('Pulling a batch of up to 5 messages (timeout 2s)...');
    final messages = await js.pull(
      streamName,
      consumerName,
      batch: 5,
      timeout: const Duration(seconds: 2),
    );

    print('Pulled ${messages.length} message(s):');
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      print('  [$i] Subject: ${msg.subject}, Data: "${msg.string}", Stream Seq: ${msg.streamSequence}');

      // 7. Acknowledge messages
      if (i == 0) {
        // Asynchronous Ack
        final ok = msg.ack();
        print('  [$i] Sent asynchronous ACK: $ok');
      } else {
        // Synchronous Ack (waits for server acknowledgment response)
        print('  [$i] Sending synchronous ACK...');
        await msg.ackSync();
        print('  [$i] Synchronous ACK confirmed.');
      }
    }

    // Let NATS process the ACKs
    await Future.delayed(const Duration(milliseconds: 200));

    // Pulling again should be empty
    final remaining = await js.pull(
      streamName,
      consumerName,
      batch: 1,
      timeout: const Duration(milliseconds: 500),
    );
    print('Remaining messages to pull: ${remaining.length}');

  } catch (e) {
    print('Error occurred: $e');
  } finally {
    // 8. Clean up resources
    print('Cleaning up consumer and stream...');
    try {
      await js.deleteConsumer(streamName, consumerName);
      await js.deleteStream(streamName);
      print('Cleanup successful.');
    } catch (e) {
      print('Cleanup failed: $e');
    }

    await client.close();
    print('Connection closed.');
  }
}
