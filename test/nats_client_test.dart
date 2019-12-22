import 'package:test/test.dart';
import 'package:dart_nats/dart-nats.dart';

//please start nats-server on localhost before testing

void main() {
  test("connect to localhost ", () async {
    var client = Client();
    client.connect('localhost');
    var sub = client.sub('subject1');
    await Future.delayed(Duration(seconds: 1));
    client.pub('subject1', 'message1');
    var msg = await sub.stream.first;
    client.close();
    expect(msg.toString(), equals('message1'));
  });
}
