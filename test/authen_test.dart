import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

var port = 8084;

void main() {
  group('all', () {
    test('token', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8084'),
          connectOption: ConnectOption(authToken: 'mytoken'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('user', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8085'),
          connectOption: ConnectOption(user: 'foo', pass: 'bar'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('jwt', () async {
      var client = Client();
      client.seed =
          'SUAJGSBAKQHGYI7ZVKVR6WA7Z5U52URHKGGT6ZICUJXMG4LCTC2NTLQSF4';
      await client.connect(
        Uri.parse('nats://localhost:4223'),
        retryInterval: 1,
        connectOption: ConnectOption(
          jwt:
              'eyJ0eXAiOiJKV1QiLCJhbGciOiJlZDI1NTE5LW5rZXkifQ.eyJqdGkiOiJBU1pFQVNGMzdKS0dPTFZLTFdKT1hOM0xZUkpHNURJUFczUEpVT0s0WUlDNFFENlAyVFlRIiwiaWF0IjoxNjY0NTI0OTU5LCJpc3MiOiJBQUdTSkVXUlFTWFRDRkUzRVE3RzVPQldSVUhaVVlDSFdSM0dRVERGRldaSlM1Q1JLTUhOTjY3SyIsIm5hbWUiOiJzaWdudXAiLCJzdWIiOiJVQzZCUVY1Tlo1V0pQRUVZTTU0UkZBNU1VMk5NM0tON09WR01DU1VaV1dORUdZQVBNWEM0V0xZUCIsIm5hdHMiOnsicHViIjp7fSwic3ViIjp7fSwic3VicyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwidHlwZSI6InVzZXIiLCJ2ZXJzaW9uIjoyfX0.8Q0HiN0h2tBvgpF2cAaz2E3WLPReKEnSmUWT43NSlXFNRpsCWpmkikxGgFn86JskEN4yast1uSj306JdOhyJBA',
        ),
      );
      var sub = client.sub('subject.foo');
      client.pubString('subject.foo', 'message1');
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('nkey', () async {
      var client = Client();
      client.seed =
          'SUACSSL3UAHUDXKFSNVUZRF5UHPMWZ6BFDTJ7M6USDXIEDNPPQYYYCU3VY';
      await client.connect(
        Uri.parse('ws://localhost:8086'),
        retryInterval: 1,
        connectOption: ConnectOption(
          nkey: 'UDXU4RCSJNZOIQHZNWXHXORDPRTGNJAHAHFRGZNEEJCPQTT2M7NLCNF4',
        ),
      );
      var sub = client.sub('subject.foo');
      client.pubString('subject.foo', 'message1');
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
  });
}
