import 'dart:async';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
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
      await service.close();
      expect(receive.string, equals('respond'));
    });
    test('request', () async {
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
      await service.close();
      expect(receive.string, equals('respond'));
    });
    test('long message', () async {
      var txt =
          '12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890';
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8080'), retryInterval: 1);
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList(txt.codeUnits));
      // client.pub('subject1', Uint8List.fromList(txt.codeUnits));
      var msg = await sub.stream.first;
      // msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals(txt));
    });

    test('pub with header', () async {
      var txt = 'this is text';
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:8080'), retryInterval: 1);
      var sub = client.sub('subject1');
      var header = Header();
      header.add('key1', 'value1');
      header.add('key2', 'value2');
      header.add('key3', 'value3');
      header.add('key4', 'value:with:colon');
      client.pub('subject1', Uint8List.fromList(txt.codeUnits), header: header);
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals(txt));
      expect(msg.header?.get('key1'), equals('value1'));
      expect(msg.header?.get('key4'), equals('value:with:colon'));
      expect(msg.header?.toBytes(), equals(header.toBytes()));
    });
  });
}
