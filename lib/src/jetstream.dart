import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_nats/dart_nats.dart';

import 'kv.dart';
import 'object_store.dart';

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

  /// Allow rollup headers
  final bool? allowRollup;

  /// Deny delete
  final bool? denyDelete;

  /// Deny purge
  final bool? denyPurge;

  /// Discard policy: 'old', 'new'
  final String? discard;

  /// Constructor for StreamConfig
  StreamConfig({
    required this.name,
    required this.subjects,
    this.storage = 'file',
    this.retention = 'limits',
    this.maxMsgs = -1,
    this.maxBytes = -1,
    this.allowRollup,
    this.denyDelete,
    this.denyPurge,
    this.discard,
  });

  /// Export configuration to JSON map
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'subjects': subjects,
      'storage': storage,
      'retention': retention,
      'max_msgs': maxMsgs,
      'max_bytes': maxBytes,
    };
    if (allowRollup != null) {
      map['allow_rollup_hdrs'] = allowRollup;
    }
    if (denyDelete != null) {
      map['deny_delete'] = denyDelete;
    }
    if (denyPurge != null) {
      map['deny_purge'] = denyPurge;
    }
    if (discard != null) {
      map['discard'] = discard;
    }
    return map;
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

/// Publish options for JetStream de-duplication and optimistic concurrency control
class PubOpts {
  final String? msgId;
  final String? expectStream;
  final int? expectLastSeq;
  final String? expectLastMsgId;
  final int? expectLastSubjectSeq;

  PubOpts({
    this.msgId,
    this.expectStream,
    this.expectLastSeq,
    this.expectLastMsgId,
    this.expectLastSubjectSeq,
  });
}

/// JetStream Stream State
class StreamState {
  final int messages;
  final int bytes;
  final int firstSeq;
  final String firstTs;
  final int lastSeq;
  final String lastTs;
  final int consumerCount;

  StreamState({
    required this.messages,
    required this.bytes,
    required this.firstSeq,
    required this.firstTs,
    required this.lastSeq,
    required this.lastTs,
    required this.consumerCount,
  });

  factory StreamState.fromJson(Map<String, dynamic> json) {
    return StreamState(
      messages: json['messages'] as int? ?? 0,
      bytes: json['bytes'] as int? ?? 0,
      firstSeq: json['first_seq'] as int? ?? 0,
      firstTs: json['first_ts'] as String? ?? '',
      lastSeq: json['last_seq'] as int? ?? 0,
      lastTs: json['last_ts'] as String? ?? '',
      consumerCount: json['consumer_count'] as int? ?? 0,
    );
  }
}

/// JetStream Stream Information
class StreamInfo {
  final String type;
  final StreamConfig config;
  final String created;
  final StreamState state;

  StreamInfo({
    required this.type,
    required this.config,
    required this.created,
    required this.state,
  });

  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    final cfg = json['config'] as Map<String, dynamic>? ?? {};
    return StreamInfo(
      type: json['type'] as String? ?? '',
      config: StreamConfig(
        name: cfg['name'] as String? ?? '',
        subjects: List<String>.from(cfg['subjects'] as List? ?? []),
        storage: cfg['storage'] as String? ?? 'file',
        retention: cfg['retention'] as String? ?? 'limits',
        maxMsgs: cfg['max_msgs'] as int? ?? -1,
        maxBytes: cfg['max_bytes'] as int? ?? -1,
      ),
      created: json['created'] as String? ?? '',
      state: StreamState.fromJson(json['state'] as Map<String, dynamic>? ?? {}),
    );
  }
}

/// JetStream Consumer Information
class ConsumerInfo {
  final String type;
  final String streamName;
  final String name;
  final String created;
  final ConsumerConfig config;
  final int numPending;
  final int numWaiting;
  final int numAckPending;
  final int numRedelivered;

  ConsumerInfo({
    required this.type,
    required this.streamName,
    required this.name,
    required this.created,
    required this.config,
    required this.numPending,
    required this.numWaiting,
    required this.numAckPending,
    required this.numRedelivered,
  });

