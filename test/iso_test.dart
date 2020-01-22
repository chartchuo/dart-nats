import 'dart:isolate';

import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

//please start nats-server on localhost before testing

void run(SendPort sendPort) async {
  var client = Client();
  await client.connect('localhost');
  for (var i = 0; i < 100000; i++) {
    client.pubString('sub', i.toString());
  }
  await client.ping();
  client.close();
  sendPort.send('finish');
}

void main() {
  group('all', () {
    test('isolation', () async {
      var client = Client();
      await client.connect('localhost');
      var sub = client.sub('sub');
      var r = 0;
      var iteration = 100000;

      sub.stream.listen((msg) {
        print(msg.string);
        r++;
      });
      var receivePort = ReceivePort();
      var iso = await Isolate.spawn(run, receivePort.sendPort);

      var out = await receivePort.first;
      print(out);
      iso.kill();

      await Future.delayed(Duration(
          seconds: 1)); //wait for last message send round trip to server
      client.close();
      expect(r, equals(iteration));
    });
  });
}
