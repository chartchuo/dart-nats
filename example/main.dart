import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_nats/dart_nats.dart';

void main() async {
  final client = Client();

  // 1. Monitor connection status events
  client.statusStream.listen((status) {
    print('Connection status changed to: $status');
  });

  print('Connecting to NATS server...');
  await client.connect(
    Uri.parse('nats://localhost:4222'),
    retry: true,
    retryCount: 3,
  );

  // 2. Scenario 1: Standard Pub/Sub (Asynchronous)
  print('\n--- Scenario 1: Pub/Sub ---');
  final sub = client.sub('demo.chat');

  // Listen to messages asynchronously
  final listener = sub.stream.listen((Message msg) {
    print('Received on [${msg.subject}]: ${msg.string}');
  });

  // Publish some string and binary messages
  print('Publishing messages to "demo.chat"...');
  client.pubString('demo.chat', 'Hello, NATS!');
  client.pub('demo.chat', Uint8List.fromList(utf8.encode('Binary Message')));

  // Give it a brief moment to receive and process messages
  await Future.delayed(Duration(milliseconds: 100));

  // 3. Scenario 2: Request/Reply (Synchronous RPC)
  print('\n--- Scenario 2: Request/Reply (RPC) ---');

  // Setup a service responder
  final serviceSub = client.sub('demo.service');
  final serviceListener = serviceSub.stream.listen((Message requestMsg) {
    print('Service received request: "${requestMsg.string}"');

    // Respond back to the reply subject
    if (requestMsg.respondString('Processed: ${requestMsg.string}')) {
      print('Service responded successfully.');
    }
  });

  // Send a request and await the reply
  print('Sending request to "demo.service"...');
  try {
    final response = await client.request(
      'demo.service',
      Uint8List.fromList(utf8.encode('Hello Service')),
      timeout: Duration(seconds: 2),
    );
    print('Request response received: "${response.string}"');
  } catch (e) {
    print('Request failed: $e');
  }

  // 4. Scenario 3: Cleaning Up
  print('\n--- Scenario 3: Cleaning Up ---');
  print('Closing subscriptions...');
  await listener.cancel();
  await serviceListener.cancel();
  client.unSub(sub);
  client.unSub(serviceSub);

  print('Disconnecting client...');
  await client.close();
  print('Done!');
}
