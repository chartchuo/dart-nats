import 'package:dart_nats/dart_nats.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
// larger MSG payloads not always working, check if full payload present in buffer #20
//  while (_receiveState == _ReceiveState.idle && _buffer.contains(13)) {

//     var n13 = _buffer.indexOf(13);
//     var msgFull = String.fromCharCodes(_buffer.take(n13)).toLowerCase().trim();
//     var msgList = msgFull.split(' ');
//     var msgType = msgList[0];
//     //print('... process $msgType ${_buffer.length}');

//     if (msgType == 'msg') {
//       var len = int.parse((msgList.length == 4 ? msgList[3] : msgList[4]));
//       if (len > 0 && _buffer.length < (msgFull.length + len + 4)) {
//         break; // not a full payload, go around again
//       }
//     }

//     _processOp();
//   }
void main() {
  group('all', () {
    test('0016 Connect to invalid ws connection does not give error', () async {
      var client = Client();
      var gotit = false;
      try {
        await client.connect(Uri.parse('ws://localhost:1234'));
        var fooSub = client.sub('foo');
        var barSub = client.sub('bar');
        // sleep(Duration(seconds: 20));
      } catch (e) {
        gotit = true;
      }
      await client.close();
      expect(gotit, equals(true));
    });
    test(
        '0020 larger MSG payloads not always working, check if full payload present in buffer',
        () async {
      var client = Client();
      unawaited(
          client.connect(Uri.parse('nats://localhost'), retryInterval: 1));
      var sub = client.sub('subject1');
      var str21k = '';
      for (var i = 0; i < 21000; i++) {
        str21k += '${i % 10}';
      }
      client.pubString('subject1', str21k);
      var msg = await sub.stream.first;
      await client.close();
      expect(msg.string, equals(str21k));
    });
  });
}
