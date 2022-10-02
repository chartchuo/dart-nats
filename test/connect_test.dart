import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

void main() {
  group('all', () {
    test('ws:', () async {
      var client = Client();
      unawaited(
          client.connect(Uri.parse('ws://localhost:8080'), retryInterval: 1));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('nats:', () async {
      var client = Client();
      unawaited(
          client.connect(Uri.parse('nats://localhost:4222'), retryInterval: 1));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('await', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8080'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('wss', () async {
      var client = Client();
      await client.connect(Uri.parse('wss://demo.nats.io:443'));
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
      await client.connect(Uri.parse('ws://localhost:8080'), retryInterval: 1);
      await client.close();

      // no runtime error should be fine
      // expect only first and last status
      expect(statusHistory.first, equals(Status.connecting));
      expect(statusHistory.last, equals(Status.closed));
    });
  });
}
