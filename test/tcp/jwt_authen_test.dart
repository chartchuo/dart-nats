import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:dart_nats/dart_nats.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
// start nats server using
// nats-server -DV -c mem_resolver.cfg

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      var raw = base32
          .decode('SUAJGSBAKQHGYI7ZVKVR6WA7Z5U52URHKGGT6ZICUJXMG4LCTC2NTLQSF4');
      client.seed = raw.sublist(2, 34);
      unawaited(client.tcpConnect('localhost',
          retryInterval: 1,
          connectOption: ConnectOption(
              jwt:
                  'eyJ0eXAiOiJKV1QiLCJhbGciOiJlZDI1NTE5LW5rZXkifQ.eyJqdGkiOiJBU1pFQVNGMzdKS0dPTFZLTFdKT1hOM0xZUkpHNURJUFczUEpVT0s0WUlDNFFENlAyVFlRIiwiaWF0IjoxNjY0NTI0OTU5LCJpc3MiOiJBQUdTSkVXUlFTWFRDRkUzRVE3RzVPQldSVUhaVVlDSFdSM0dRVERGRldaSlM1Q1JLTUhOTjY3SyIsIm5hbWUiOiJzaWdudXAiLCJzdWIiOiJVQzZCUVY1Tlo1V0pQRUVZTTU0UkZBNU1VMk5NM0tON09WR01DU1VaV1dORUdZQVBNWEM0V0xZUCIsIm5hdHMiOnsicHViIjp7fSwic3ViIjp7fSwic3VicyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwidHlwZSI6InVzZXIiLCJ2ZXJzaW9uIjoyfX0.8Q0HiN0h2tBvgpF2cAaz2E3WLPReKEnSmUWT43NSlXFNRpsCWpmkikxGgFn86JskEN4yast1uSj306JdOhyJBA')));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    // test('await', () async {
    //   var client = Client();
    //   await client.tcpConnect('localhost',
    //       connectOption: ConnectOption(
    //           jwt:
    //               'eyJ0eXAiOiJKV1QiLCJhbGciOiJlZDI1NTE5LW5rZXkifQ.eyJqdGkiOiJBU1pFQVNGMzdKS0dPTFZLTFdKT1hOM0xZUkpHNURJUFczUEpVT0s0WUlDNFFENlAyVFlRIiwiaWF0IjoxNjY0NTI0OTU5LCJpc3MiOiJBQUdTSkVXUlFTWFRDRkUzRVE3RzVPQldSVUhaVVlDSFdSM0dRVERGRldaSlM1Q1JLTUhOTjY3SyIsIm5hbWUiOiJzaWdudXAiLCJzdWIiOiJVQzZCUVY1Tlo1V0pQRUVZTTU0UkZBNU1VMk5NM0tON09WR01DU1VaV1dORUdZQVBNWEM0V0xZUCIsIm5hdHMiOnsicHViIjp7fSwic3ViIjp7fSwic3VicyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwidHlwZSI6InVzZXIiLCJ2ZXJzaW9uIjoyfX0.8Q0HiN0h2tBvgpF2cAaz2E3WLPReKEnSmUWT43NSlXFNRpsCWpmkikxGgFn86JskEN4yast1uSj306JdOhyJBA'));
    //   var sub = client.sub('subject1');
    //   var result = client.pub(
    //       'subject1', Uint8List.fromList('message1'.codeUnits),
    //       buffer: false);
    //   expect(result, true);

    //   var msg = await sub.stream!.first;
    //   await client.close();
    //   expect(String.fromCharCodes(msg.data), equals('message1'));
    // });
  });
}
