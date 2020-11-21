import 'package:dart_nats_client/dart_nats_client.dart';

void main() async {
  var client = Client();
  await client.connect('localhost');
  var sub = client.sub('subject1');
  client.pubString('subject1', 'message1');
  var data = await sub.stream.first;

  print(data.string);
  client.unSub(sub);
  client.close();
}
