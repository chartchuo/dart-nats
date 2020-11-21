@Timeout(Duration(seconds: 30))
import 'package:test/test.dart';
import 'package:dart_nats_client/dart_nats_client.dart';
import 'dart:isolate';

//please start nats-server on localhost before testing

const iteration = 10000;
void run(SendPort sendPort) async {
  var client = Client();
  await client.connect('localhost');
  for (var i = 0; i < iteration; i++) {
    client.pubString('iso', i.toString());
    //commend out for reproduce issue#4
    await Future.delayed(Duration(milliseconds: 1));
  }
  await client.ping();
  client.close();
  sendPort.send('finish');
}

void main() {
  group('all', () {
    test('continuous', () async {
      var client = Client();
      await client.connect('localhost');
      var sub = client.sub('iso');
      var r = 0;

      sub.stream.listen((msg) {
        if (r % 1000 == 0) {
          print(msg.string);
        }
        r++;
      });

      var receivePort = ReceivePort();
      var iso = await Isolate.spawn(run, receivePort.sendPort);
      var out = await receivePort.first;
      print(out);
      iso.kill();
      //wait for last message send round trip to server
      await Future.delayed(Duration(seconds: 1));

      sub.close();
      client.close();

      expect(r, equals(iteration));
    });
  });
}