  factory ConsumerInfo.fromJson(Map<String, dynamic> json) {
    final cfg = json['config'] as Map<String, dynamic>? ?? {};
    return ConsumerInfo(
      type: json['type'] as String? ?? '',
      streamName: json['stream_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      created: json['created'] as String? ?? '',
      config: ConsumerConfig(
        durable: cfg['durable_name'] as String?,
        deliverSubject: cfg['deliver_subject'] as String?,
        filterSubject: cfg['filter_subject'] as String?,
        ackPolicy: cfg['ack_policy'] as String? ?? 'explicit',
        deliverPolicy: cfg['deliver_policy'] as String? ?? 'all',
      ),
      numPending: json['num_pending'] as int? ?? 0,
      numWaiting: json['num_waiting'] as int? ?? 0,
      numAckPending: json['num_ack_pending'] as int? ?? 0,
      numRedelivered: json['num_redelivered'] as int? ?? 0,
    );
  }
}

/// NATS JetStream Context
class JetStream {
  /// NATS core client instance
  final Client client;

  /// Constructor for JetStream context
  JetStream(this.client);

  /// Publish a byte message to a JetStream subject and wait for acknowledgement
  Future<PubAck> publish(
    String subject,
    Uint8List data, {
    Duration timeout = const Duration(seconds: 2),
    PubOpts? opts,
    Header? header,
  }) async {
    final h = header ?? Header();
    if (opts != null) {
      if (opts.msgId != null) h.add('Nats-Msg-Id', opts.msgId!);
      if (opts.expectStream != null) h.add('Nats-Expected-Stream', opts.expectStream!);
      if (opts.expectLastSeq != null) h.add('Nats-Expected-Last-Sequence', opts.expectLastSeq!.toString());
      if (opts.expectLastMsgId != null) h.add('Nats-Expected-Last-Msg-Id', opts.expectLastMsgId!);
      if (opts.expectLastSubjectSeq != null) h.add('Nats-Expected-Last-Subject-Sequence', opts.expectLastSubjectSeq!.toString());
    }

    final response = await client.request(subject, data, timeout: timeout, header: h);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return PubAck.fromJson(map as Map<String, dynamic>);
  }

  /// Publish a string message to a JetStream subject and wait for acknowledgement
  Future<PubAck> publishString(
    String subject,
    String str, {
    Duration timeout = const Duration(seconds: 2),
    PubOpts? opts,
    Header? header,
  }) {
    return publish(
      subject,
      Uint8List.fromList(utf8.encode(str)),
      timeout: timeout,
      opts: opts,
      header: header,
    );
  }

  /// Get information about a stream
  Future<StreamInfo> getStream(String streamName,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.STREAM.INFO.$streamName';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return StreamInfo.fromJson(map as Map<String, dynamic>);
  }

  /// Update an existing stream
  Future<bool> updateStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.STREAM.UPDATE.${config.name}';
    final payload = utf8.encode(jsonEncode(config.toJson()));
    final response = await client.request(subject, Uint8List.fromList(payload),
        timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return true;
  }

  /// Purge a stream (delete all messages but keep config/stream)
  Future<bool> purgeStream(String streamName,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.STREAM.PURGE.$streamName';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return true;
  }

  /// List all streams
  Future<List<StreamInfo>> listStreams(
      {Duration timeout = const Duration(seconds: 2)}) async {
    const subject = '\$JS.API.STREAM.LIST';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    final list = map['streams'] as List? ?? [];
    return list.map((item) => StreamInfo.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// Get information about a consumer
  Future<ConsumerInfo> getConsumer(String streamName, String consumerName,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.CONSUMER.INFO.$streamName.$consumerName';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return ConsumerInfo.fromJson(map as Map<String, dynamic>);
  }

  /// List consumers on a stream
  Future<List<ConsumerInfo>> listConsumers(String streamName,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.CONSUMER.LIST.$streamName';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    final list = map['consumers'] as List? ?? [];
    return list.map((item) => ConsumerInfo.fromJson(item as Map<String, dynamic>)).toList();
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

  /// Create or bind to a Key-Value bucket
  Future<KeyValue> keyValue(String bucket, {bool create = false, String? storage = 'file'}) async {
    if (create) {
      final config = KeyValueConfig(bucket: bucket, storage: storage ?? 'file');
      await addStream(config.toStreamConfig());
    }
    return KeyValue(client, bucket);
  }

  /// Create or bind to an Object Store bucket
  Future<ObjectStore> objectStore(String bucket, {bool create = false, String? storage = 'file'}) async {
    final streamName = 'OBJ_$bucket';
    if (create) {
      final config = StreamConfig(
        name: streamName,
        subjects: ['\$O.$bucket.>'],
        storage: storage ?? 'file',
      );
      await addStream(config);
    }
    return ObjectStore(client, bucket);
  }
}
