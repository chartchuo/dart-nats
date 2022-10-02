import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

var port = 8082;

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      unawaited(client.connect(Uri.parse('ws://localhost:$port'),
          retryInterval: 1,
          connectOption: ConnectOption(user: 'foo', pass: 'bar')));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('await', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:$port'),
          connectOption: ConnectOption(user: 'foo', pass: 'bar'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
  });
}
