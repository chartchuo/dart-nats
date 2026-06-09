import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('JWT/Auth fail handling', () {
    test('0026 Connect with invalid JWT throws exception', () async {
      final client = Client();
      client.seed =
          'SUAJGSBAKQHGYI7ZVKVR6WA7Z5U52URHKGGT6ZICUJXMG4LCTC2NTLQSF4';

      var threwException = false;
      try {
        await client.connect(
          Uri.parse('nats://localhost:4223'),
          retry: false, // disable retry to fail quickly
          timeout: 2,
          connectOption: ConnectOption(
            jwt: 'invalid.jwt.token',
          ),
        );
      } catch (e) {
        threwException = true;
        print('Expected exception caught: $e');
      } finally {
        await client.close();
      }

      expect(threwException, isTrue);
    });
  });
}
