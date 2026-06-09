import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_nats/dart_nats.dart';

// Custom HttpOverrides to accept self-signed certificates for local development.
// This is necessary when connecting to local secure WebSockets (wss://) because
// standard WebSocket connection libraries use the global HttpClient under the hood.
class DevelopmentHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  // Apply HTTP overrides to accept the self-signed certificate used by our test NATS server.
  HttpOverrides.global = DevelopmentHttpOverrides();

  final client = Client();

  // 1. Monitor connection status events
  client.statusStream.listen((status) {
    print('Connection status changed to: $status');
  });

  // Enable accepting self-signed or invalid certificates on the client
  client.acceptBadCert = true;

  // 2. Connect to NATS over Secure WebSockets (WSS).
  // By default, our local docker-compose wss server runs on port 8443.
  print(
      'Connecting to NATS Secure WebSocket server on wss://localhost:8443...');
  try {
    await client.connect(
      Uri.parse('wss://localhost:8443'),
      retry: true,
      retryCount: 3,
    );
    print('Connected successfully via Secure WebSocket (WSS)!');
  } catch (e) {
    print('Failed to connect via Secure WebSocket: $e');
    print('Ensure NATS is running in Docker (docker-compose up -d)');
    return;
  }

  // 3. Scenario: Pub/Sub over Secure WebSockets
  print('\n--- Scenario: Pub/Sub over Secure WebSockets ---');
  final sub = client.sub('demo.websocket.secure');

  // Listen to messages asynchronously
  final listener = sub.stream.listen((Message msg) {
    print('Received on [${msg.subject}]: ${msg.string}');
  });

  // Publish a test message
  print('Publishing message to "demo.websocket.secure"...');
  client.pubString('demo.websocket.secure', 'Hello from Secure WebSockets!');

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
