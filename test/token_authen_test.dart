import 'dart:typed_data';

import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

// start nats server using
//nats-server --auth mytoken

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      unawaited(client.connect(Uri.parse('ws://localhost:80'),
          retryInterval: 1,
          connectOption: ConnectOption(auth_token: 'mytoken')));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('await', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'),
          connectOption: ConnectOption(auth_token: 'mytoken'));
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
