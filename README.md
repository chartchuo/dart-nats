# Dart-NATS 
A Dart client for the [NATS](https://nats.io) messaging system. It's simple. Design to use with flutter easy to write no need to deal with complex asynchronous.

## Dart Examples:

Run the `example/main.dart`:

```
dart example/main.dart
```

```dart
import 'package:dart_nats/dart_nats.dart';

void main() async {
  var client = Client();
  client.connect('localhost');
  var sub = client.sub('subject1');
  await Future.delayed(Duration(seconds: 1));
  client.pub('subject1', 'message1');
  var msg = await sub.stream.first;

  print(msg);
  client.unSub(sub);
  client.close();
}
```

## Flutter Examples:

Run the `example/flutter/main.dart`:

```
dart example/flutter/main.dart
```

```dart
import 'package:flutter/material.dart';
import 'package:hello_world/nats_client.dart' as nats;

class MyHomePage extends StatefulWidget {
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  TextEditingController _controller = TextEditingController();
  nats.Client natsClient;
  nats.Subscription fooSub, barSub;

  @override
  void initState() {
    super.initState();
    connect();
  }

  void connect() {
    natsClient = nats.Client();
    natsClient.connect('demo.nats.io');
    fooSub = natsClient.sub('foo');
    barSub = natsClient.sub('bar');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Form(
              child: TextFormField(
                controller: _controller,
                decoration: InputDecoration(labelText: 'publish'),
              ),
            ),
            Text('foo message:'),
            StreamBuilder(
              stream: fooSub.stream,
              builder: (context, AsyncSnapshot<nats.Message> snapshot) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(snapshot.hasData ? '${snapshot.data}' : ''),
                );
              },
            ),
            Text('bar message:'),
            StreamBuilder(
              stream: barSub.stream,
              builder: (context, AsyncSnapshot<nats.Message> snapshot) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(snapshot.hasData ? '${snapshot.data}' : ''),
                );
              },
            ),
            Row(
              children: <Widget>[
                RaisedButton(
                  child: Text('pub to foo'),
                  onPressed: () => _sendMessage('foo'),
                ),
                RaisedButton(
                  child: Text('pub to bar'),
                  onPressed: () => _sendMessage('bar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage(String subject) {
    if (_controller.text.isNotEmpty) {
      natsClient.pub(subject, _controller.text);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
```

## Done
* Connect to NATS Server
* Basic sub and pub 
* Reconnect to single server when connection lost and resume subscription


## Todo
* Reply to 
* Connect to cluster 