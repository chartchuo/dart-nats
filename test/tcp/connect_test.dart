import 'dart:typed_data';

import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

void main() {
  group('tcp', () {
    test('simple', () async {
      var client = Client();
      unawaited(client.tcpConnect('localhost', retryInterval: 1));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('await', () async {
      var client = Client();
      await client.tcpConnect('localhost');
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
