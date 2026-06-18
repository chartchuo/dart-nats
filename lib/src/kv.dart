import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';
import 'common.dart';
import 'message.dart';
import 'jetstream.dart';
import 'inbox.dart';

/// KeyValue Configuration
class KeyValueConfig {
  /// The bucket name.
final String bucket;
  /// Human‑readable description of the bucket.
final String description;
  /// Storage type, either 'file' or 'memory'.
final String storage; // 'file' or 'memory'
  /// Maximum number of messages per key (history depth).
final int history; // max_msgs_per_subject
  /// Maximum total bytes for the bucket (‑1 for unlimited).
final int maxBytes;
  /// Time‑to‑live for entries; 0 for no expiry.
final Duration ttl; // max_age

  /// Create a [KeyValueConfig] for a bucket.
  KeyValueConfig({
    required this.bucket,
    this.description = '',
    this.storage = 'file',
    this.history = 1,
    this.maxBytes = -1,
    this.ttl = Duration.zero,
  });

  /// Convert to JetStream StreamConfig
  StreamConfig toStreamConfig() {
    return StreamConfig(
      name: 'KV_$bucket',
      subjects: ['\$KV.$bucket.>'],
      storage: storage,
      maxMsgs: -1,
      maxBytes: maxBytes,
      allowRollup: true,
      discard: 'new',
      allowDirect: true,
      denyDelete: true,
      maxMsgsPerSubject: history,
    );
  }
}

/// KeyValue Entry holding value and metadata revision details
class KeyValueEntry {
  /// The entry's key.
final String key;
  /// The entry's value bytes.
final Uint8List value;
  /// Revision number for this entry.
final int revision;
  /// Creation timestamp of the entry.
final DateTime created;

  /// Create a [KeyValueEntry] holding a value and its metadata.
  KeyValueEntry({
    required this.key,
    required this.value,
    required this.revision,
    required this.created,
  });

  /// Get value payload as string
  String get string => utf8.decode(value);
}

/// EXPERIMENTAL: Key-Value Store APIs are experimental and subject to change in future releases.
///
/// NATS Key-Value Store implementation
class KeyValue {
  /// Underlying NATS client used for all operations.
final Client client;
  /// Name of the bucket this instance operates on.
final String bucket;
  /// Backing JetStream stream name (derived from the bucket).
final String streamName;

  /// Create a [KeyValue] store bound to [client] and [bucket].
  KeyValue(this.client, this.bucket) : streamName = 'KV_$bucket';

  /// Associate a value with a key
  /// Store a binary value under the given [key]. Returns the sequence number of the stored message.
Future<int> put(String key, Uint8List value) async {
    final subject = '\$KV.$bucket.$key';
    final ack = await client.jetStream().publish(subject, value);
    return ack.sequence;
  }

  /// Associate a string value with a key
  /// Store a string value under the given [key] by encoding it as UTF‑8.
Future<int> putString(String key, String value) {
    return put(key, Uint8List.fromList(utf8.encode(value)));
  }

  /// Retrieve the latest entry associated with a key
  /// Retrieve the latest entry for [key]; returns `null` if the key does not exist.
Future<KeyValueEntry?> get(String key) async {
    final apiSubject = '\$JS.API.STREAM.MSG.GET.$streamName';
    final payload = utf8.encode(jsonEncode({
      'last_by_subj': '\$KV.$bucket.$key',
    }));

    try {
      final response =
          await client.request(apiSubject, Uint8List.fromList(payload));
      final map = jsonDecode(response.string);
      if (map['error'] != null) {
        if (map['error']['code'] == 404) {
          return null; // Key not found
        }
        throw NatsException(map['error']['description'] as String);
      }
      return _parseEntry(key, map['message'] as Map<String, dynamic>);
    } catch (e) {
      if (e is TimeoutException) {
        return null;
      }
      rethrow;
    }
  }

  /// Delete the key (adds a deletion tombstone message to history)
  /// Delete the entry for [key] by publishing a tombstone message.
Future<bool> delete(String key) async {
    final subject = '\$KV.$bucket.$key';
    final header = Header().add('KV-Operation', 'DEL');
    final ack =
        await client.jetStream().publish(subject, Uint8List(0), header: header);
    return ack.sequence > 0;
  }

