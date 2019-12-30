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
  client.pubString('subject1', 'message1');
  var msg = await sub.stream.first;

  print(msg.payloadString);
  client.unSub(sub);
  client.close();
}
```

## Flutter Examples:

Import and Declare object
```dart
import 'package:dart_nats/dart_nats.dart' as nats;

  nats.Client natsClient;
  nats.Subscription fooSub, barSub;
```

Simply connect to server and subscribe to subject
```dart
  void connect() {
    natsClient = nats.Client();
    natsClient.connect('demo.nats.io');
    fooSub = natsClient.sub('foo');
    barSub = natsClient.sub('bar');
  }
```
Use as Stream in StreamBuilder
```dart
          StreamBuilder(
            stream: fooSub.stream,
            builder: (context, AsyncSnapshot<nats.Message> snapshot) {
              return Text(snapshot.hasData ? '${snapshot.data.payloadString}' : '');
            },
          ),
```

Publish Message
```dart
      natsClient.pubString(subject, _controller.text);
```

Dispose 
```dart
  void dispose() {
    natsClient.close();
    super.dispose();
  }
```

Full Flutter sample code [example/flutter/main.dart](https://github.com/chartchuo/dart-nats/blob/master/example/flutter/main_dart)

## Done
* Connect to NATS Server
* Basic sub and pub 
* Reconnect to single server when connection lost and resume subscription


## Todo
* Reply to 
* Connect to cluster 
* authentication