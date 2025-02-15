import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('all', () {
    test('verbose', () async {
      var client = Client();
      await client.connect(
        Uri.parse('nats://localhost:4227'),
        retryInterval: 1,
        connectOption: ConnectOption(
          verbose: true,
          jwt: 'eyJ0eXAiOiJKV1QiLCJhbGciOiJlZDI1NTE5LW5rZXkifQ.eyJqdGkiOiJLQUE3TU5NRTNHQVZRNUlZUTNFTk5PNk1SVFJHSVlTWk9ESFNYS01TU1lJTFBPWkc3WFZBIiwiaWF0IjoxNjY3NzE0ODEzLCJpc3MiOiJBQVhGT1pVNFVIS1lCTTVCUVZPQ01LNUZYSkVCTlFSU0NZUTJKTTNUNjdSVEpRTlhVNlFKS0tGQyIsIm5hbWUiOiJ0ZXN0Iiwic3ViIjoiVUNHVkMzVkY1SVhBQk9DV0w3Tkw3WFFTR1lMVzRBT0lNWEdNWUpJSVlCSlgyVjZUN1JWMzJYVVEiLCJuYXRzIjp7InB1YiI6eyJhbGxvdyI6WyJ0ZXN0Il19LCJzdWIiOnt9LCJzdWJzIjotMSwiZGF0YSI6LTEsInBheWxvYWQiOi0xLCJ0eXBlIjoidXNlciIsInZlcnNpb24iOjJ9fQ.Sa27RTijMuACL7EhPwxYwmGPINRXqaQtlrODQaPYf-JtrJo43CTKQ_I1jryG_VK7il61Y-LjxAiJJZxehNO7Cw',
        ),
      );
      var result = await client.pubString('test', 'message1');
      expect(result, equals(true));
      result = await client.pubString('other', 'message2');
      expect(result, equals(false));
      await client.close();
    });
  });
}
