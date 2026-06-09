import 'package:dart_nats/dart_nats.dart';

void main() async {
  final client = Client();

  // 1. Monitor connection status events
  client.statusStream.listen((status) {
    print('Connection status changed to: $status');
  });

  // 2. Connect to NATS over WebSockets.
  // By default, our local docker-compose configuration exposes the NATS WebSocket
  // server on port 8080 (unsecured/no-tls ws://).
  print('Connecting to NATS WebSocket server on ws://localhost:8080...');
  try {
    await client.connect(
      Uri.parse('ws://localhost:8080'),
      retry: true,
      retryCount: 3,
    );
    print('Connected successfully via WebSocket!');
  } catch (e) {
    print('Failed to connect via WebSocket: $e');
    print('Ensure NATS is running in Docker (docker-compose up -d)');
    return;
  }

  // 3. Scenario: Pub/Sub over WebSockets
  print('\n--- Scenario: Pub/Sub over WebSockets ---');
  final sub = client.sub('demo.websocket');

  // Listen to messages asynchronously
  final listener = sub.stream.listen((Message msg) {
    print('Received on [${msg.subject}]: ${msg.string}');
  });

  // Publish a test message
  print('Publishing message to "demo.websocket"...');
  client.pubString('demo.websocket', 'Hello from WebSockets!');

  // Wait briefly for delivery
  await Future.delayed(Duration(milliseconds: 100));

  // 4. Resource Cleanup
  print('\n--- Scenario: Resource Cleanup ---');
  print('Closing subscription...');
  await listener.cancel();
  client.unSub(sub);

  print('Disconnecting client...');
  await client.close();
  print('Done!');
}
