# Dart-NATS

[![Pub Version](https://img.shields.io/pub/v/dart_nats?color=blue)](https://pub.dev/packages/dart_nats)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)

A lightweight, high-performance Dart client library for the [NATS](https://nats.io) messaging system. Designed specifically for use with **Dart** and **Flutter** applications.

> [!NOTE]
> **Good news—this repository is active and maintained again!** To help us move fast and keep maintenance overhead light, we're using AI assistants to help write code, document features, and write tests. Currently, we're building out exciting new features like NATS JetStream, Key-Value, and Object Stores, and keeping updated with the latest Dart SDK.

---

## 📖 Introduction & Core Concepts

NATS is a simple, secure, and high-performance publish-subscribe messaging system. This client library allows Dart and Flutter applications to communicate seamlessly with NATS servers.

### Async Model: Streams and Futures
The library is designed around standard Dart asynchronous paradigms:
* **Futures**: Used for one-shot operations, such as establishing connections, sending requests, publishing messages, or performing administrative tasks (like creating streams or KV buckets).
* **Streams**: Used for subscribing to message topics, listening to connection status changes, or watching live mutations in a Key-Value bucket.

---

## 🚀 Getting Started

### 1. Add Dependency
Add `dart_nats` to your `pubspec.yaml` file:

```yaml
dependencies:
  dart_nats: ^0.7.0
```

### 2. Import the Package
Import the client library into your Dart code:

```dart
import 'package:dart_nats/dart_nats.dart';
```

---

## 🔌 Connection Setup & Lifecycle

The client supports standard TCP socket connections (for native platforms) and WebSocket connections (for Flutter Web and platforms requiring HTTP-friendly transports).

### 1. Protocols & URI Schemes
Depending on the platform and transport, connect using the appropriate URI scheme:

```dart
final client = Client();

// 1. Native TCP connection (highly recommended for server, mobile, and desktop)
await client.connect(Uri.parse('nats://localhost:4222'));

// 2. Native TLS (secure TCP socket connection)
await client.connect(Uri.parse('tls://localhost:4222'));

// 3. WebSocket connection (required for Flutter Web)
await client.connect(Uri.parse('ws://localhost:8080'));

// 4. Secure WebSocket connection (WSS)
await client.connect(Uri.parse('wss://localhost:8443'));
```

### 2. Connection Management & Background Retry
You can configure retry behavior, handle connection states, and track connection health:

```dart
// Connect in the background without blocking execution
client.connect(
  Uri.parse('nats://localhost:4222'),
  retry: true,           // Enable automatic background reconnects
  retryCount: -1,        // -1 means retry infinitely; otherwise set max attempts
  retryInterval: 5,      // Delay in seconds between connection retries
  timeout: 5,            // Connection timeout in seconds
);

// Wait until the client successfully establishes a connection
await client.wait4Connected(); // Or client.waitUntilConnected();
```

### 3. Monitoring Connection Status
You can listen to connection status changes through the `statusStream`. This is ideal for updating Flutter UI overlays when the network drops:

```dart
client.statusStream.listen((status) {
  switch (status) {
    case Status.connecting:
      print('Connecting to NATS...');
      break;
    case Status.connected:
      print('Connected successfully!');
      break;
    case Status.disconnected:
      print('Disconnected from server.');
      break;
    case Status.reconnecting:
      print('Network dropped. Reconnecting in background...');
      break;
    case Status.closed:
      print('Connection explicitly closed.');
      break;
    default:
      break;
  }
});
```

### 4. Connection State Callbacks
Alternatively, you can register connection lifecycle callbacks:

```dart
client.onConnect = () => print('Connected');
client.onDisconnect = () => print('Disconnected');
client.onReconnect = () => print('Reconnected');
client.onClose = () => print('Connection Closed');
```

### 5. Disconnection & Draining
* `close()`: Immediately shuts down the connection and cleans up memory.
* `forceClose()`: Closes the active connection and ensures no background reconnect retries are attempted.
* `drain()`: Subscriptions are drained (processed) completely before the connection is closed.

```dart
// Gracefully drain all subscriptions and close connection
await client.drain();
```

---

## ✉️ Publish & Subscribe (Core Pub/Sub)

Pub/Sub is the foundation of NATS. Subscribers register interest in subjects, and publishers send payloads to those subjects.

### 1. Publishing Payloads
You can publish raw binary bytes (`Uint8List`) or string helper payloads:

```dart
// Publish a raw binary payload
await client.pub('sensors.temperature', Uint8List.fromList([22, 10, 44]));

// Publish a string payload
await client.pubString('sensors.temperature', '22.4 C');
```

### 2. Subscribing to Topics
Subscribing returns a `Subscription` containing a Dart `Stream<Message>`. The client automatically restores these subscriptions when a background reconnection occurs:

```dart
// Subscribe to a topic
final sub = client.sub('sensors.temperature');

// Listen to the message stream
final streamSubscription = sub.stream.listen((Message msg) {
  print('Received payload: ${msg.string}');
  
  // Respond directly if the publisher requested a reply
  if (msg.replyTo != null) {
    msg.respondString('Acknowledgment');
  }
});

// To stop listening and clean up subscription:
client.unSub(sub); // Or await sub.close();
```

### 3. Wildcard Subscriptions
NATS supports path-based wildcards:
* `*` (asterisk) matches a single token path segment. E.g., `sensors.*` matches `sensors.temperature` and `sensors.humidity`.
* `>` (greater-than) matches any trailing tokens recursively. E.g., `sensors.>` matches `sensors.us.west.temperature`.

```dart
final sub = client.sub('sensors.>');
```

### 4. Queue Groups (Load Balancing)
If you run multiple instances of a service and want to distribute messages among them (instead of having all instances receive every message), use queue groups:

```dart
// NATS will load-balance messages on 'orders.created' among all instances in 'billing-group'
final sub = client.sub('orders.created', queueGroup: 'billing-group');
```

---

## 📱 Flutter Integration

Integrating NATS into Flutter is straightforward because subscriptions expose standard Dart streams. You can consume message streams directly in your UI using a `StreamBuilder`.

```dart
import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart' as nats;

class TemperatureMonitor extends StatefulWidget {
  const TemperatureMonitor({Key? key}) : super(key: key);

  @override
  _TemperatureMonitorState createState() => _TemperatureMonitorState();
}

class _TemperatureMonitorState extends State<TemperatureMonitor> {
  late nats.Client _natsClient;
  late nats.Subscription _sub;

  @override
  void initState() {
    super.initState();
    _natsClient = nats.Client();
    _natsClient.connect(Uri.parse('nats://localhost:4222'), retry: true);
    
    // Subscribe to subject
    _sub = _natsClient.sub('sensors.temperature');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NATS Monitor')),
      body: Center(
        child: StreamBuilder<nats.Message>(
          stream: _sub.stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }
            if (!snapshot.hasData) {
              return const Text('Waiting for temperature readings...');
            }
            return Text(
              'Temperature: ${snapshot.data?.string}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Gracefully unsubscribe and close client on disposal
    _natsClient.unSub(_sub);
    _natsClient.close();
    super.dispose();
  }
}
```

---

## 🔁 Request-Reply Pattern

The Request-Reply pattern is useful for client-server APIs. NATS automatically handles temporary inbox creation so replies map back to the correct request.

### 1. Simple Request
```dart
try {
  final Message response = await client.request(
    'users.get',
    Uint8List.fromList('user-123'.codeUnits),
    timeout: const Duration(seconds: 3),
  );
  print('User details: ${response.string}');
} on TimeoutException {
  print('Request timed out!');
}
```

### 2. Structured JSON Decoding
You can register custom type decoders. This avoids manual JSON parsing in your application code:

```dart
// 1. Define your data class
class User {
  final String id;
  final String name;
  User({required this.id, required this.name});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(id: json['id'], name: json['name']);
  }
}

// 2. Define the JSON parser function
User jsonToUser(String jsonStr) {
  return User.fromJson(jsonDecode(jsonStr));
}

// 3. Register the decoder with the client
client.registerJsonDecoder<User>(jsonToUser);

// 4. Request the object directly -> response.data is automatically parsed as User
final response = await client.requestString<User>('users.get', 'user-123');
final User user = response.data;
print('User: ${user.name}');
```

---

## 🔐 Authentication Modes

NATS supports multiple authentication schemes depending on your security requirements.

### 1. Token Auth
```dart
client.connect(
  Uri.parse('nats://localhost:4222'),
  connectOption: ConnectOption(authToken: 'my-secret-token'),
);
```

### 2. Username & Password Auth
```dart
client.connect(
  Uri.parse('nats://localhost:4222'),
  connectOption: ConnectOption(user: 'admin', pass: 'strongpassword'),
);
```

### 3. NKEY Auth
NKEY uses public-key cryptography. You set the private seed locally, and provide the public key to NATS:

```dart
client.seed = 'SUACSSL3UAHUDXKFSNVUZRF5UHPMWZ6BFDTJ7M6USDXIEDNPPQYYYCU3VY';
client.connect(
  Uri.parse('nats://localhost:4222'),
  connectOption: ConnectOption(
    nkey: 'UDXU4RCSJNZOIQHZNWXHXORDPRTGNJAHAHFRGZNEEJCPQTT2M7NLCNF4',
  ),
);
```

### 4. JWT & User Credentials (.creds) Auth
JWT authentication maps credentials securely. You can easily load NATS `.creds` files directly:

```dart
// Load from a raw credentials file string
client.loadCredentials(myCredsFileContent);

// Or load directly from a file path (Native Dart platforms)
await client.loadCredentialsFile('/path/to/user.creds');

// Connect to the server
await client.connect(Uri.parse('nats://localhost:4222'));
```

---

## ⚡ JetStream Support (Persistence)

JetStream provides message persistence, at-least-once delivery guarantees, and support for message replay.

### 1. Initialize JetStream
Create a JetStream context from your connected client:

```dart
final js = client.jetStream();
```

### 2. Stream Management
Streams ingest messages published to specific subjects and store them:

```dart
// 1. Configure the stream
final streamConfig = StreamConfig(
  name: 'events-stream',
  subjects: ['events.>'],
  storage: 'file', // 'file' for persistent disk storage, 'memory' for ephemeral testing
);

// 2. Create the stream
await js.addStream(streamConfig);

// 3. Get stream info (e.g. sequence numbers, message counts)
final StreamInfo info = await js.getStream('events-stream');
print('Stored messages: ${info.state.messages}');

// 4. Purge stream messages
await js.purgeStream('events-stream');

// 5. Delete stream
await js.deleteStream('events-stream');
```

### 3. Publishing to JetStream
JetStream publishing awaits a publish acknowledgment (`PubAck`) from the server to guarantee persistence:

```dart
// Publish with optimistic concurrency checks (optional)
final pubAck = await js.publishString(
  'events.clicks',
  'click-data',
  opts: PubOpts(msgId: 'unique-msg-id'), // Prevent duplicate publishes
);
print('Message persisted at sequence: ${pubAck.sequence}');
```

### 4. Pull Consumer Lifecycle
Pull Consumers fetch batches of messages on-demand. This pattern is ideal for workers and high-throughput background processing:

```dart
// 1. Define consumer configuration
final consumerConfig = ConsumerConfig(
  durable: 'worker-consumer', // Required for pull mode state tracking
  ackPolicy: 'explicit',
  deliverPolicy: 'all',
);

// 2. Add the consumer to the stream
await js.addConsumer('events-stream', consumerConfig);

// 3. Pull a batch of messages on-demand
final List<Message> batch = await js.pull(
  'events-stream',
  'worker-consumer',
  batch: 10,
  timeout: const Duration(seconds: 3),
);

for (final Message msg in batch) {
  print('Process message: ${msg.string}');
  
  // Acknowledge the message (removes it from delivery queue)
  msg.ack();
  
  // Or:
  // await msg.ackSync(); // Wait for server to confirm acknowledgment
  // msg.nak();          // Negative ack: triggers redelivery
  // msg.term();         // Terminate: prevents any future redeliveries of this message
}

// Clean up when done
await js.deleteConsumer('events-stream', 'worker-consumer');
```

---

## 🗄️ Key-Value (KV) Store

The KV Store provides a lightweight, schemaless key-value database built on top of NATS JetStream.

### 1. Create or Bind to a KV Bucket
```dart
// Provision or bind to the bucket. Setting create: true creates the backing JetStream stream.
final KeyValue kv = await js.keyValue('app_settings', create: true, storage: 'memory');
```

### 2. Put & Get Values
```dart
// Save keys (strings or raw binary bytes)
await kv.putString('theme', 'dark');
await kv.put('port', Uint8List.fromList([80, 80]));

// Fetch key entry
final KeyValueEntry? entry = await kv.get('theme');
if (entry != null) {
  print('Key: ${entry.key}');
  print('Value: ${entry.string}');
  print('Revision (Sequence): ${entry.revision}');
  print('Timestamp: ${entry.created}');
}
```

### 3. Deleting vs Purging
* `delete()`: Places a tombstone message on the key. The key will appear as deleted, but previous histories are kept.
* `purge()`: Permanently deletes the key and purges all of its historical values.

```dart
await kv.delete('theme');
await kv.purge('port');
```

### 4. Watch for Real-Time Changes
Listen for live updates to keys. You can watch specific keys, or use wildcards (e.g. `>` to watch everything):

```dart
final Stream<KeyValueEntry?> watcher = kv.watch(key: 'user.>', includeHistory: false);

final streamSub = watcher.listen((KeyValueEntry? entry) {
  if (entry == null) {
    print('Watched key was deleted/purged.');
  } else {
    print('Live Update - Key: ${entry.key}, Value: ${entry.string}');
  }
});

// Cancel when finished
await streamSub.cancel();
```

---

## 📦 Object Store

The Object Store is built on top of JetStream. It is designed to store files and large payloads. Under the hood, the client splits large objects into 128 KiB chunks and performs end-to-end SHA-256 digest validation to ensure file transfer integrity.

### 1. Bind or Create a Bucket
```dart
final ObjectStore os = await js.objectStore('attachments', create: true, storage: 'memory');
```

### 2. Put & Get Large Payloads
```dart
final largeData = Uint8List(500 * 1024); // 500 KiB data payload

// Upload the object (will split into 4 chunks of 128 KiB under the hood)
final ObjectInfo info = await os.put('report.pdf', largeData, description: 'Q3 financial report');
print('Uploaded chunks count: ${info.chunks}');

// Download object (downloads chunks and verifies SHA-256 integrity automatically)
final Uint8List? fileData = await os.get('report.pdf');
print('Downloaded file size: ${fileData?.length} bytes');
```

### 3. List and Delete Objects
```dart
// List all active objects
final List<ObjectInfo> files = await os.list();
for (final file in files) {
  print('Filename: ${file.name}, Chunks: ${file.chunks}, Size: ${file.size}');
}

// Delete object chunks and reclaim space
await os.delete('report.pdf');
```

---

## 🧪 Development & Testing

For instructions on running containerized NATS servers locally, generating certificates, and executing the test suites, check the [DEVELOPMENT.md](file:///Users/chartchuo/workspace/dart-nats/DEVELOPMENT.md) guide.
