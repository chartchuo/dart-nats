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
  final String bucket;
  final String description;
  final String storage; // 'file' or 'memory'
  final int history; // max_msgs_per_subject
  final int maxBytes;
  final Duration ttl; // max_age

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
    );
  }
}

/// KeyValue Entry holding value and metadata revision details
class KeyValueEntry {
  final String key;
  final Uint8List value;
  final int revision;
  final DateTime created;

  KeyValueEntry({
    required this.key,
    required this.value,
    required this.revision,
    required this.created,
  });

  /// Get value payload as string
  String get string => utf8.decode(value);
}

/// NATS Key-Value Store implementation
class KeyValue {
  final Client client;
  final String bucket;
  final String streamName;

  KeyValue(this.client, this.bucket) : streamName = 'KV_$bucket';

  /// Associate a value with a key
  Future<int> put(String key, Uint8List value) async {
    final subject = '\$KV.$bucket.$key';
    final ack = await client.jetStream().publish(subject, value);
    return ack.sequence;
  }

  /// Associate a string value with a key
  Future<int> putString(String key, String value) {
    return put(key, Uint8List.fromList(utf8.encode(value)));
  }

  /// Retrieve the latest entry associated with a key
  Future<KeyValueEntry?> get(String key) async {
    final apiSubject = '\$JS.API.STREAM.MSG.GET.$streamName';
    final payload = utf8.encode(jsonEncode({
      'last_by_subj': '\$KV.$bucket.$key',
    }));

    try {
      final response = await client.request(apiSubject, Uint8List.fromList(payload));
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
  Future<bool> delete(String key) async {
    final subject = '\$KV.$bucket.$key';
    final header = Header().add('KV-Operation', 'DEL');
    final ack = await client.jetStream().publish(subject, Uint8List(0), header: header);
    return ack.sequence > 0;
  }

  /// Purge the key (deletes all historical versions for this key)
  Future<bool> purge(String key) async {
    final subject = '\$KV.$bucket.$key';
    final header = Header()
        .add('KV-Operation', 'PURGE')
        .add('Nats-Rollup', 'sub');
    final ack = await client.jetStream().publish(subject, Uint8List(0), header: header);
    return ack.sequence > 0;
  }

  /// Watch for real-time key modifications. Can watch a single key or a wildcard (e.g. ">").
  Stream<KeyValueEntry?> watch({String key = '>', bool includeHistory = false}) {
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

    client.jetStream().addConsumer(streamName, consumerConfig).catchError((dynamic err) {
      controller.addError(err);
      controller.close();
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
}
