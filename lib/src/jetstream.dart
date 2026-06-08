import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_nats/dart_nats.dart';

/// Publish acknowledgment returned by JetStream server
class PubAck {
  /// Stream name
  final String stream;

  /// Sequence number
  final int sequence;

  /// Optional JetStream domain name
  final String? domain;

  /// Whether the message is identified as a duplicate
  final bool duplicate;

  /// Constructor for PubAck
  PubAck({
    required this.stream,
    required this.sequence,
    this.domain,
    this.duplicate = false,
  });

  /// Factory from JSON map
  factory PubAck.fromJson(Map<String, dynamic> json) {
    return PubAck(
      stream: json['stream'] as String,
      sequence: json['seq'] as int,
      domain: json['domain'] as String?,
      duplicate: json['duplicate'] as bool? ?? false,
    );
  }
}

/// JetStream Stream Configuration
class StreamConfig {
  /// Stream name
  final String name;

  /// Subjects bound to the stream
  final List<String> subjects;

  /// Storage type: 'file' or 'memory'
  final String storage;

  /// Retention policy: 'limits', 'interest', 'workqueue'
  final String retention;

  /// Maximum messages stored (-1 for unlimited)
  final int maxMsgs;

  /// Maximum bytes stored (-1 for unlimited)
  final int maxBytes;

  /// Constructor for StreamConfig
  StreamConfig({
    required this.name,
    required this.subjects,
    this.storage = 'file',
    this.retention = 'limits',
    this.maxMsgs = -1,
    this.maxBytes = -1,
  });

  /// Export configuration to JSON map
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'subjects': subjects,
      'storage': storage,
      'retention': retention,
      'max_msgs': maxMsgs,
      'max_bytes': maxBytes,
    };
  }
}

/// JetStream Consumer Configuration
class ConsumerConfig {
  /// Durable consumer name (required for Pull Mode durability)
  final String? durable;

  /// Delivery subject (required for Push Mode; omit/null for Pull Mode)
  final String? deliverSubject;

  /// Filter subject to bind to
  final String? filterSubject;

  /// Acknowledgment policy: 'explicit', 'none', 'all'
  final String ackPolicy;

  /// Delivery policy: 'all', 'last', 'new'
  final String deliverPolicy;

  /// Constructor for ConsumerConfig
  ConsumerConfig({
    this.durable,
    this.deliverSubject,
    this.filterSubject,
    this.ackPolicy = 'explicit',
    this.deliverPolicy = 'all',
  });

  /// Export configuration to JSON map
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'ack_policy': ackPolicy,
      'deliver_policy': deliverPolicy,
    };
    if (durable != null) map['durable_name'] = durable;
    if (deliverSubject != null) map['deliver_subject'] = deliverSubject;
    if (filterSubject != null) map['filter_subject'] = filterSubject;
    return map;
  }
}

/// NATS JetStream Context
class JetStream {
  /// NATS core client instance
  final Client client;

  /// Constructor for JetStream context
  JetStream(this.client);

  /// Publish a byte message to a JetStream subject and wait for acknowledgement
  Future<PubAck> publish(String subject, Uint8List data,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final response = await client.request(subject, data, timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return PubAck.fromJson(map as Map<String, dynamic>);
  }

  /// Publish a string message to a JetStream subject and wait for acknowledgement
  Future<PubAck> publishString(String subject, String str,
      {Duration timeout = const Duration(seconds: 2)}) {
    return publish(subject, Uint8List.fromList(utf8.encode(str)),
        timeout: timeout);
  }

  /// Create or update a stream
  Future<bool> addStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.STREAM.CREATE.${config.name}';
    final payload = utf8.encode(jsonEncode(config.toJson()));
    final response = await client.request(subject, Uint8List.fromList(payload),
        timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return true;
  }

  /// Delete a stream
  Future<bool> deleteStream(String streamName,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.STREAM.DELETE.$streamName';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return true;
  }

  /// Create a consumer (durable or ephemeral) on a stream
  Future<bool> addConsumer(String streamName, ConsumerConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    String subject;
    if (config.durable != null) {
      subject =
          '\$JS.API.CONSUMER.DURABLE.CREATE.$streamName.${config.durable}';
    } else {
      subject = '\$JS.API.CONSUMER.CREATE.$streamName';
    }
    final payload = utf8.encode(jsonEncode({
      'stream_name': streamName,
      'config': config.toJson(),
    }));
    final response = await client.request(subject, Uint8List.fromList(payload),
        timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return true;
  }

  /// Delete a consumer from a stream
  Future<bool> deleteConsumer(String streamName, String consumerName,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.CONSUMER.DELETE.$streamName.$consumerName';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return true;
  }

  /// Pull a batch of messages from a pull consumer.
  /// Returns a Future with a List of Messages.
  Future<List<Message>> pull(String stream, String consumer,
      {int batch = 1, Duration timeout = const Duration(seconds: 2)}) async {
    final inbox = client.inboxPrefix + '.' + Nuid().next();
    final sub = client.sub(inbox);

    final subject = '\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer';
    final payload = utf8.encode(jsonEncode({
      'batch': batch,
      'expires': timeout.inMicroseconds * 1000, // nanoseconds
    }));

    // Publish the pull request pointing responses to our inbox
    client.pub(subject, Uint8List.fromList(payload), replyTo: inbox);

    final messages = <Message>[];
    final completer = Completer<List<Message>>();

    StreamSubscription? streamSub;
    Timer? timer;

    void cleanup() {
      timer?.cancel();
      streamSub?.cancel();
      client.unSub(sub);
    }

    timer = Timer(timeout, () {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(messages);
      }
    });

    streamSub = sub.stream.listen((msg) {
      // Check if we got a NATS status header (e.g. 404 No Messages, 408 Request Timeout)
      final statusHeader = msg.header?.status;
      if (statusHeader != null && statusHeader >= 400) {
        cleanup();
        if (!completer.isCompleted) {
          completer.complete(messages);
        }
        return;
      }

      messages.add(msg);
      if (messages.length >= batch) {
        cleanup();
        if (!completer.isCompleted) {
          completer.complete(messages);
        }
      }
    }, onError: (err) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(err);
      }
    }, onDone: () {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(messages);
      }
    });

    return completer.future;
  }
}
