import 'package:dart_nats/dart_nats.dart';

void main() async {
  var client = Client();
  client.connect('localhost');
  var sub = client.sub('subject1');
  await Future.delayed(Duration(seconds: 1));
  client.pub('subject1', 'message1'.codeUnits);
  var msg = await sub.stream.first;

  print(msg);
  client.unSub(sub);
  client.close();
}
