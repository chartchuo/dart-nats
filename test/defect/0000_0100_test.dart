import 'dart:async';

import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('all', () {
    test('0016 nats: Connect to invalid ws connection does not give error',
        () async {
      var client = Client();
      var gotit = false;
      try {
        await client.connect(Uri.parse('nats://localhost:1234'),
            retry: false, retryInterval: 1);
      } on NatsException {
        gotit = true;
      }
      expect(gotit, equals(true));
    });

    test(
        '0020 larger MSG payloads not always working, check if full payload present in buffer',
        () async {
      var client = Client();
      unawaited(client.connect(Uri.parse('nats://localhost')));
      var sub = client.sub('subject1');
      var str21k = '';
      for (var i = 0; i < 21000; i++) {
        str21k += '${i % 10}';
      }
      client.pubString('subject1', str21k);
      var msg = await sub.stream.first;
      await client.close();
      expect(msg.string, equals(str21k));
    });

    test('0022 Connection to nats with macos and mobile:', () async {
      var client = Client();
      unawaited(
          client.connect(Uri.parse('nats://demo.nats.io'), retryInterval: 1));
      var sub = client.sub('subject1');
      client.pubString('subject1', 'message1');
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });

    test(
        '0034 StateError: StreamSink is closed - unsubscribing when client is closed should not throw',
        () async {
      var client = Client();
      await client.connect(Uri.parse('nats://localhost:4222'));
      var sub = client.sub('subject1');
      await client.close();
      expect(() => client.unSub(sub), returnsNormally);
    });
  });
}
