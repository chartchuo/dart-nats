import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('all', () {
    test('nats:', () async {
      var client = Client();

      await client.connect(Uri.parse('nats://localhost:4222'),
          retryInterval: 1);
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
  });
}
