# Dart-NATS

[![Pub Version](https://img.shields.io/pub/v/dart_nats?color=blue)](https://pub.dev/packages/dart_nats)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)

A lightweight, high-performance Dart client library for the [NATS](https://nats.io) messaging system. Designed specifically for use with **Dart** and **Flutter** applications.

---

## Features

- [x] **Publish & Subscribe:** Support for standard pub/sub operations.
- [x] **Platform Versatility:** Run on Web (WebSockets) and native mobile/desktop/server (TCP Socket and WebSockets).
- [x] **Reconnection & Retry:** Automatic retry/reconnection in the background with customizable retry limits.
- [x] **Message Buffering:** Buffers published messages during brief reconnection attempts.
- [x] **Inbox & NUID:** Built-in unique ID and transient inbox generation.
- [x] **Request-Response:** Synchronous or asynchronous request/respond patterns, including request timeout and unsubscribe-after-N capabilities.
- [x] **Queue Groups:** Support for shared subscriptions (Queue subscribe).
- [x] **Robust Authentication:** Built-in support for token, username/password, NKEY, and JWT authentication (compatible with NATS 2.0+).
- [x] **TLS/SSL Security:** Secure connections for native TCP sockets and WebSockets.
- [x] **JetStream Support:** Create, update, purge, delete, and list Streams and Consumers, publish/subscribe, and pull messages with manual Ack/Nak/Term control.
- [x] **Key-Value Store:** High-level wrapper to put, get, delete, purge, and watch real-time keys in a KV bucket.
- [x] **Object Store:** Convenient object/file storage featuring automatic chunking (128 KiB chunks) and end-to-end SHA-256 digest validation.

---

## Getting Started

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  dart_nats: ^0.7.0
```

---

## Connection Setup

### Flutter Web Support (via WebSockets)
```dart
final client = Client();
client.connect(Uri.parse('ws://localhost:80'));
// or secure
client.connect(Uri.parse('wss://localhost:443'));
```

### Native Platforms (via TCP Socket and WebSockets)
```dart
final client = Client();
client.connect(Uri.parse('nats://localhost:4222'));
client.connect(Uri.parse('tls://localhost:4222'));
client.connect(Uri.parse('ws://localhost:80'));
client.connect(Uri.parse('wss://localhost:443'));
```

---

## Connection Management

### Background Retry
To handle network drops gracefully, you can enable background retries and listen to connection state changes:

```dart
// Connect in background without awaiting blocks
client.connect(
  Uri.parse('nats://localhost:4222'), 
  retry: true, 
  retryCount: -1, // -1 means infinite retries
);

// If needed, await for the initial connection to establish
await client.wait4Connected();

// Listen to the connection status stream
client.statusStream.listen((status) {
  print('Connection status changed to: $status');
});
```

### Disable Retry and Catch Exceptions
```dart
try {
  await client.connect(Uri.parse('nats://localhost:1234'), retry: false);
} on NatsException catch (e) {
  print('Connection failed: $e');
}
```

---

## Dart Usage Example

```dart
import 'package:dart_nats/dart_nats.dart';

void main() async {
  final client = Client();
  
  // Establish connection
  await client.connect(Uri.parse('nats://localhost:4222'));
  
  // Subscribe to a subject
  final sub = client.sub('subject1');
  
  // Publish a message
  await client.pubString('subject1', 'hello world');
  
  // Wait for the first message on subscription
  final msg = await sub.stream.first;
  print('Received payload: ${msg.string}');
  
  // Clean up
  client.unSub(sub);
  client.close();
}
```

---

## Flutter Integration Example

### 1. Declare and Initialize the Client
```dart
import 'package:dart_nats/dart_nats.dart' as nats;

nats.Client natsClient;
nats.Subscription fooSub, barSub;

void connect() {
  natsClient = nats.Client();
  natsClient.connect(Uri.parse('nats://hostname:4222'));
  fooSub = natsClient.sub('foo');
  barSub = natsClient.sub('bar');
}
```

### 2. Stream Data to UI (StreamBuilder)
```dart
StreamBuilder<nats.Message>(
  stream: fooSub.stream,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return Text('Message: ${snapshot.data?.string}');
    }
    return const Text('Waiting for messages...');
  },
)
```

### 3. Publish Message
```dart
await natsClient.pubString('subject', 'message string');
```

### 4. Dispose Client on Widget Destruction
```dart
@override
void dispose() {
  natsClient.close();
  super.dispose();
}
```

---

## Request & Response Pattern

### Standard Binary Request
```dart
final client = Client();
client.inboxPrefix = '_INBOX.test_test';
await client.connect(Uri.parse('nats://localhost:4222'));

final response = await client.request(
  'service', 
  Uint8List.fromList('request'.codeUnits),
);
print('Response: ${response.string}');
```

### Structured Data (JSON) Decoding
Register a decoder to automatically deserialize response payloads into strongly typed Dart objects:

```dart
final client = Client();
await client.connect(Uri.parse('nats://localhost:4222'));

// Register the JSON decoder mapping a JSON string to a Student object
client.registerJsonDecoder<Student>(json2Student);

final response = await client.requestString<Student>('service', '');
final Student student = response.data;

Student json2Student(String json) {
  return Student.fromJson(jsonDecode(json));
}
```

---

## Authentication Modes

### Token Authentication
```dart
final client = Client();
client.connect(
  Uri.parse('nats://localhost'),
  connectOption: ConnectOption(authToken: 'mytoken'),
);
```

### Username & Password Authentication
```dart
final client = Client();
client.connect(
  Uri.parse('nats://localhost'),
  connectOption: ConnectOption(user: 'foo', pass: 'bar'),
);
```

### NKEY Authentication
```dart
final client = Client();
client.seed = 'SUACSSL3UAHUDXKFSNVUZRF5UHPMWZ6BFDTJ7M6USDXIEDNPPQYYYCU3VY';
client.connect(
  Uri.parse('nats://localhost'),
  connectOption: ConnectOption(
    nkey: 'UDXU4RCSJNZOIQHZNWXHXORDPRTGNJAHAHFRGZNEEJCPQTT2M7NLCNF4',
  ),
);
```

### JWT Authentication
```dart
final client = Client();
client.seed = 'SUAJGSBAKQHGYI7ZVKVR6WA7Z5U52URHKGGT6ZICUJXMG4LCTC2NTLQSF4';
client.connect(
  Uri.parse('nats://localhost'),
  connectOption: ConnectOption(
    jwt: 'YOUR_JWT_STRING',
  ),
);
```

---

## JetStream Support

NATS JetStream provides persistence, at-least-once delivery, and consumer management.

### Initialize JetStream Context
```dart
final client = Client();
await client.connect(Uri.parse('nats://localhost:4222'));

final js = client.jetStream();
```

### Stream Management
```dart
// Define stream configuration
final streamConfig = StreamConfig(
  name: 'orders-stream',
  subjects: ['orders.*'],
  storage: 'memory', // Or 'file' (default)
);

// Create the stream
await js.addStream(streamConfig);

// Retrieve stream information
final info = await js.getStream('orders-stream');
print('Active messages: ${info.state.messages}');

// Purge a stream (keep config, delete messages)
await js.purgeStream('orders-stream');

// Delete a stream entirely
await js.deleteStream('orders-stream');
```

### Publish to a Stream
JetStream publishes wait for a publish acknowledgement (`PubAck`) from the server to guarantee persistence:
```dart
final pubAck = await js.publishString('orders.created', 'Order Data');
print('Published to stream ${pubAck.stream} at sequence ${pubAck.sequence}');
```

### Pull Consumer Lifecycle
Pull consumers allow you to pull batches of messages on demand:
```dart
final consumerConfig = ConsumerConfig(
  durable: 'billing-service', // Required for pull mode durability
  ackPolicy: 'explicit',
  deliverPolicy: 'all',
);

// Create the consumer
await js.addConsumer('orders-stream', consumerConfig);

// Pull a batch of messages
final messages = await js.pull(
  'orders-stream',
  'billing-service',
  batch: 5,
  timeout: const Duration(seconds: 2),
);

for (final msg in messages) {
  print('Pulled: ${msg.string}');
  
  // Acknowledge the message (standard)
  msg.ack();
  
  // Or sync ack (waits for confirmation)
  // await msg.ackSync();
  
  // Or Nak (triggers immediate redelivery)
  // msg.nak();
  
  // Or Term (term/terminate to prevent any redelivery)
  // msg.term();
}
```

---

## Key-Value Store

The Key-Value (KV) Store is built on top of JetStream. It allows you to store, retrieve, delete, and watch keys in a bucket.

### Create or Bind to a Bucket
```dart
// Create a KV store instance (setting create: true will provision the backing stream)
final kv = await js.keyValue('my_bucket', create: true, storage: 'memory');
```

### Write and Read Keys
```dart
// Put a string or binary value
await kv.putString('user:123', 'John Doe');

// Get the latest entry
final entry = await kv.get('user:123');
if (entry != null) {
  print('Value: ${entry.string}');
  print('Revision: ${entry.revision}');
  print('Created: ${entry.created}');
}
```

### Delete and Purge Keys
- `delete`: Inserts a tombstone, keeping the historical record but marking the key as deleted.
- `purge`: Permanently removes the key and all its historical values.
```dart
// Delete key
await kv.delete('user:123');

// Purge key history
await kv.purge('user:123');
```

### Real-Time Watcher
Listen for modifications to keys in real-time. You can watch a specific key or all keys using wildcards:
```dart
final subscription = kv.watch(key: 'user.*', includeHistory: true).listen((entry) {
  if (entry == null) {
    print('Key was deleted/purged');
  } else {
    print('Key: ${entry.key}, Value: ${entry.string}');
  }
});

// To stop watching
await subscription.cancel();
```

---

## Object Store

The Object Store offers a way to store files or large payloads. Under the hood, it chunks files into 128 KiB blocks and runs end-to-end SHA-256 digest validation to ensure data integrity during uploads and downloads.

### Create or Bind to an Object Store Bucket
```dart
final os = await js.objectStore('my_files', create: true, storage: 'memory');
```

### Put and Get Objects
```dart
// Upload an object
final content = 'Hello NATS Object Store! ' * 5000; // Large payload
final info = await os.putString('notes.txt', content, description: 'User notes');
print('Uploaded object chunks: ${info.chunks}');

// Download and verify integrity
final retrieved = await os.getString('notes.txt');
print('Downloaded content: $retrieved');
```

### List and Delete Objects
```dart
// List active objects in bucket
final list = await os.list();
for (final obj in list) {
  print('Object: ${obj.name}, Size: ${obj.size} bytes');
}

// Delete object and reclaim NATS storage space
await os.delete('notes.txt');
```

---

## Development & Testing

For detailed instructions on setting up your local environment, managing NATS Docker containers, and running tests, please refer to the [DEVELOPMENT.md](file:///Users/chartchuo/workspace/dart-nats/DEVELOPMENT.md) guide.
