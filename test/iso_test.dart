import 'dart:isolate';

import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';

//please start nats-server on localhost before testing

void run(SendPort sendPort) async {
  var client = Client();
  await client.connect('localhost');
  for (var i = 0; i < 10000; i++) {
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
      var iteration = 10000;

      sub.stream.listen((msg) {
        print(msg.string);
        r++;
      });
      var receivePort = ReceivePort();
      var iso = await Isolate.spawn(run, receivePort.sendPort);

      // await Future.delayed(Duration(seconds: 10));
      var out = await receivePort.first;
      print(out);
      iso.kill();

      client.close();
      expect(r, equals(iteration));
    });
  });
}
