@Timeout(Duration(seconds: 300))
import 'package:test/test.dart';
import 'package:dart_nats/dart_nats.dart';
import 'dart:isolate';

//please start nats-server on localhost before testing

const iteration = 100000;
void run(SendPort sendPort) async {
  var client = Client();
  await client.connect('localhost');
  for (var i = 0; i < iteration; i++) {
    client.pubString('iso', i.toString());
    await Future.delayed(Duration(milliseconds: 1));
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
      var sub = client.sub('iso');
      var r = 0;
      // var iteration = 100000;

      sub.stream.listen((msg) {
        if (r % 1000 == 0) {
          print(msg.string);
        }
        r++;
        if (r == 9490) {
          print(msg.string);
        }
      });

      var receivePort = ReceivePort();
      var iso = await Isolate.spawn(run, receivePort.sendPort);
      var out = await receivePort.first;
      print(out);
      iso.kill();
      //wait for last message send round trip to server
      await Future.delayed(Duration(seconds: 20));

      // receivePort = ReceivePort();
      // iso = await Isolate.spawn(run, receivePort.sendPort);
      // out = await receivePort.first;
      // print(out);
      // iso.kill();
      // await Future.delayed(Duration(seconds: 2));

      sub.close();
      client.close();

      expect(r, equals(iteration));
    });
  });
}
