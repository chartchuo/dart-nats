import 'dart:typed_data';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      await client.tcpConnect('localhost', retryInterval: 1);
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      await client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('respond', () async {
      var server = Client();
      await server.tcpConnect('localhost');
      var service = server.sub('service');
      service.stream!.listen((m) {
        m.respondString('respond');
      });

      var requester = Client();
      await requester.tcpConnect('localhost');
      var inbox = newInbox();
      var inboxSub = requester.sub(inbox);

      requester.pubString('service', 'request', replyTo: inbox);

      var receive = await inboxSub.stream!.first;

      await requester.close();
      service.close();
      expect(receive.string, equals('respond'));
    });
    test('resquest', () async {
      var server = Client();
      await server.tcpConnect('localhost');
      var service = server.sub('service');
      unawaited(service.stream!.first.then((m) {
        m.respond(Uint8List.fromList('respond'.codeUnits));
      }));

      var client = Client();
      await client.tcpConnect('localhost');
      var receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));

      await client.close();
      service.close();
      expect(receive.string, equals('respond'));
    });
    test('repeat resquest', () async {
      var server = Client();
      await server.tcpConnect('localhost');
      var service = server.sub('service');
      service.stream!.listen((m) {
        m.respond(Uint8List.fromList('respond'.codeUnits));
      });

      var client = Client();
      await client.tcpConnect('localhost');
      var receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));
      receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));
      receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));
      receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));

      await client.close();
      service.close();
      expect(receive.string, equals('respond'));
    });
  });
}
