import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8080'), retryInterval: 1);
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('respond', () async {
      var server = Client();
      await server.connect(Uri.parse('ws://localhost:8080'));
      var service = server.sub('service');
      service.stream.listen((m) {
        m.respondString('respond');
      });

      var requester = Client();
      await requester.connect(Uri.parse('ws://localhost:8080'));
      var inbox = newInbox();
      var inboxSub = requester.sub(inbox);

      requester.pubString('service', 'request', replyTo: inbox);

      var receive = await inboxSub.stream.first;

      await requester.close();
      await server.close();
      expect(receive.string, equals('respond'));
    });
    test('resquest', () async {
      var server = Client();
      await server.connect(Uri.parse('ws://localhost:8080'));
      var service = server.sub('service');
      unawaited(service.stream.first.then((m) {
        m.respond(Uint8List.fromList('respond'.codeUnits));
      }));

      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8080'));
      var receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));

      await client.close();
      await server.close();
      expect(receive.string, equals('respond'));
    });
    test('resquest with timeout', () async {
      var server = Client();
      await server.connect(Uri.parse('ws://localhost:8080'));
      var service = server.sub('service');
      unawaited(service.stream.first.then((m) {
        sleep(Duration(seconds: 1));
        m.respond(Uint8List.fromList('respond'.codeUnits));
      }));

      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8080'));
      var receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits),
          timeout: Duration(seconds: 3));

      await client.close();
      await server.close();
      expect(receive.string, equals('respond'));
    });
    test('resquest with timeout exception', () async {
      var server = Client();
      await server.connect(Uri.parse('ws://localhost:8080'));
      var service = server.sub('service');
      unawaited(service.stream.first.then((m) {
        sleep(Duration(seconds: 5));
        m.respond(Uint8List.fromList('respond'.codeUnits));
      }));

      var client = Client();
      var timeout = false;
      await client.connect(Uri.parse('ws://localhost:8080'));
      try {
        await client.request('service', Uint8List.fromList('request'.codeUnits),
            timeout: Duration(seconds: 2));
      } on TimeoutException {
        timeout = true;
      }
      await client.close();
      await service.close();
      await server.close();
      expect(timeout, equals(true));
    });
    test('repeat resquest', () async {
      var server = Client();
      await server.connect(Uri.parse('ws://localhost:8080'));
      var service = server.sub('service');
      service.stream.listen((m) {
        m.respond(Uint8List.fromList('respond'.codeUnits));
      });

      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8080'));
      var receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));
      receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));
      receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));
      receive = await client.request(
          'service', Uint8List.fromList('request'.codeUnits));

      await client.close();
      await server.close();
      expect(receive.string, equals('respond'));
    });
  });
}
