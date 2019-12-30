import 'package:dart_nats/dart_nats.dart';

void main() async {
  var client = Client();
  client.connect('localhost');
  var sub = client.sub('subject1');
  client.pubString('subject1', 'message1');
  var msg = await sub.stream.first;

  print(msg.payloadString);
  client.unSub(sub);
  client.close();
}
