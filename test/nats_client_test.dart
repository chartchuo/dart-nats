import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

//please start nats-server on localhost before testing

void main() {
  group('all', () {
    test("default", () async {
      var client = Client();
      client.connect('localhost');
      var sub = client.sub('subject1');
      client.pub('subject1', 'message1');
      var msg = await sub.stream.first;
      client.close();
      expect(msg.toString(), equals('message1'));
    });
    test("delay connect", () async {
      var client = Client();
      var sub = client.sub('subject1');
      client.pub('subject1', 'message1');
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
      client.pub('subject1', 'message1', buffer: false);
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
      client.pub('subject1', 'message1');
      client.pub('subject2', 'message2');
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
      client.pub('subject1.1', 'message1');
      client.pub('subject1.2', 'message2');
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
      client.pub('subject1.a.1', 'message1');
      client.pub('subject1.b.2', 'message2');
      var msgStream = sub.stream.asBroadcastStream();
      var msg1 = await msgStream.first;
      var msg2 = await msgStream.first;
      client.close();
      expect(msg1.toString(), equals('message1'));
      expect(msg2.toString(), equals('message2'));
    });
  });
}
