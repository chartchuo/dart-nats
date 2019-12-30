import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

//please start nats-server on localhost before testing

void main() {
  group('all', () {
    test("simple", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      client.pub('subject1', 'message1'.codeUnits);
      var msg = await sub.stream.first;
      client.close();
      expect(msg.toString(), equals('message1'));
    });
    test("byte", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      var msgByte = [1, 2, 3, 129, 130];
      client.pub('subject1', msgByte);
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payload, equals(msgByte));
    });
    test("byte with return and  new line", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      var msgByte = [1, 2, 3, 13, 10, 129, 130];
      client.pub('subject1', msgByte);
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg.payload, equals(msgByte));
    });
    test("Thai UTF8", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      var thaiString = utf8.encode('ทดสอบ');
      client.pub('subject1', thaiString);
      var msg = await sub.stream.first;
      client.close();
      print(msg.payload);
      expect(msg, equals(thaiString));
    });
    test("delay connect", () async {
      var client = Client();
      var sub = client.sub('subject1');
      client.pub('subject1', 'message1'.codeUnits);
      client.connect('localhost');
      var msg = await sub.stream.first;
      client.close();
      expect(msg.toString(), equals('message1'));
    });
    test("pub with no buffer ", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      await Future.delayed(Duration(seconds: 1));
      client.pub('subject1', 'message1'.codeUnits, buffer: false);
      var msg = await sub.stream.first;
      client.close();
      expect(msg.toString(), equals('message1'));
    });
    test("multiple sub ", () async {
      var client = Client();
      client.connect('localhost');
      var sub1 = client.sub('subject1');
      var sub2 = client.sub('subject2');
      await Future.delayed(Duration(seconds: 1));
      client.pub('subject1', 'message1'.codeUnits);
      client.pub('subject2', 'message2'.codeUnits);
      var msg1 = await sub1.stream.first;
      var msg2 = await sub2.stream.first;
      client.close();
      expect(msg1.toString(), equals('message1'));
      expect(msg2.toString(), equals('message2'));
    });
    test("Wildcard sub * ", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1.*');
      client.pub('subject1.1', 'message1'.codeUnits);
      client.pub('subject1.2', 'message2'.codeUnits);
      var msgStream = sub.stream.asBroadcastStream();
      var msg1 = await msgStream.first;
      var msg2 = await msgStream.first;
      client.close();
      expect(msg1.toString(), equals('message1'));
      expect(msg2.toString(), equals('message2'));
    });
    test("Wildcard sub > ", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1.>');
      client.pub('subject1.a.1', 'message1'.codeUnits);
      client.pub('subject1.b.2', 'message2'.codeUnits);
      var msgStream = sub.stream.asBroadcastStream();
      var msg1 = await msgStream.first;
      var msg2 = await msgStream.first;
      client.close();
      expect(msg1.toString(), equals('message1'));
      expect(msg2.toString(), equals('message2'));
    });
  });
}
