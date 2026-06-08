import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'client.dart';
import 'common.dart';
import 'message.dart';
import 'jetstream.dart';
import 'inbox.dart';

/// Object Store Metadata Information
class ObjectInfo {
  final String name;
  final String description;
  final String bucket;
  final String nuid;
  final int size;
  final DateTime mtime;
  final int chunks;
  final String digest;
  final bool deleted;

  ObjectInfo({
    required this.name,
    this.description = '',
    required this.bucket,
    required this.nuid,
    required this.size,
    required this.mtime,
    required this.chunks,
    required this.digest,
    this.deleted = false,
  });

  factory ObjectInfo.fromJson(Map<String, dynamic> json) {
    return ObjectInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      nuid: json['nuid'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      mtime: DateTime.tryParse(json['mtime'] as String? ?? '') ?? DateTime.now(),
      chunks: json['chunks'] as int? ?? 0,
      digest: json['digest'] as String? ?? '',
      deleted: json['deleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'bucket': bucket,
      'nuid': nuid,
      'size': size,
      'mtime': mtime.toUtc().toIso8601String(),
      'chunks': chunks,
      'digest': digest,
      'deleted': deleted,
    };
  }
}

/// NATS Object Store implementation
class ObjectStore {
  final Client client;
  final String bucket;
  final String streamName;
  static const int defaultChunkSize = 128 * 1024; // 128 KiB

  ObjectStore(this.client, this.bucket) : streamName = 'OBJ_$bucket';

  /// Store an object in the bucket
  Future<ObjectInfo> put(String name, Uint8List data, {String description = ''}) async {
    final nuid = Nuid().next();
    final totalSize = data.length;
    
    // Chunking the data
    final chunks = <Uint8List>[];
    var offset = 0;
    while (offset < totalSize) {
      var end = offset + defaultChunkSize;
      if (end > totalSize) {
        end = totalSize;
      }
      chunks.add(data.sublist(offset, end));
      offset = end;
    }

    // Publish all data chunks
    for (var i = 0; i < chunks.length; i++) {
      final chunkSubject = '\$O.$bucket.C.$nuid';
      await client.pub(chunkSubject, chunks[i]);
    }
    
    // Ensure all chunks are flushed to the server
    await client.flush();

    // Compute digest and create metadata
    final hash = sha256.convert(data);
    final digest = 'SHA-256=${base64Url.encode(hash.bytes)}';
    
    final info = ObjectInfo(
      name: name,
      description: description,
      bucket: bucket,
      nuid: nuid,
      size: totalSize,
      mtime: DateTime.now(),
      chunks: chunks.length,
      digest: digest,
    );

    // Save metadata
    final encodedName = base64Url.encode(utf8.encode(name));
    final metadataSubject = '\$O.$bucket.M.$encodedName';
    final payload = utf8.encode(jsonEncode(info.toJson()));
    
    await client.jetStream().publish(metadataSubject, Uint8List.fromList(payload));
    return info;
  }

  /// Store a string payload as an object
  Future<ObjectInfo> putString(String name, String value, {String description = ''}) {
    return put(name, Uint8List.fromList(utf8.encode(value)), description: description);
  }

  /// Retrieve the ObjectInfo metadata for a given name
  Future<ObjectInfo?> getInfo(String name) async {
    final encodedName = base64Url.encode(utf8.encode(name));
    final apiSubject = '\$JS.API.STREAM.MSG.GET.$streamName';
    final payload = utf8.encode(jsonEncode({
      'last_by_subj': '\$O.$bucket.M.$encodedName',
    }));

    try {
      final response = await client.request(apiSubject, Uint8List.fromList(payload));
      final map = jsonDecode(response.string);
      if (map['error'] != null) {
        if (map['error']['code'] == 404) {
          return null; // Not found
        }
        throw NatsException(map['error']['description'] as String);
      }
      final msgMap = map['message'] as Map<String, dynamic>;
      final dataStr = msgMap['data'] as String? ?? '';
      final decodedMeta = jsonDecode(utf8.decode(base64.decode(dataStr)));
      return ObjectInfo.fromJson(decodedMeta as Map<String, dynamic>);
    } catch (e) {
      if (e is TimeoutException) {
        return null;
      }
      rethrow;
    }
  }

