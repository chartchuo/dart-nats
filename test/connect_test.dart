import 'dart:typed_data';

import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

// please start nats-server on localhost before testing
// nats-server -c test/nats.conf

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      unawaited(
          client.connect(Uri.parse('ws://localhost:80'), retryInterval: 1));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('await', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('status stream', () async {
      var client = Client();
      var statusHistory = <Status>[];
      client.statusStream.listen((s) {
        // print(s);
        statusHistory.add(s);
      });
      unawaited(
          client.connect(Uri.parse('ws://localhost:80'), retryInterval: 1));
      await client.close();
      await client.connect(Uri.parse('ws://localhost:80'), retryInterval: 1);
      await client.close();

      expect(statusHistory[0], equals(Status.connecting));
      expect(statusHistory[1], equals(Status.connected));
      expect(statusHistory[2], equals(Status.closed));
      expect(statusHistory[3], equals(Status.connecting));
      expect(statusHistory[4], equals(Status.connected));
      expect(statusHistory[5], equals(Status.closed));
      expect(statusHistory[6], equals(Status.disconnected));
    });
  });
}
