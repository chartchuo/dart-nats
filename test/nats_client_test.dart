import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

//please start nats-server on localhost before testing

void main() {
  group('all', () {
    test('simple', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream!.first;
      client.close();
      expect(String.fromCharCodes(msg.data), equals('message1'));
    });
    test('newInbox', () {
      //just loop generate with out error
      var i = 0;
      for (i = 0; i < 10000; i++) {
        print(newInbox());
      }
      expect(i, 10000);
    });
    test('nuid not dup', () {
      var dup = false;
      var nuid1 = Nuid();
      var nuid2 = Nuid();
      for (var i = 0; i < 10000; i++) {
        var n1 = nuid1.next();
        var n2 = nuid2.next();
        if (n1 == n2) dup = true;
        print('$n1 $n2');
      }
      for (var i = 0; i < 10000; i++) {
        var nuid1 = Nuid();
        var nuid2 = Nuid();
        var n1 = nuid1.next();
        var n2 = nuid2.next();
        if (n1 == n2) dup = true;
        print('$n1 $n2');
      }
      expect(dup, false);
    });
    test('pub with Uint8List', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      var msgByte = Uint8List.fromList([1, 2, 3, 129, 130]);
      client.pub('subject1', msgByte);
      var msg = await sub.stream!.first;
      client.close();
      print(msg.data);
      expect(msg.data, equals(msgByte));
    });
    test('pub with Uint8List include return and  new line', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      var msgByte = Uint8List.fromList(
          [1, 10, 3, 13, 10, 13, 130, 1, 10, 3, 13, 10, 13, 130]);
      client.pub('subject1', msgByte);
      var msg = await sub.stream!.first;
      client.close();
      print(msg.data);
      expect(msg.data, equals(msgByte));
    });
    test('byte huge data', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      var msgByte = Uint8List.fromList(
          List<int>.generate(1024 + 1024 * 4, (i) => i % 256));
      client.pub('subject1', msgByte);
      var msg = await sub.stream!.first;
      client.close();
      print(msg.data);
      expect(msg.data, equals(msgByte));
    });
    test('UTF8', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      var thaiString = utf8.encode('ทดสอบ');
      client.pub('subject1', thaiString as Uint8List);
      var msg = await sub.stream!.first;
      client.close();
      print(msg.data);
      expect(msg.data, equals(thaiString));
    });
    test('pubString ascii', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      client.pubString('subject1', 'testtesttest');
      var msg = await sub.stream!.first;
      client.close();
      print(msg.data);
      expect(msg.string, equals('testtesttest'));
    });
    test('pubString Thai', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      client.pubString('subject1', 'ทดสอบ');
      var msg = await sub.stream!.first;
      client.close();
      print(msg.data);
      expect(msg.string, equals('ทดสอบ'));
    });
    test('delay connect', () async {
      var client = Client();
      var sub = client.sub('subject1');
      client.pubString('subject1', 'message1');
      await client.connect(Uri.parse('ws://localhost:80'));
      var msg = await sub.stream!.first;
      client.close();
      expect(msg.string, equals('message1'));
    });
    test('pub with no buffer ', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      await Future.delayed(Duration(seconds: 1));
      client.pubString('subject1', 'message1', buffer: false);
      var msg = await sub.stream!.first;
      client.close();
      expect(msg.string, equals('message1'));
    });
    test('multiple sub ', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub1 = client.sub('subject1');
      var sub2 = client.sub('subject2');
      await Future.delayed(Duration(seconds: 1));
      client.pubString('subject1', 'message1');
      client.pubString('subject2', 'message2');
      var msg1 = await sub1.stream!.first;
      var msg2 = await sub2.stream!.first;
      client.close();
      expect(msg1.string, equals('message1'));
      expect(msg2.string, equals('message2'));
    });
    test('Wildcard sub * ', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1.*');
      client.pubString('subject1.1', 'message1');
      client.pubString('subject1.2', 'message2');
      var msgStream = sub.stream!.asBroadcastStream();
      var msg1 = await msgStream.first;
      var msg2 = await msgStream.first;
      client.close();
      expect(msg1.string, equals('message1'));
      expect(msg2.string, equals('message2'));
    });
    test('Wildcard sub > ', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1.>');
      client.pubString('subject1.a.1', 'message1');
      client.pubString('subject1.b.2', 'message2');
      var msgStream = sub.stream!.asBroadcastStream();
      var msg1 = await msgStream.first;
      var msg2 = await msgStream.first;
      client.close();
      expect(msg1.string, equals('message1'));
      expect(msg2.string, equals('message2'));
    });
    test('unsub after connect', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      client.pubString('subject1', 'message1');
      var msg = await sub.stream!.first;
      client.unSub(sub);
      expect(msg.string, equals('message1'));

      sub = client.sub('subject1');
      client.pubString('subject1', 'message1');
      msg = await sub.stream!.first;
      sub.unSub();
      expect(msg.string, equals('message1'));

      client.close();
    });
    test('unsub before connect', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('subject1');
      client.unSub(sub);

      sub = client.sub('subject1');
      sub.unSub();
      client.close();
      expect(1, 1);
    });
    test('get max payload', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));

      //todo wait for connected
      await Future.delayed(Duration(seconds: 2));
      var max = client.maxPayload();
      client.close();

      expect(max, isNotNull);
    });
    test('sub continuous msg', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('sub');
      var r = 0;
      var iteration = 100;
      sub.stream!.listen((msg) {
        print(msg.string);
        r++;
      });
      for (var i = 0; i < iteration; i++) {
        client.pubString('sub', i.toString());
        // await Future.delayed(Duration(milliseconds: 10));
      }
      await Future.delayed(Duration(seconds: 1));
      client.close();
      expect(r, equals(iteration));
    });
    test('sub defect 13 binary', () async {
      var client = Client();
      await client.connect(Uri.parse('ws://localhost:80'));
      var sub = client.sub('sub');
      var r = 0;
      var iteration = 100;
      sub.stream!.listen((msg) {
        print(msg.string);
        r++;
      });
      for (var i = 0; i < iteration; i++) {
        client.pub('sub', Uint8List.fromList([10, 13, 10]));
        // await Future.delayed(Duration(milliseconds: 10));
      }
      await Future.delayed(Duration(seconds: 1));
      client.close();
      expect(r, equals(iteration));
    });
  });
}