  /// Purge the key (deletes all historical versions for this key)
  /// Purge all historical versions of [key] from the stream.
Future<bool> purge(String key) async {
    final subject = '\$KV.$bucket.$key';
    final header =
        Header().add('KV-Operation', 'PURGE').add('Nats-Rollup', 'sub');
    final ack =
        await client.jetStream().publish(subject, Uint8List(0), header: header);
    return ack.sequence > 0;
  }

  /// Watch real‑time modifications for [key] (supports wild‑cards). If [includeHistory] is true, emits past entries as well.
  Stream<KeyValueEntry?> watch(
      {String key = '>', bool includeHistory = false}) {
    final controller = StreamController<KeyValueEntry?>();
    final deliverSubject = client.inboxPrefix + '.' + Nuid().next();
    final sub = client.sub(deliverSubject);

    final streamSub = sub.stream.listen((msg) {
      try {
        final parts = msg.subject!.split('.');
        if (parts.length < 3) return;
        final keyName = parts.sublist(2).join('.');

        Header? header = msg.header;
        final op = header?.get('KV-Operation');
        if (op == 'DEL' || op == 'PURGE') {
          controller.add(null);
        } else {
          controller.add(KeyValueEntry(
            key: keyName,
            value: msg.byte,
            revision: msg.streamSequence ?? 0,
            created: DateTime.now(),
          ));
        }
      } catch (e) {
        controller.addError(e);
      }
    }, onError: (err) {
      controller.addError(err);
    }, onDone: () {
      controller.close();
    });

    final consumerConfig = ConsumerConfig(
      deliverSubject: deliverSubject,
      filterSubject: '\$KV.$bucket.$key',
      deliverPolicy: includeHistory ? 'all' : 'last',
      ackPolicy: 'none',
    );

    client
        .jetStream()
        .addConsumer(streamName, consumerConfig)
        .catchError((dynamic err) {
      controller.addError(err);
      controller.close();
      throw err;
    });

    controller.onCancel = () {
      streamSub.cancel();
      client.unSub(sub);
    };

    return controller.stream;
  }

  KeyValueEntry? _parseEntry(String key, Map<String, dynamic> jsonMsg) {
    final seq = jsonMsg['seq'] as int;
    final timeStr = jsonMsg['time'] as String;
    final created = DateTime.tryParse(timeStr) ?? DateTime.now();

    Header? header;
    final hdrs = jsonMsg['hdrs'] as String?;
    if (hdrs != null && hdrs.isNotEmpty) {
      final decodedHdrs = base64.decode(hdrs);
      header = Header.fromBytes(decodedHdrs);
    }

    if (header != null) {
      final op = header.get('KV-Operation');
      if (op == 'DEL' || op == 'PURGE') {
        return null; // Key is deleted or purged
      }
    }

    final data = jsonMsg['data'] as String? ?? '';
    final value = base64.decode(data);

    return KeyValueEntry(
      key: key,
      value: value,
      revision: seq,
      created: created,
    );
  }

  /// List all active keys in this bucket (excluding deleted/purged ones).
  /// List all active keys in the bucket, excluding those that are deleted or purged.
Future<List<String>> keys({Duration timeout = const Duration(seconds: 5)}) async {
    final deliverSubject = client.inboxPrefix + '.' + Nuid().next();
    final sub = client.sub(deliverSubject);

    final consumerConfig = ConsumerConfig(
      deliverSubject: deliverSubject,
      filterSubject: '\$KV.$bucket.>',
      deliverPolicy: 'all',
      ackPolicy: 'none',
    );

    final activeKeys = <String, bool>{}; // key -> is_active
    final completer = Completer<List<String>>();
    StreamSubscription? streamSub;
    Timer? timeoutTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      streamSub?.cancel();
      client.unSub(sub);
    }

