import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'client.dart';
import 'common.dart';
import 'inbox.dart';
import 'message.dart';
import 'kv.dart';
import 'object_store.dart';
import 'subscription.dart';

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

  /// Allow direct message gets
  final bool? allowDirect;

  /// Max messages per subject
  final int? maxMsgsPerSubject;

  /// Max message size
  final int? maxMsgSize;

  /// Maximum age of messages in the stream
  final Duration? maxAge;

  /// Number of replicas for the stream configuration
  final int? numReplicas;

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
    this.allowDirect,
    this.maxMsgsPerSubject,
    this.maxMsgSize,
    this.maxAge,
    this.numReplicas,
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
    if (allowDirect != null) {
      map['allow_direct'] = allowDirect;
    }
    if (maxMsgsPerSubject != null) {
      map['max_msgs_per_subject'] = maxMsgsPerSubject;
    }
    if (maxMsgSize != null) {
      map['max_msg_size'] = maxMsgSize;
    }
    if (maxAge != null) {
      map['max_age'] = maxAge!.inMicroseconds * 1000;
    }
    if (numReplicas != null) {
      map['num_replicas'] = numReplicas;
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

  /// Optional start sequence
  final int? optStartSeq;

  /// Flow control enabled
  final bool? flowControl;

  /// Idle heartbeat duration
  final Duration? idleHeartbeat;

  /// Constructor for ConsumerConfig
  ConsumerConfig({
    this.durable,
    this.deliverSubject,
    this.filterSubject,
    this.ackPolicy = 'explicit',
    this.deliverPolicy = 'all',
    this.optStartSeq,
    this.flowControl,
    this.idleHeartbeat,
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
    if (optStartSeq != null) map['opt_start_seq'] = optStartSeq;
    if (flowControl != null) map['flow_control'] = flowControl;
    if (idleHeartbeat != null) {
      map['idle_heartbeat'] = idleHeartbeat!.inMicroseconds * 1000; // in nanoseconds
    }
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

/// EXPERIMENTAL: JetStream APIs are experimental and subject to change in future releases.
///
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
      if (opts.msgId != null) {
        h.add('Nats-Msg-Id', opts.msgId!);
      }
      if (opts.expectStream != null) {
        h.add('Nats-Expected-Stream', opts.expectStream!);
      }
      if (opts.expectLastSeq != null) {
        h.add('Nats-Expected-Last-Sequence', opts.expectLastSeq!.toString());
      }
      if (opts.expectLastMsgId != null) {
        h.add('Nats-Expected-Last-Msg-Id', opts.expectLastMsgId!);
      }
      if (opts.expectLastSubjectSeq != null) {
        h.add('Nats-Expected-Last-Subject-Sequence',
            opts.expectLastSubjectSeq!.toString());
      }
    }

    final response =
        await client.request(subject, data, timeout: timeout, header: h);
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

  /// Get a handle to a stream
  JsStream stream(String name) {
    return JsStream(this, name);
  }

  /// Get a handle to a consumer
  Consumer consumer(String streamName, String consumerName) {
    return Consumer(this, streamName, consumerName);
  }

  /// Get information about a stream
  Future<StreamInfo> streamInfo(String streamName,
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

  /// Get information about a stream (Deprecated: Use streamInfo instead)
  @Deprecated('Use streamInfo instead')
  Future<StreamInfo> getStream(String streamName,
      {Duration timeout = const Duration(seconds: 2)}) {
    return streamInfo(streamName, timeout: timeout);
  }

  /// Update an existing stream
  Future<JsStream> updateStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.STREAM.UPDATE.${config.name}';
    final payload = utf8.encode(jsonEncode(config.toJson()));
    final response = await client.request(subject, Uint8List.fromList(payload),
        timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return JsStream(this, config.name);
  }

  /// Create a stream
  Future<JsStream> createStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final subject = '\$JS.API.STREAM.CREATE.${config.name}';
    final payload = utf8.encode(jsonEncode(config.toJson()));
    final response = await client.request(subject, Uint8List.fromList(payload),
        timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return JsStream(this, config.name);
  }

  /// Create or update a stream
  Future<JsStream> createOrUpdateStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      await streamInfo(config.name, timeout: timeout);
      return await updateStream(config, timeout: timeout);
    } on NatsException catch (_) {
      return await createStream(config, timeout: timeout);
    }
  }

  /// Create or update a stream (Deprecated: Use createStream instead)
  @Deprecated('Use createStream instead')
  Future<bool> addStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    await createStream(config, timeout: timeout);
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

  /// Purge a stream (Deprecated: Use stream(streamName).purge() instead)
  @Deprecated('Use stream(streamName).purge() instead')
  Future<bool> purgeStream(String streamName,
      {Duration timeout = const Duration(seconds: 2)}) {
    return _purgeStream(streamName, timeout: timeout);
  }

  /// Internal purge helper
  Future<bool> _purgeStream(String streamName,
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
    return list
        .map((item) => StreamInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Find a stream name by a subject it covers
  Future<String> streamNameBySubject(String subject,
      {Duration timeout = const Duration(seconds: 2)}) async {
    const apiSubject = '\$JS.API.STREAM.NAMES';
    final payload = utf8.encode(jsonEncode({'subject': subject}));
    final response = await client.request(apiSubject, Uint8List.fromList(payload),
        timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    final streams = map['streams'] as List?;
    if (streams == null || streams.isEmpty) {
      throw NatsException('no stream matches subject');
    }
    return streams.first as String;
  }

  /// Get information about a consumer
  Future<ConsumerInfo> consumerInfo(String streamName, String consumerName,
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

  /// Get information about a consumer (Deprecated: Use consumerInfo instead)
  @Deprecated('Use consumerInfo instead')
  Future<ConsumerInfo> getConsumer(String streamName, String consumerName,
      {Duration timeout = const Duration(seconds: 2)}) {
    return consumerInfo(streamName, consumerName, timeout: timeout);
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
    return list
        .map((item) => ConsumerInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Create a consumer (durable or ephemeral) on a stream
  Future<Consumer> createConsumer(String streamName, ConsumerConfig config,
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
    final consumerName = config.durable ?? map['name'] as String? ?? '';
    return Consumer(this, streamName, consumerName);
  }

  /// Create or update a consumer
  Future<Consumer> createOrUpdateConsumer(String streamName, ConsumerConfig config,
      {Duration timeout = const Duration(seconds: 2)}) {
    return createConsumer(streamName, config, timeout: timeout);
  }

  /// Create a consumer (durable or ephemeral) on a stream (Deprecated: Use createConsumer instead)
  @Deprecated('Use createConsumer instead')
  Future<bool> addConsumer(String streamName, ConsumerConfig config,
      {Duration timeout = const Duration(seconds: 2)}) async {
    await createConsumer(streamName, config, timeout: timeout);
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

  /// Pull a batch of messages from a pull consumer (Deprecated: Use consumer(stream, consumer).fetch() instead)
  @Deprecated('Use consumer(stream, consumer).fetch() instead')
  Future<List<Message>> pull(String stream, String consumer,
      {int batch = 1, Duration timeout = const Duration(seconds: 2)}) {
    return _pull(stream, consumer, batch: batch, timeout: timeout);
  }

  /// Internal pull implementation
  Future<List<Message>> _pull(String stream, String consumer,
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

  /// Create a new Key-Value bucket
  Future<KeyValue> createKeyValue(KeyValueConfig config) async {
    await createStream(config.toStreamConfig());
    return KeyValue(client, config.bucket);
  }

  /// Bind to an existing Key-Value bucket
  Future<KeyValue> keyValue(String bucket,
      {bool create = false, String? storage = 'file', int history = 1}) async {
    if (create) {
      final config = KeyValueConfig(
        bucket: bucket,
        storage: storage ?? 'file',
        history: history,
      );
      await createKeyValue(config);
    }
    return KeyValue(client, bucket);
  }

  /// Delete a Key-Value bucket
  Future<bool> deleteKeyValue(String bucket,
      {Duration timeout = const Duration(seconds: 2)}) {
    return deleteStream('KV_$bucket', timeout: timeout);
  }

  /// Create a new Object Store bucket
  Future<ObjectStore> createObjectStore(ObjectStoreConfig config) async {
    await createStream(config.toStreamConfig());
    return ObjectStore(client, config.bucket);
  }

  /// Bind to an existing Object Store bucket
  Future<ObjectStore> objectStore(String bucket,
      {bool create = false, String? storage = 'file'}) async {
    if (create) {
      final config = ObjectStoreConfig(
        bucket: bucket,
        storage: storage ?? 'file',
      );
      await createObjectStore(config);
    }
    return ObjectStore(client, bucket);
  }

  /// Delete an Object Store bucket
  Future<bool> deleteObjectStore(String bucket,
      {Duration timeout = const Duration(seconds: 2)}) {
    return deleteStream('OBJ_$bucket', timeout: timeout);
  }

  /// Get a specific message from a stream by its sequence number
  Future<Message> getMsg(String stream, int seq, {Duration timeout = const Duration(seconds: 2)}) async {
    final apiSubject = '\$JS.API.STREAM.MSG.GET.$stream';
    final payload = utf8.encode(jsonEncode({
      'seq': seq,
    }));
    final response = await client.request(apiSubject, Uint8List.fromList(payload), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return _parseRawStreamMsg(stream, map['message'] as Map<String, dynamic>);
  }

  /// Get the last message in a stream for a specific subject
  Future<Message> getLastMsg(String stream, String subject, {Duration timeout = const Duration(seconds: 2)}) async {
    final apiSubject = '\$JS.API.STREAM.MSG.GET.$stream';
    final payload = utf8.encode(jsonEncode({
      'last_by_subj': subject,
    }));
    final response = await client.request(apiSubject, Uint8List.fromList(payload), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return _parseRawStreamMsg(stream, map['message'] as Map<String, dynamic>);
  }

  Message _parseRawStreamMsg(String stream, Map<String, dynamic> jsonMsg) {
    final subject = jsonMsg['subject'] as String;
    final seq = jsonMsg['seq'] as int;
    final dataStr = jsonMsg['data'] as String? ?? '';
    final value = base64.decode(dataStr);

    Header? header;
    final hdrs = jsonMsg['hdrs'] as String?;
    if (hdrs != null && hdrs.isNotEmpty) {
      final decodedHdrs = base64.decode(hdrs);
      header = Header.fromBytes(decodedHdrs);
    }

    // Embed the sequence info into a dummy replyTo subject to support msg.streamSequence and msg.consumerSequence
    final dummyReply = '\$JS.ACK.$stream.dummy.1.$seq.$seq.0.0';

    return Message(subject, 0, value, client,
        replyTo: dummyReply, header: header);
  }

  /// Subscribe to a JetStream subject using a push consumer. (Deprecated: Use createConsumer and pull instead)
  @Deprecated('Use createConsumer and pull instead')
  Future<Subscription> subscribe(
    String subject, {
    String? stream,
    String? durable,
    String? queueGroup,
    bool manualAck = false,
    String deliverPolicy = 'all',
  }) async {
    String? targetStream = stream;
    if (targetStream == null) {
      final streams = await listStreams();
      for (final s in streams) {
        if (s.config.subjects.contains(subject)) {
          targetStream = s.config.name;
          break;
        }
      }
    }
    if (targetStream == null) {
      throw NatsException('Could not find a stream for subject: $subject');
    }

    final deliverSubject = client.inboxPrefix + '.' + Nuid().next();

    final consumerConfig = ConsumerConfig(
      durable: durable,
      deliverSubject: deliverSubject,
      filterSubject: subject,
      ackPolicy: manualAck ? 'explicit' : 'none',
      deliverPolicy: deliverPolicy,
    );

    await createConsumer(targetStream, consumerConfig);

    return client.sub(deliverSubject, queueGroup: queueGroup);
  }

  /// Create an Ordered Consumer on a stream.
  OrderedConsumer orderedConsumer(String stream, OrderedConsumerConfig config) {
    return OrderedConsumer(this, stream, config);
  }

  /// Get JetStream account usage information and statistics
  Future<AccountInfo> accountInfo(
      {Duration timeout = const Duration(seconds: 2)}) async {
    const subject = '\$JS.API.INFO';
    final response =
        await client.request(subject, Uint8List.fromList([]), timeout: timeout);
    final map = jsonDecode(response.string);
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    return AccountInfo.fromJson(map as Map<String, dynamic>);
  }
}

/// Configuration options for an Ordered Consumer.
class OrderedConsumerConfig {
  /// Subject to filter messages from the stream
  final String? filterSubject;

  /// Starting point for message delivery: 'all', 'last', 'new', 'by_start_sequence', etc.
  final String deliverPolicy;

  /// Starting sequence number (used if deliverPolicy is 'by_start_sequence')
  final int? optStartSeq;

  /// Starting time (used if deliverPolicy is 'by_start_time')
  final DateTime? optStartTime;

  /// Constructor
  OrderedConsumerConfig({
    this.filterSubject,
    this.deliverPolicy = 'all',
    this.optStartSeq,
    this.optStartTime,
  });
}

/// Managed pull/push consumer providing ordered delivery guarantees.
class OrderedConsumer {
  /// The JetStream context
  final JetStream js;

  /// The Stream name
  final String stream;

  /// The configuration options
  final OrderedConsumerConfig config;

  int _lastSeq = 0;
  String? _currentConsumerName;
  StreamController<Message>? _controller;
  StreamSubscription? _sub;
  bool _active = true;

  /// Constructor for OrderedConsumer
  OrderedConsumer(this.js, this.stream, this.config) {
    if (config.deliverPolicy == 'by_start_sequence' && config.optStartSeq != null) {
      _lastSeq = config.optStartSeq! - 1;
    }
  }

  /// Get a Stream of ordered messages.
  Stream<Message> messages() {
    _controller = StreamController<Message>(
      onCancel: () {
        stop();
      },
    );
    _start();
    return _controller!.stream;
  }

  /// Stop the Ordered Consumer and release NATS resources.
  void stop() {
    _active = false;
    _cleanup();
    if (_controller != null && !_controller!.isClosed) {
      _controller!.close();
    }
  }

  void _cleanup() {
    _sub?.cancel();
    if (_currentConsumerName != null) {
      final name = _currentConsumerName!;
      js.deleteConsumer(stream, name).catchError((_) => false);
      _currentConsumerName = null;
    }
  }

  Future<void> _start() async {
    int expectedConsumerSeq = 1;

    while (_active) {
      try {
        final name = 'OC_${Nuid().next()}';
        _currentConsumerName = name;

        final deliverSubject = js.client.inboxPrefix + '.' + Nuid().next();
        final coreSub = js.client.sub(deliverSubject);

        // Build consumer configuration
        final consumerConfig = ConsumerConfig(
          durable: null, // Ephemeral
          deliverSubject: deliverSubject,
          filterSubject: config.filterSubject,
          ackPolicy: 'none',
          deliverPolicy: _lastSeq == 0 ? config.deliverPolicy : 'by_start_sequence',
          optStartSeq: _lastSeq == 0 ? config.optStartSeq : _lastSeq + 1,
          flowControl: true,
          idleHeartbeat: const Duration(seconds: 5),
        );

        await js.createConsumer(stream, consumerConfig);

        expectedConsumerSeq = 1;
        final completer = Completer<void>();

        _sub = coreSub.stream.listen(
          (msg) {
            // Check for heartbeats (Status header >= 100)
            final status = msg.header?.status;
            if (status != null && status >= 100 && status < 300) {
              // Idle heartbeat or flow control
              // Under flow control, respond if replyTo is present
              if (msg.replyTo != null && msg.replyTo!.isNotEmpty) {
                js.client.pub(msg.replyTo!, Uint8List(0));
              }
              return;
            }

            final seq = msg.streamSequence;
            final consSeq = msg.consumerSequence;

            if (seq == null || consSeq == null) return;

            // Check if there is a gap in the consumer sequence
            if (consSeq != expectedConsumerSeq) {
              // Sequence gap detected! Reset consumer.
              _sub?.cancel();
              js.deleteConsumer(stream, name).catchError((_) => false);
              completer.complete();
              return;
            }

            _lastSeq = seq;
            expectedConsumerSeq++;

            if (_controller != null && !_controller!.isClosed) {
              _controller!.add(msg);
            }
          },
          onError: (err) {
            _sub?.cancel();
            js.deleteConsumer(stream, name).catchError((_) => false);
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            _sub?.cancel();
            js.deleteConsumer(stream, name).catchError((_) => false);
            if (!completer.isCompleted) completer.complete();
          },
        );

        // Wait until consumer resets or closes
        await completer.future;
      } catch (e) {
        // Wait before retrying
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }
}

/// NATS JetStream Stream handle wrapping operations for a specific stream.
class JsStream {
  final JetStream js;
  final String name;

  JsStream(this.js, this.name);

  /// Get details/status of this stream
  Future<StreamInfo> info({Duration timeout = const Duration(seconds: 2)}) {
    return js.streamInfo(name, timeout: timeout);
  }

  /// Purge all messages from this stream
  Future<bool> purge({Duration timeout = const Duration(seconds: 2)}) {
    return js._purgeStream(name, timeout: timeout);
  }

  /// Bind to a consumer on this stream
  Consumer consumer(String consumerName) {
    return js.consumer(name, consumerName);
  }

  /// Create a consumer on this stream
  Future<Consumer> createConsumer(ConsumerConfig config,
      {Duration timeout = const Duration(seconds: 2)}) {
    return js.createConsumer(name, config, timeout: timeout);
  }
}

/// NATS JetStream Consumer handle wrapping operations for a specific consumer.
class Consumer {
  final JetStream js;
  final String streamName;
  final String name;

  Consumer(this.js, this.streamName, this.name);

  /// Get status of this consumer
  Future<ConsumerInfo> info({Duration timeout = const Duration(seconds: 2)}) {
    return js.consumerInfo(streamName, name, timeout: timeout);
  }

  /// Pull a batch of messages from this pull consumer
  Future<List<Message>> fetch(
      {int batch = 1, Duration timeout = const Duration(seconds: 2)}) {
    return js._pull(streamName, name, batch: batch, timeout: timeout);
  }
}

/// JetStream Tier resource usage
class Tier {
  final int memory;
  final int storage;
  final int reservedMemory;
  final int reservedStorage;
  final int streams;
  final int consumers;

  Tier({
    required this.memory,
    required this.storage,
    required this.reservedMemory,
    required this.reservedStorage,
    required this.streams,
    required this.consumers,
  });

  factory Tier.fromJson(Map<String, dynamic> json) {
    return Tier(
      memory: json['memory'] as int? ?? 0,
      storage: json['storage'] as int? ?? 0,
      reservedMemory: json['reserved_memory'] as int? ?? 0,
      reservedStorage: json['reserved_storage'] as int? ?? 0,
      streams: json['streams'] as int? ?? 0,
      consumers: json['consumers'] as int? ?? 0,
    );
  }
}

/// JetStream API usage statistics for an account
class APIStats {
  final int level;
  final int total;
  final int errors;
  final int inflight;

  APIStats({
    required this.level,
    required this.total,
    required this.errors,
    required this.inflight,
  });

  factory APIStats.fromJson(Map<String, dynamic> json) {
    return APIStats(
      level: json['level'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      errors: json['errors'] as int? ?? 0,
      inflight: json['inflight'] as int? ?? 0,
    );
  }
}

/// JetStream account information
class AccountInfo {
  final String domain;
  final APIStats api;
  final Tier tier;
  final Map<String, Tier> tiers;

  AccountInfo({
    required this.domain,
    required this.api,
    required this.tier,
    required this.tiers,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    final tiersMap = <String, Tier>{};
    if (json['tiers'] != null) {
      (json['tiers'] as Map<String, dynamic>).forEach((key, value) {
        tiersMap[key] = Tier.fromJson(value as Map<String, dynamic>);
      });
    }
    return AccountInfo(
      domain: json['domain'] as String? ?? '',
      api: APIStats.fromJson(json['api'] as Map<String, dynamic>? ?? {}),
      tier: Tier.fromJson(json['tier'] as Map<String, dynamic>? ?? {}),
      tiers: tiersMap,
    );
  }
}
