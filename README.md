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

Step 1 declare object
```dart
  nats.Client natsClient;
  nats.Subscription fooSub, barSub;
```

Step 2 simply connect to server and subscribe to subject
```dart
  void connect() {
    natsClient = nats.Client();
    natsClient.connect('demo.nats.io');
    fooSub = natsClient.sub('foo');
    barSub = natsClient.sub('bar');
  }
```
Step 3 Use as Stream in StreamBuilder
```dart
          StreamBuilder(
            stream: fooSub.stream,
            builder: (context, AsyncSnapshot<nats.Message> snapshot) {
              return Text(snapshot.hasData ? '${snapshot.data}' : '');
            },
          ),
```
Step 4 dispose 
```dart
  void dispose() {
    natsClient.close();
    super.dispose();
  }
```


Full Flutter sample code `example/flutter/main.dart`:

```
dart example/flutter/main.dart
```

## Done
* Connect to NATS Server
* Basic sub and pub 
* Reconnect to single server when connection lost and resume subscription


## Todo
* Reply to 
* Connect to cluster 
* authentication