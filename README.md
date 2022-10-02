## TLS, Token, User/Pass, NKey, JWT support NOW.
##

# Dart-NATS 
A Dart client for the [NATS](https://nats.io) messaging system. Design to use with Dart and flutter.

### Flutter Web Support by WebSocket 
```dart
client.connect(Uri.parse('ws://localhost:80'));
```

### Flutter Other Platform Support by TCP Socket and WebSocket
```dart
client.connect(Uri.parse('nats://localhost'));
client.connect(Uri.parse('ws://localhost:80'));
```

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
  natsClient.connect(Uri.parse('ws://hostname');
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

## Authentication

Token Authtication 
```dart
var client = Client();
client.connect(Uri.parse('nats://localhost'),
          connectOption: ConnectOption(authToken: 'mytoken'));
```

User/Passwore Authentication
```dart
var client = Client();
client.connect(Uri.parse('nats://localhost'),
          connectOption: ConnectOption(user: 'foo', pass: 'bar'));
```

NKEY Authentication
```dart
var client = Client();
client.seed =
    'SUACSSL3UAHUDXKFSNVUZRF5UHPMWZ6BFDTJ7M6USDXIEDNPPQYYYCU3VY';
client.connect(
  Uri.parse('nats://localhost'),
  retryInterval: 1,
  connectOption: ConnectOption(
    nkey: 'UDXU4RCSJNZOIQHZNWXHXORDPRTGNJAHAHFRGZNEEJCPQTT2M7NLCNF4',
  ),
);
```

JWT Authentication
```dart
var client = Client();
client.seed =
    'SUAJGSBAKQHGYI7ZVKVR6WA7Z5U52URHKGGT6ZICUJXMG4LCTC2NTLQSF4';
client.connect(
  Uri.parse('nats://localhost'),
  retryInterval: 1,
  connectOption: ConnectOption(
    jwt:
        '''eyJ0eXAiOiJKV1QiLCJhbGciOiJlZDI1NTE5LW5rZXkifQ.eyJqdGkiOiJBU1pFQVNGMzdKS0dPTFZLTFdKT1hOM0xZUkpHNURJUFczUEpVT0s0WUlDNFFENlAyVFlRIiwiaWF0IjoxNjY0NTI0OTU5LCJpc3MiOiJBQUdTSkVXUlFTWFRDRkUzRVE3RzVPQldSVUhaVVlDSFdSM0dRVERGRldaSlM1Q1JLTUhOTjY3SyIsIm5hbWUiOiJzaWdudXAiLCJzdWIiOiJVQzZCUVY1Tlo1V0pQRUVZTTU0UkZBNU1VMk5NM0tON09WR01DU1VaV1dORUdZQVBNWEM0V0xZUCIsIm5hdHMiOnsicHViIjp7fSwic3ViIjp7fSwic3VicyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwidHlwZSI6InVzZXIiLCJ2ZXJzaW9uIjoyfX0.8Q0HiN0h2tBvgpF2cAaz2E3WLPReKEnSmUWT43NSlXFNRpsCWpmkikxGgFn86JskEN4yast1uSj306JdOhyJBA''',
  ),
);
```



Full Flutter sample code [example/flutter/main.dart](https://github.com/chartchuo/dart-nats/blob/master/example/flutter/main_dart)


## Features
The following is a list of features currently supported: 

- [x] - Publish
- [x] - Subscribe, unsubscribe
- [x] - NUID, Inbox
- [x] - Reconnect to single server when connection lost and resume subscription
- [x] - Unsubscribe after N message
- [x] - Request, Respond
- [x] - Queue subscribe
- [x] - Request timeout
- [x] - Events/status 
- [x] - Buffering message during reconnect atempts
- [x] - All authentication models, including NATS 2.0 JWT and nkey
- [x] - NATS 2.x 
- [x] - TLS 

Planned:
- [ ] - Connect to cluster
