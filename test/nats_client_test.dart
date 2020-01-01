import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

//please start nats-server on localhost before testing

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream.first;
      client.close();
      expect(String.fromCharCodes(msg.payload), equals('message1'));
    });
    test('newInbox', () async {
      var nuid = Nuid();
      print("'" + nuid.next() + "'");
      print("'" + nuid.next() + "'");
      print("'" + nuid.next() + "'");
      print("'" + nuid.next() + "'");
      print("'" + newInbox() + "'");
      print("'" + newInbox() + "'");
      print("'" + newInbox() + "'");
      print("'" + newInbox() + "'");
      expect(true, true);
    });
    test('pub with Uint8List', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      var msgByte = Uint8List.fromList([1, 2, 3, 129, 130]);
      client.pub('subject1', msgByte);
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payload, equals(msgByte));
    });
    test('pub with Uint8List include return and  new line', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      var msgByte = Uint8List.fromList(
          [1, 10, 3, 13, 10, 13, 130, 1, 10, 3, 13, 10, 13, 130]);
      client.pub('subject1', msgByte);
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payload, equals(msgByte));
    });
    test('byte huge data', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      var msgByte = Uint8List.fromList(
          List<int>.generate(1024 + 1024 * 4, (i) => i % 256));
      client.pub('subject1', msgByte);
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payload, equals(msgByte));
    });
    test('Thai UTF8', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      var thaiString = utf8.encode('ทดสอบ');
      client.pub('subject1', thaiString);
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payload, equals(thaiString));
    });
    test('pubString ascii', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      client.pubString('subject1', 'testtesttest');
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payloadString, equals('testtesttest'));
    });
    test('pubString Thai', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      client.pubString('subject1', 'ทดสอบ');
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payloadString, equals('ทดสอบ'));
    });
    test('delay connect', () async {
      var client = Client();
      var sub = client.sub('subject1');
      client.pubString('subject1', 'message1');
      client.connect('localhost');
      var msg = await sub.stream.first;
      client.close();
      expect(msg.payloadString, equals('message1'));
    });
    test('pub with no buffer ', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      await Future.delayed(Duration(seconds: 1));
      client.pubString('subject1', 'message1', buffer: false);
      var msg = await sub.stream.first;
      client.close();
      expect(msg.payloadString, equals('message1'));
    });
    test('multiple sub ', () async {
      var client = Client();
      client.connect('localhost');
      var sub1 = client.sub('subject1');
      var sub2 = client.sub('subject2');
      await Future.delayed(Duration(seconds: 1));
      client.pubString('subject1', 'message1');
      client.pubString('subject2', 'message2');
      var msg1 = await sub1.stream.first;
      var msg2 = await sub2.stream.first;
      client.close();
      expect(msg1.payloadString, equals('message1'));
      expect(msg2.payloadString, equals('message2'));
    });
    test('Wildcard sub * ', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1.*');
      client.pubString('subject1.1', 'message1');
      client.pubString('subject1.2', 'message2');
      var msgStream = sub.stream.asBroadcastStream();
      var msg1 = await msgStream.first;
      var msg2 = await msgStream.first;
      client.close();
      expect(msg1.payloadString, equals('message1'));
      expect(msg2.payloadString, equals('message2'));
    });
    test('Wildcard sub > ', () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1.>');
      client.pubString('subject1.a.1', 'message1');
      client.pubString('subject1.b.2', 'message2');
      var msgStream = sub.stream.asBroadcastStream();
      var msg1 = await msgStream.first;
      var msg2 = await msgStream.first;
      client.close();
      expect(msg1.payloadString, equals('message1'));
      expect(msg2.payloadString, equals('message2'));
    });
  });
}
