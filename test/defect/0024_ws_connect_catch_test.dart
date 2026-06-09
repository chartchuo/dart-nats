import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('WS Connect Exception Catch (Issue #24)', () {
    test('0024 catch websocket connection exception when server is offline',
        () async {
      final client = Client();
      var gotit = false;
      var caughtExceptionType = '';
      dynamic caughtException;

      client.statusStream.listen(
        (s) {
          print('Status: $s');
        },
        onError: (e) {
          print('Status stream error: $e');
        },
      );

      try {
        await client.connect(
          Uri.parse('ws://localhost:1234'),
          retry: false,
          retryInterval: 1,
        );
      } catch (e, stackTrace) {
        gotit = true;
        caughtException = e;
        caughtExceptionType = e.runtimeType.toString();
        print('Caught expected exception: $e (type: $caughtExceptionType)');
        print('Stack trace:\n$stackTrace');
      } finally {
        await client.close();
      }

      expect(gotit, isTrue);
      expect(caughtExceptionType, equals('NatsException'));
      expect(caughtException.toString(), contains('WebSocketChannelException'));
      expect(client.connected, isFalse);
    });
  });
}