  /// Retrieve full byte data of the object and verify integrity
  Future<Uint8List?> get(String name) async {
    final info = await getInfo(name);
    if (info == null || info.deleted) return null;

    final deliverSubject = client.inboxPrefix + '.' + Nuid().next();
    final sub = client.sub(deliverSubject);

    final consumerConfig = ConsumerConfig(
      deliverSubject: deliverSubject,
      filterSubject: '\$O.$bucket.C.${info.nuid}',
      deliverPolicy: 'all',
      ackPolicy: 'none',
    );

    final chunksData = <Uint8List>[];
    final completer = Completer<Uint8List?>();
    StreamSubscription? streamSub;
    Timer? timeoutTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      streamSub?.cancel();
      client.unSub(sub);
    }

    timeoutTimer = Timer(const Duration(seconds: 15), () {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    streamSub = sub.stream.listen((msg) {
      chunksData.add(msg.byte);
      if (chunksData.length >= info.chunks) {
        cleanup();
        
        final builder = BytesBuilder();
        for (final chunk in chunksData) {
          builder.add(chunk);
        }
        final fullData = builder.takeBytes();
        
        // Digest verification
        final hash = sha256.convert(fullData);
        final computedDigest = 'SHA-256=${base64Url.encode(hash.bytes)}';
        if (computedDigest != info.digest) {
          if (!completer.isCompleted) {
            completer.completeError(NatsException('SHA-256 digest verification failed.'));
          }
        } else {
          if (!completer.isCompleted) {
            completer.complete(fullData);
          }
        }
      }
    }, onError: (err) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(err);
      }
    });

    try {
      await client.jetStream().addConsumer('OBJ_$bucket', consumerConfig);
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// Retrieve object data as string
  Future<String?> getString(String name) async {
    final bytes = await get(name);
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  /// Delete/mark object deleted and purge its chunk history
  Future<bool> delete(String name) async {
    final info = await getInfo(name);
    if (info == null) return false;

    final encodedName = base64Url.encode(utf8.encode(name));
    final metadataSubject = '\$O.$bucket.M.$encodedName';

    final deletedInfo = ObjectInfo(
      name: info.name,
      description: info.description,
      bucket: info.bucket,
      nuid: info.nuid,
      size: 0,
      mtime: DateTime.now(),
      chunks: 0,
      digest: '',
      deleted: true,
    );

    // Update metadata to deleted=true
    final payload = utf8.encode(jsonEncode(deletedInfo.toJson()));
    await client.jetStream().publish(metadataSubject, Uint8List.fromList(payload));

    // Purge the chunks subject to reclaim NATS space
    final purgeSubject = '\$JS.API.STREAM.PURGE.OBJ_$bucket';
    final purgePayload = utf8.encode(jsonEncode({
      'filter': '\$O.$bucket.C.${info.nuid}',
    }));
    await client.request(purgeSubject, Uint8List.fromList(purgePayload));

    return true;
  }

  /// List all active objects in this Object Store bucket
  Future<List<ObjectInfo>> list() async {
    final deliverSubject = client.inboxPrefix + '.' + Nuid().next();
    final sub = client.sub(deliverSubject);

    final consumerConfig = ConsumerConfig(
      deliverSubject: deliverSubject,
      filterSubject: '\$O.$bucket.M.>',
      deliverPolicy: 'all',
      ackPolicy: 'none',
    );

    final list = <ObjectInfo>[];
    final completer = Completer<List<ObjectInfo>>();
    StreamSubscription? streamSub;
    Timer? timeoutTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      streamSub?.cancel();
      client.unSub(sub);
    }

    timeoutTimer = Timer(const Duration(seconds: 5), () {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(list);
      }
    });

    streamSub = sub.stream.listen((msg) {
      try {
        final map = jsonDecode(msg.string);
        final info = ObjectInfo.fromJson(map as Map<String, dynamic>);
        if (!info.deleted) {
          list.add(info);
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
            completer.complete(list);
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
        completer.complete(list);
      }
    });

    try {
      await client.jetStream().addConsumer('OBJ_$bucket', consumerConfig);
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete([]);
      }
    }

    return completer.future;
  }
}
