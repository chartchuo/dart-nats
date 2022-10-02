import 'package:dart_nats/dart_nats.dart';

void main() async {
  var client = Client();
  await client.connect(Uri.parse('ws://localhost:80'));
  var sub = client.sub('subject1');
  client.pubString('subject1', 'message1');
  var data = await sub.stream.first;

  print(data.string);
  client.unSub(sub);
  await client.close();
}
