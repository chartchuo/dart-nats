import 'dart:async';
import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('Advanced JetStream Features', () {
    late Client client;
    late JetStream js;

    setUp(() async {
      client = Client();
      await client.connect(Uri.parse('nats://localhost:4222'), retry: false);
      js = client.jetStream();
    });

    tearDown(() async {
      await client.close();
    });

    test('Direct Msg Get - getMsg and getLastMsg', () async {
      final streamName = 'direct-get-stream';
      final subject = 'direct.get.test';

      await js.createStream(StreamConfig(
        name: streamName,
        subjects: [subject],
        storage: 'memory',
      ));

      await js.publishString(subject, 'first-message');
      await js.publishString(subject, 'second-message');

      // 1. Retrieve by sequence
      final msg1 = await js.getMsg(streamName, 1);
      expect(msg1.string, equals('first-message'));
      expect(msg1.streamSequence, equals(1));

      // 2. Retrieve last by subject
      final msg2 = await js.getLastMsg(streamName, subject);
      expect(msg2.string, equals('second-message'));
      expect(msg2.streamSequence, equals(2));

      await js.deleteStream(streamName);
    });

    test('Push Subscription Helper - subscribe()', () async {
      final streamName = 'push-sub-stream';
      final subject = 'push.sub.test';

      await js.createStream(StreamConfig(
        name: streamName,
        subjects: [subject],
        storage: 'memory',
      ));

      // Use subscribe helper
      final sub = await js.subscribe(subject, stream: streamName);
      
      await js.publishString(subject, 'pushed-data');

      final msg = await sub.stream.first.timeout(const Duration(seconds: 3));
      expect(msg.string, equals('pushed-data'));

      client.unSub(sub);
      await js.deleteStream(streamName);
    });

    test('Ordered Consumer', () async {
      final streamName = 'ordered-cons-stream';
      final subject = 'ordered.cons.test';

      await js.createStream(StreamConfig(
        name: streamName,
        subjects: [subject],
        storage: 'memory',
      ));

      await js.publishString(subject, 'msg-1');
      await js.publishString(subject, 'msg-2');
      await js.publishString(subject, 'msg-3');

      final oc = js.orderedConsumer(
        streamName,
        OrderedConsumerConfig(filterSubject: subject, deliverPolicy: 'all'),
      );

      final messagesList = <Message>[];
      final completer = Completer<void>();

      final subscription = oc.messages().listen((msg) {
        messagesList.add(msg);
        if (messagesList.length >= 3) {
          completer.complete();
        }
      });

      await completer.future.timeout(const Duration(seconds: 5));
      expect(messagesList.length, equals(3));
      expect(messagesList[0].string, equals('msg-1'));
      expect(messagesList[1].string, equals('msg-2'));
      expect(messagesList[2].string, equals('msg-3'));

      await subscription.cancel();
      oc.stop();
      await js.deleteStream(streamName);
    });

    test('KeyValue Store keys(), history(), and status()', () async {
      final bucket = 'adv_kv_test';
      try {
        await js.deleteKeyValue(bucket);
      } catch (_) {}
      final kv = await js.createKeyValue(KeyValueConfig(bucket: bucket, storage: 'memory', history: 10));

      await kv.putString('a', 'apple');
      await kv.putString('b', 'banana');
      await kv.putString('a', 'apricot'); // revision of 'a'
      await kv.delete('b');

      // 1. Verify keys() - should return only active non-deleted keys
      final keysList = await kv.keys();
      expect(keysList.length, equals(1));
      expect(keysList[0], equals('a'));

      // 2. Verify history() - returns all versions of a key
      final historyList = await kv.history('a').toList();
      print('DEBUG HISTORY: ${historyList.map((e) => "${e.key} : ${e.string} (rev ${e.revision})").toList()}');
      expect(historyList.length, equals(2));
      expect(historyList[0].string, equals('apple'));
      expect(historyList[0].revision, equals(1));
      expect(historyList[1].string, equals('apricot'));
      expect(historyList[1].revision, equals(3));

      // 3. Verify status()
      final statusInfo = await kv.status();
      expect(statusInfo.bucket, equals(bucket));
      expect(statusInfo.storage, equals('memory'));
      expect(statusInfo.values, equals(4)); // 3 puts + 1 delete tombstone

      await js.deleteKeyValue(bucket);
    });

    test('Object Store putLink(), putBucketLink(), and automatic resolution', () async {
      final srcBucket = 'src_obj_bucket';
      final linkBucket = 'link_obj_bucket';

      final srcStore = await js.createObjectStore(ObjectStoreConfig(bucket: srcBucket, storage: 'memory'));
      final linkStore = await js.createObjectStore(ObjectStoreConfig(bucket: linkBucket, storage: 'memory'));

      // 1. Put standard object in source
      final targetInfo = await srcStore.putString('source-obj', 'original payload');

      // 2. Create link in link bucket pointing to source-obj
      final linkInfo = await linkStore.putLink('linked-obj', targetInfo);
      expect(linkInfo.link, isNotNull);
      expect(linkInfo.link!.bucket, equals(srcBucket));
      expect(linkInfo.link!.name, equals('source-obj'));

      // 3. Get on link should automatically resolve to target
      final resolvedData = await linkStore.getString('linked-obj');
      expect(resolvedData, equals('original payload'));

      // 4. Create link pointing to entire bucket
      final bucketLinkInfo = await linkStore.putBucketLink('bucket-link', srcBucket);
      expect(bucketLinkInfo.link, isNotNull);
      expect(bucketLinkInfo.link!.bucket, equals(srcBucket));
      expect(bucketLinkInfo.link!.name, isNull);

      await js.deleteObjectStore(srcBucket);
      await js.deleteObjectStore(linkBucket);
    });
  });
}
