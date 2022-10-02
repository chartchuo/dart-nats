import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

// start nats server using
// nats-server -DV -m 8222 -user foo -pass bar

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      unawaited(client.tcpConnect('localhost',
          port: 4220,
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
      await client.tcpConnect('localhost',
          port: 4220, connectOption: ConnectOption(user: 'foo', pass: 'bar'));
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
