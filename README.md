# Dart-NATS 
A Dart client for the [NATS](https://nats.io) messaging system. Design to use with Dart and flutter.

### Flutter Web Support by WebSocket 
```dart
client.connect(Uri.parse('ws://localhost:80'));
```

### Flutter Other Platform Support by TCP Socket and WebSocket
```dart
client.tcpConnect('localhost');
client.connect(Uri.parse('ws://localhost:80'));
```

## API Change
To support Flutter Web. We change transport from socket to WebSocket and also change API call 

## Dart Examples:

Run the `example/main.dart`:

```
dart example/main.dart
```

```dart
import 'package:dart_nats/dart_nats.dart';

void main() async {
  var client = Client();
  client.connect(Uri.parse('ws://localhost:80'));
  var sub = client.sub('subject1');
  client.pubString('subject1', 'message1');
  var msg = await sub.stream.first;

  print(msg.string);
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
    natsClient.connect(Uri.parse('wss://demo.nats.io:443');
    fooSub = natsClient.sub('foo');
    barSub = natsClient.sub('bar');
  }
```
Use as Stream in StreamBuilder
```dart
          StreamBuilder(
            stream: fooSub.stream,
            builder: (context, AsyncSnapshot<nats.Message> snapshot) {
              return Text(snapshot.hasData ? '${snapshot.data.string}' : '');
            },
          ),
```

Publish Message
```dart
      natsClient.pubString('subject','message string');
```

Dispose 
```dart
  void dispose() {
    natsClient.close();
    super.dispose();
  }
```

Full Flutter sample code [example/flutter/main.dart](https://github.com/chartchuo/dart-nats/blob/master/example/flutter/main_dart)


## Features
The following is a list of features currently supported and planned by this client:

* [x] - Publish
* [x] - Subscribe, unsubscribe
* [x] - NUID, Inbox
* [x] - Reconnect to single server when connection lost and resume subscription
* [x] - Unsubscribe after N message
* [x] - Request, Respond
* [x] - Queue subscribe
* [ ] - caches, flush, drain
* [x] - Request timeout
* [ ] - structured data
* [ ] - Connection option (cluster, timeout,ping interval, max ping, echo,... )
* [ ] - Random automatic reconnection, disable reconnect, number of attempts, pausing
* [ ] - Connect to cluster,randomize, Automatic reconnect upon connection failure base server info
* [x] - Events/status 
* [ ] - disconnect handler, reconnect handler
* [x] - Buffering message during reconnect atempts
* [ ] - All authentication models, including NATS 2.0 JWT and seed keys
* [ ] - NATS 2.2 
