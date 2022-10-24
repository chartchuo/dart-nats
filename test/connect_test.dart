import 'dart:async';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('all', () {
    test('ws', () async {
      var client = Client();
      unawaited(
          client.connect(Uri.parse('ws://localhost:8080'), retryInterval: 1));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('nats:', () async {
      var client = Client();
      unawaited(
          client.connect(Uri.parse('nats://localhost:4222'), retryInterval: 1));
      var sub = client.sub('subject1');
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('await', () async {
      var client = Client();
      await client.connect(Uri.parse('nats://localhost'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('retry false', () async {
      var client = Client();
      await client.connect(Uri.parse('nats://localhost'), retry: false);
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));
    });
    test('reconnect', () async {
      var client = Client();
      await client.connect(Uri.parse('nats://localhost'));
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      await client.close();
      expect(String.fromCharCodes(msg.byte), equals('message1'));

      await client.connect(Uri.parse('nats://localhost'));
      result = client.pub('subject1', Uint8List.fromList('message2'.codeUnits),
          buffer: false);
      expect(result, true);
      msg = await sub.stream.first;
      expect(String.fromCharCodes(msg.byte), equals('message2'));
    });
    test('retry background', () async {
      var client = Client();
      unawaited(client.connect(
        Uri.parse('nats://localhost'),
        retry: true,
        retryCount: -1,
        timeout: 2,
        retryInterval: 2,
      ));

      await client.waitUntilConnected();
      var sub = client.sub('subject1');
      var result = client.pub(
          'subject1', Uint8List.fromList('message1'.codeUnits),
          buffer: false);
      expect(result, true);

      var msg = await sub.stream.first;
      expect(String.fromCharCodes(msg.byte), equals('message1'));

      await client.tcpClose();
      await client.waitUntilConnected();

      result = client.pub('subject1', Uint8List.fromList('message2'.codeUnits),
          buffer: false);
      expect(result, true);
      msg = await sub.stream.first;
      expect(String.fromCharCodes(msg.byte), equals('message2'));
    });
    test('status stream', () async {
      var client = Client();
      var statusHistory = <Status>[];
      client.statusStream.listen((s) {
        // print(s);
        statusHistory.add(s);
      });
      await client.connect(Uri.parse('ws://localhost:8080'));
      await client.close();

      // no runtime error should be fine
      // expect only first and last status
      expect(statusHistory.first, equals(Status.connecting));
      expect(statusHistory.last, equals(Status.closed));
    });
    test('status stream detail', () async {
      var client = Client();
      var statusHistory = <Status>[];
      client.statusStream.listen((s) {
        // print(s);
        statusHistory.add(s);
      });
      await client.connect(
        Uri.parse('ws://localhost:8080'),
        retry: true,
        retryCount: 3,
        retryInterval: 1,
      );
      await client.close();

      // no runtime error should be fine
      // expect only first and last status
      expect(statusHistory.length, equals(4));
      expect(statusHistory[0], equals(Status.connecting));
      expect(statusHistory[1], equals(Status.infoHandshake));
      expect(statusHistory[2], equals(Status.connected));
      expect(statusHistory[3], equals(Status.closed));
    });
    test('status stream retry fail', () async {
      var client = Client();
      var statusHistory = <Status>[];
      try {
        client.statusStream.listen((s) {
          print(s);
          statusHistory.add(s);
        });
        await client.connect(
          Uri.parse('nats://localhost:1234'),
          retry: true,
          retryCount: 3,
          retryInterval: 1,
        );
        print('after connect');
      } on NatsException {
        //
      } on WebSocketChannelException {
        //
      } catch (e) {
        //
      }
      await client.close();

      // no runtime error should be fine
      // expect only first and last status
      expect(statusHistory.length, equals(4));
      expect(statusHistory[0], equals(Status.connecting));
      expect(statusHistory[1], equals(Status.reconnecting));
      expect(statusHistory[2], equals(Status.reconnecting));
      expect(statusHistory[3], equals(Status.closed));
    });
  });
}
