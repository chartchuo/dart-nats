import 'dart:io';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

// mkcert -install
// mkcert -cert-file server-cert.pem -key-file server-key.pem localhost ::1
// nats-server --tls --tlscert=server-cert.pem --tlskey=server-key.pem -ms 8222
// move both files to test/config

void main() {
  group('all', () {
    test('nats:', () async {
      var client = Client();
      client.acceptBadCert = true;
      await client.connect(Uri.parse('nats://localhost:4443'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('tls:', () async {
      var client = Client();
      client.acceptBadCert = true;
      await client.connect(Uri.parse('tls://localhost:4443'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('wss:', () async {
      HttpOverrides.global = MyHttpOverrides();

      var client = Client();
      client.acceptBadCert = true;
      await client.connect(Uri.parse('wss://localhost:8443'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
  });
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              true; // add your localhost detection logic here if you want
  }
}