    timeoutTimer = Timer(timeout, () {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(activeKeys.entries.where((e) => e.value).map((e) => e.key).toList());
      }
    });

    streamSub = sub.stream.listen((msg) {
      try {
        final parts = msg.subject!.split('.');
        if (parts.length >= 3) {
          final keyName = parts.sublist(2).join('.');
          final op = msg.header?.get('KV-Operation');
          if (op == 'DEL' || op == 'PURGE') {
            activeKeys[keyName] = false;
          } else {
            activeKeys[keyName] = true;
          }
        }
      } catch (_) {}

      final reply = msg.replyTo;
      if (reply != null) {
        final parts = reply.split('.');
        int? pending;
        if (parts.length == 9) {
          pending = int.tryParse(parts[8]);
        } else if (parts.length == 11) {
          pending = int.tryParse(parts[10]);
        }
        if (pending == 0) {
          cleanup();
          if (!completer.isCompleted) {
            completer.complete(activeKeys.entries.where((e) => e.value).map((e) => e.key).toList());
          }
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
        completer.complete(activeKeys.entries.where((e) => e.value).map((e) => e.key).toList());
      }
    });

    try {
      await client.jetStream().addConsumer(streamName, consumerConfig);
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete([]);
      }
    }

    return completer.future;
  }

  /// Get a stream of all revisions (history) for a specific key.
  /// The stream will yield historical entries and automatically close when the existing history is fully read.
  /// Stream the historical revisions for [key] in order of creation.
Stream<KeyValueEntry> history(String key, {Duration timeout = const Duration(seconds: 5)}) {
    final controller = StreamController<KeyValueEntry>();
    final deliverSubject = client.inboxPrefix + '.' + Nuid().next();
    final sub = client.sub(deliverSubject);

    StreamSubscription? streamSub;
    Timer? timeoutTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      streamSub?.cancel();
      client.unSub(sub);
      if (!controller.isClosed) {
        controller.close();
      }
    }

    timeoutTimer = Timer(timeout, () {
      cleanup();
    });

    streamSub = sub.stream.listen((msg) {
      try {
        final parts = msg.subject!.split('.');
        if (parts.length >= 3) {
          final keyName = parts.sublist(2).join('.');
          final seq = msg.streamSequence ?? 0;
          
          controller.add(KeyValueEntry(
            key: keyName,
            value: msg.byte,
            revision: seq,
            created: DateTime.now(),
          ));
        }
      } catch (e) {
        controller.addError(e);
      }

      final reply = msg.replyTo;
      if (reply != null) {
        final parts = reply.split('.');
        int? pending;
        if (parts.length == 9) {
          pending = int.tryParse(parts[8]);
        } else if (parts.length == 11) {
          pending = int.tryParse(parts[10]);
        }
        if (pending == 0) {
          cleanup();
        }
      }
    }, onError: (err) {
      controller.addError(err);
      cleanup();
    }, onDone: () {
      cleanup();
    });

    client.jetStream().addConsumer(streamName, ConsumerConfig(
      deliverSubject: deliverSubject,
      filterSubject: '\$KV.$bucket.$key',
      deliverPolicy: 'all',
      ackPolicy: 'none',
    )).catchError((dynamic err) {
      controller.addError(err);
      cleanup();
      return false;
    });

    return controller.stream;
  }

  /// Get status details for this Key-Value bucket.
  /// Retrieve status and statistics for this bucket.
Future<KeyValueStatus> status() async {
    final info = await client.jetStream().getStream(streamName);
    return KeyValueStatus(bucket, info);
  }
}

/// Represents status and statistics of a Key-Value bucket.
class KeyValueStatus {
  /// The bucket name
  final String bucket;

  /// The backing stream information
  final StreamInfo info;

  /// Constructor
  KeyValueStatus(this.bucket, this.info);

  /// Storage type: 'file' or 'memory'
  String get storage => info.config.storage;

  /// The history depth configuration (max messages per subject)
  int get history => info.config.maxMsgsPerSubject ?? 1;

  /// Total number of stored bytes (compressed/raw size in NATS)
  int get size => info.state.bytes;

  /// Total count of operations/messages currently in the backing stream
  int get values => info.state.messages;
}
