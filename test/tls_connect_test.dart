import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

// mkcert -install
// mkcert -cert-file server-cert.pem -key-file server-key.pem localhost ::1
// nats-server --tls --tlscert=server-cert.pem --tlskey=server-key.pem -ms 8222

//Todo
void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      unawaited(client.tcpConnect('localhost', retryInterval: 1));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream.first;
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

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
  });
}
