import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mutex/mutex.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'common.dart';
import 'inbox.dart';
import 'message.dart';
import 'nkeys.dart';
import 'subscription.dart';
import 'jetstream.dart';

enum _ReceiveState {
  idle,
  msg,
}

enum _ClientStatus {
  init,
  used,
  closed,
}

/// NATS connection status
enum Status {
  /// Disconnected state
  disconnected,

  /// Performing TLS handshake
  tlsHandshake,

  /// Connected, awaiting initial info handshake
  infoHandshake,

  /// Fully connected and ready to process messages
  connected,

  /// Connection has been closed
  closed,

  /// Reconnecting to the server
  reconnecting,

  /// Connecting by connect() method
  connecting,
}

class _Pub {
  final String? subject;
  final List<int> data;
  final String? replyTo;

  _Pub(this.subject, this.data, this.replyTo);
}

/// NATS client implementation
class Client {
  final _ackStream = StreamController<bool>.broadcast();
  _ClientStatus _clientStatus = _ClientStatus.init;
  WebSocketChannel? _wsChannel;
  Socket? _tcpSocket;
  SecureSocket? _secureSocket;
  bool _tlsRequired = false;
  bool _retry = false;

  Info _info = Info();
  final _pingCompleters = <Completer<void>>[];
  late Completer<void> _connectCompleter;

  List<Uri> _serverPool = [];
  int _currentServerIndex = 0;

  /// Connection event callbacks
  void Function()? onConnect;
  void Function()? onDisconnect;
  void Function(dynamic error)? onError;
  void Function()? onReconnect;
  void Function()? onClose;

  /// User authentication callbacks
  String Function()? userJwtHandler;
  Uint8List Function(Uint8List nonce)? signatureHandler;

  /// Error handler for websocket errors
  Function(dynamic) wsErrorHandler = (e) {
    throw NatsException('listen ws error: $e');
  };

  var _status = Status.disconnected;

  /// Check if client is fully connected
  bool get connected => _status == Status.connected;

  final _statusController = StreamController<Status>.broadcast();
  var _channelStream = StreamController<dynamic>();

  /// Get current connection status of client
  Status get status => _status;

  /// Accept self-signed or invalid certificate. Not recommended for production.
  bool acceptBadCert = false;

  /// Stream of status updates
  Stream<Status> get statusStream => _statusController.stream;

  var _connectOption = ConnectOption();

  /// Security context used for secure socket setup
  SecurityContext? securityContext;

  Nkeys? _nkeys;

  /// Get NKEY seed
  String? get seed => _nkeys?.seed;

  /// Set NKEY seed
  set seed(String? newseed) {
    if (newseed == null) {
      _nkeys = null;
      return;
    }
    _nkeys = Nkeys.fromSeed(newseed);
  }

  final _jsonDecoder = <Type, dynamic Function(String)>{};

  /// Register a JSON decoder for a generic type <T>
  void registerJsonDecoder<T>(T Function(String) f) {
    if (T == dynamic) {
      throw NatsException('can not register dynamic type');
    }
    _jsonDecoder[T] = f;
  }

  /// Get latest server info
  Info? get info => _info;

  final _subs = <int, Subscription>{};
  final _backendSubs = <int, bool>{};
  final _pubBuffer = <_Pub>[];

  int _ssid = 0;

  List<int> _buffer = [];
  _ReceiveState _receiveState = _ReceiveState.idle;
  String _receiveLine1 = '';

  /// Create a new NATS Client
  Client() {
    _streamHandle();
  }

  Future<void> _sign() async {
    if (userJwtHandler != null) {
      _connectOption.jwt = userJwtHandler!();
    }
    if (_info.nonce != null) {
      if (signatureHandler != null) {
        final sig = signatureHandler!(Uint8List.fromList(utf8.encode(_info.nonce!)));
        _connectOption.sig = base64.encode(sig);
      } else if (_nkeys != null) {
        final sig = _nkeys?.sign(utf8.encode(_info.nonce!));
        _connectOption.sig = base64.encode(sig!);
      }
    }
  }

  void _streamHandle() {
    _channelStream.stream.listen((dynamic d) {
      if (d is List<int>) {
        _buffer.addAll(d);
      } else if (d is String) {
        _buffer.addAll(utf8.encode(d));
      }

      while (_receiveState == _ReceiveState.idle && _buffer.contains(13)) {
        final n13 = _buffer.indexOf(13);
        final msgFull =
            String.fromCharCodes(_buffer.take(n13)).toLowerCase().trim();
        final msgList = msgFull.split(' ');
        final msgType = msgList[0];

        if (msgType == 'msg' || msgType == 'hmsg') {
          final len = int.parse(msgList.last);
          if (len > 0 && _buffer.length < (msgFull.length + len + 4)) {
            break;
          }
        }

        _processOp();
      }
    });
  }

  Uri _getNextServer() {
    if (_serverPool.isEmpty) {
      throw NatsException('Server pool is empty');
    }
    final server = _serverPool[_currentServerIndex];
    _currentServerIndex = (_currentServerIndex + 1) % _serverPool.length;
    return server;
  }

  /// Connect to the NATS server using NATS URI schema
  Future<void> connect(
    Uri uri, {
    List<Uri>? servers,
    ConnectOption? connectOption,
    int timeout = 5,
    bool retry = true,
    int retryInterval = 10,
    int retryCount = 3,
    SecurityContext? securityContext,
  }) async {
    _retry = retry;
    this.securityContext = securityContext;
    _connectCompleter = Completer<void>();
    _serverPool = [uri];
    if (servers != null) {
      _serverPool.addAll(servers);
    }
    _currentServerIndex = 0;

    if (_clientStatus == _ClientStatus.used) {
      throw Exception(
          NatsException('client in use. must close before call connect'));
    }
    if (status != Status.disconnected && status != Status.closed) {
      return Future.error('Error: status not disconnected and not closed');
    }

    _clientStatus = _ClientStatus.used;
    if (connectOption != null) {
      _connectOption = connectOption;
    }

    do {
      _connectLoop(
        timeout: timeout,
        retryInterval: retryInterval,
        retryCount: retryCount,
      );

      if (_clientStatus == _ClientStatus.closed || status == Status.closed) {
        if (!_connectCompleter.isCompleted) {
          _connectCompleter.complete();
        }
        await close();
        _clientStatus = _ClientStatus.closed;
        return;
      }

      if (!_retry || retryCount != -1) {
        return _connectCompleter.future;
      }

      await for (final s in statusStream) {
        if (s == Status.disconnected) {
          break;
        }
        if (s == Status.closed) {
          return;
        }
      }
    } while (_retry && retryCount == -1);

    return _connectCompleter.future;
  }

  void _connectLoop({
    int timeout = 5,
    required int retryInterval,
    required int retryCount,
  }) async {
    int attempts = 0;
    final maxAttempts = _retry ? (retryCount == -1 ? -1 : retryCount * _serverPool.length) : _serverPool.length;

    while (attempts < maxAttempts || maxAttempts == -1) {
      if (attempts == 0) {
        _setStatus(Status.connecting);
      } else {
        _setStatus(Status.reconnecting);
      }

      final currentUri = _getNextServer();
      try {
        if (_channelStream.isClosed) {
          _channelStream = StreamController<dynamic>();
        }
        final success = await _connectUri(currentUri, timeout: timeout);
        if (!success) {
          attempts++;
          if (_retry || attempts < _serverPool.length) {
            final delay = _retry ? retryInterval : 1;
            await Future<void>.delayed(Duration(seconds: delay));
            continue;
          }
          break;
        }

        _buffer = [];
        return;
      } catch (err) {
        await close();
        if (onError != null) {
          onError!(err);
        }
        attempts++;
        if (_retry || attempts < _serverPool.length) {
          final delay = _retry ? retryInterval : 1;
          await Future<void>.delayed(Duration(seconds: delay));
        } else {
          if (!_connectCompleter.isCompleted) {
            _connectCompleter.completeError(err);
          }
          _setStatus(Status.disconnected);
          break;
        }
      }
    }

    if (!_connectCompleter.isCompleted) {
      _clientStatus = _ClientStatus.closed;
      _connectCompleter
          .completeError(NatsException('can not connect to any servers in the pool'));
    }
  }

  Future<bool> _connectUri(Uri uri, {int timeout = 5}) async {
    try {
      if (uri.scheme == '') {
        throw Exception(NatsException('No scheme in uri'));
      }

      switch (uri.scheme) {
        case 'wss':
        case 'ws':
          try {
            _wsChannel = WebSocketChannel.connect(uri);
          } catch (e) {
            return false;
          }
          if (_wsChannel == null) {
            return false;
          }
          _setStatus(Status.infoHandshake);
          _wsChannel?.stream.listen((dynamic event) {
            if (_channelStream.isClosed) return;
            _channelStream.add(event);
          }, onDone: () {
            _setStatus(Status.disconnected);
          }, onError: (dynamic e) {
            if (onError != null) {
              onError!(e);
            }
            close();
            wsErrorHandler(e);
          });
          return true;

        case 'nats':
          var port = uri.port;
          if (port == 0) {
            port = 4222;
          }
          _tcpSocket = await Socket.connect(
            uri.host,
            port,
            timeout: Duration(seconds: timeout),
          );
          if (_tcpSocket == null) {
            return false;
          }
          _setStatus(Status.infoHandshake);
          _tcpSocket!.listen((event) {
            if (_secureSocket == null) {
              if (_channelStream.isClosed) return;
              _channelStream.add(event);
            }
          }, onError: (dynamic e) {
            if (onError != null) {
              onError!(e);
            }
          }).onDone(() {
            _setStatus(Status.disconnected);
          });
          return true;

        case 'tls':
          _tlsRequired = true;
          var port = uri.port;
          if (port == 0) {
            port = 4443;
          }
          _tcpSocket = await Socket.connect(
            uri.host,
            port,
            timeout: Duration(seconds: timeout),
          );
          if (_tcpSocket == null) return false;
          _setStatus(Status.infoHandshake);
          _tcpSocket!.listen((event) {
            if (_secureSocket == null) {
              if (_channelStream.isClosed) return;
              _channelStream.add(event);
            }
          }, onError: (dynamic e) {
            if (onError != null) {
              onError!(e);
            }
          });
          return true;

        default:
          throw Exception(NatsException('schema ${uri.scheme} not support'));
      }
    } catch (e) {
      if (onError != null) {
        onError!(e);
      }
      return false;
    }
  }

  void _backendSubscriptAll() {
    _backendSubs.clear();
    _subs.forEach((sid, s) {
      _sub(s.subject, sid, queueGroup: s.queueGroup);
      _backendSubs[sid] = true;
    });
  }

  void _flushPubBuffer() {
    for (final p in _pubBuffer) {
      _pub(p);
    }
  }

  void _processOp() async {
    final nextLineIndex = _buffer.indexWhere((c) => c == 13);
    if (nextLineIndex == -1) return;

    final line = String.fromCharCodes(_buffer.sublist(0, nextLineIndex));
    if (_buffer.length > nextLineIndex + 2) {
      _buffer.removeRange(0, nextLineIndex + 2);
    } else {
      _buffer = [];
    }

    final splitIndex = line.indexOf(' ');
    String op, data;
    if (splitIndex != -1) {
      op = line.substring(0, splitIndex).trim().toLowerCase();
      data = line.substring(splitIndex).trim();
    } else {
      op = line.trim().toLowerCase();
      data = '';
    }

    switch (op) {
      case 'msg':
        _receiveState = _ReceiveState.msg;
        _receiveLine1 = line;
        _processMsg();
        _receiveLine1 = '';
        _receiveState = _ReceiveState.idle;
        break;

      case 'hmsg':
        _receiveState = _ReceiveState.msg;
        _receiveLine1 = line;
        _processHMsg();
        _receiveLine1 = '';
        _receiveState = _ReceiveState.idle;
        break;

      case 'info':
        _info = Info.fromJson(jsonDecode(data) as Map<String, dynamic>);
        if (_tlsRequired && !(_info.tlsRequired ?? false)) {
          throw Exception(NatsException('require TLS but server not required'));
        }

        if ((_info.tlsRequired ?? false) && _tcpSocket != null) {
          _setStatus(Status.tlsHandshake);
          try {
            final secureSocket = await SecureSocket.secure(
              _tcpSocket!,
              context: securityContext,
              onBadCertificate: (certificate) {
                return acceptBadCert;
              },
            );

            _secureSocket = secureSocket;
            secureSocket.listen((event) {
              if (_channelStream.isClosed) return;
              _channelStream.add(event);
            }, onError: (dynamic error) {
              print('Socket error: $error');
              _setStatus(Status.disconnected);
              if (onError != null) {
                onError!(error);
              }

              if (error is TlsException) {
                _retry = false;
                close();
                throw Exception(NatsException(error.message));
              }
            });
          } catch (e) {
            _setStatus(Status.disconnected);
            rethrow;
          }
        }

        await _sign();
        _addConnectOption(_connectOption);

        if (_connectOption.verbose == true) {
          final ack = await _ackStream.stream.first;
          if (ack) {
            _setStatus(Status.connected);
          } else {
            _setStatus(Status.disconnected);
          }
        } else {
          _setStatus(Status.connected);
        }

        _backendSubscriptAll();
        _flushPubBuffer();

        if (!_connectCompleter.isCompleted) {
          _connectCompleter.complete();
        }
        break;

      case 'ping':
        if (status == Status.connected) {
          _add('pong');
        }
        break;

      case '-err':
        if (_connectOption.verbose == true) {
          _ackStream.sink.add(false);
        }
        break;

      case 'pong':
        if (_pingCompleters.isNotEmpty) {
          final completer = _pingCompleters.removeAt(0);
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
        break;

      case '+ok':
        if (_connectOption.verbose == true) {
          _ackStream.sink.add(true);
        }
        break;
    }
  }

  void _processMsg() {
    final s = _receiveLine1.split(' ');
    final subject = s[1];
    final sid = int.parse(s[2]);
    String? replyTo;
    int length;

    if (s.length == 4) {
      length = int.parse(s[3]);
    } else {
      replyTo = s[3];
      length = int.parse(s[4]);
    }

    if (_buffer.length < length) return;
    final payload = Uint8List.fromList(_buffer.sublist(0, length));

    if (_buffer.length > length + 2) {
      _buffer.removeRange(0, length + 2);
    } else {
      _buffer = [];
    }

    if (_subs[sid] != null) {
      _subs[sid]?.add(Message<dynamic>(
        subject,
        sid,
        payload,
        this,
        replyTo: replyTo,
      ));
    }
  }

  void _processHMsg() {
    final s = _receiveLine1.split(' ');
    final subject = s[1];
    final sid = int.parse(s[2]);
    String? replyTo;
    int length;
    int headerLength;

    if (s.length == 5) {
      headerLength = int.parse(s[3]);
      length = int.parse(s[4]);
    } else {
      replyTo = s[3];
      headerLength = int.parse(s[4]);
      length = int.parse(s[5]);
    }

    if (_buffer.length < length) return;
    final header = Uint8List.fromList(_buffer.sublist(0, headerLength));
    final payload = Uint8List.fromList(_buffer.sublist(headerLength, length));

    if (_buffer.length > length + 2) {
      _buffer.removeRange(0, length + 2);
    } else {
      _buffer = [];
    }

    if (_subs[sid] != null) {
      final msg = Message<dynamic>(
        subject,
        sid,
        payload,
        this,
        replyTo: replyTo,
        header: Header.fromBytes(header),
      );
      _subs[sid]?.add(msg);
    }
  }

  /// Get server maximum payload size configuration
  int? maxPayload() => _info.maxPayload;

  /// Send PING request and wait for PONG
  Future<void> ping() {
    final completer = Completer<void>();
    _pingCompleters.add(completer);
    _add('ping');
    return completer.future;
  }

  void _addConnectOption(ConnectOption c) {
    _add('connect ' + jsonEncode(c.toJson()));
  }

  /// Default buffer action for pub
  var defaultPubBuffer = true;

  /// Publish a byte payload (Uint8List) to a subject.
  /// Returns true if successfully sent/buffered.
  Future<bool> pub(
    String? subject,
    Uint8List data, {
    String? replyTo,
    bool? buffer,
    Header? header,
  }) async {
    buffer ??= defaultPubBuffer;
    if (status != Status.connected) {
      if (buffer) {
        _pubBuffer.add(_Pub(subject, data, replyTo));
        return true;
      } else {
        return false;
      }
    }

    String cmd;
    final headerByte = header?.toBytes();
    if (header == null) {
      cmd = 'pub';
    } else {
      cmd = 'hpub';
    }
    cmd += ' $subject';
    if (replyTo != null) {
      cmd += ' $replyTo';
    }

    if (headerByte != null) {
      cmd += ' ${headerByte.length}  ${headerByte.length + data.length}';
      _add(cmd);
      final dataWithHeader = headerByte.toList();
      dataWithHeader.addAll(data.toList());
      _addByte(dataWithHeader);
    } else {
      cmd += ' ${data.length}';
      _add(cmd);
      _addByte(data);
    }

    if (_connectOption.verbose == true) {
      final ack = await _ackStream.stream.first;
      return ack;
    }
    return true;
  }

  /// Publish a string payload to a subject
  Future<bool> pubString(
    String subject,
    String str, {
    String? replyTo,
    bool buffer = true,
    Header? header,
  }) async {
    return pub(
      subject,
      Uint8List.fromList(utf8.encode(str)),
      replyTo: replyTo,
      buffer: buffer,
      header: header,
    );
  }

  Future<bool> _pub(_Pub p) async {
    if (p.replyTo == null) {
      _add('pub ${p.subject} ${p.data.length}');
    } else {
      _add('pub ${p.subject} ${p.replyTo} ${p.data.length}');
    }
    _addByte(p.data);

    if (_connectOption.verbose == true) {
      final ack = await _ackStream.stream.first;
      return ack;
    }
    return true;
  }

  T Function(String) _getJsonDecoder<T>() {
    final c = _jsonDecoder[T];
    if (c == null) {
      throw NatsException('no decoder for type $T');
    }
    return c as T Function(String);
  }

  /// Subscribe to a subject (with optional queue group and json decoder)
  Subscription<T> sub<T>(
    String subject, {
    String? queueGroup,
    T Function(String)? jsonDecoder,
  }) {
    _ssid++;

    if (T != dynamic && jsonDecoder == null) {
      jsonDecoder = _getJsonDecoder<T>();
    }

    final s = Subscription<T>(
      _ssid,
      subject,
      this,
      queueGroup: queueGroup,
      jsonDecoder: jsonDecoder,
    );
    _subs[_ssid] = s;

    if (status == Status.connected) {
      _sub(subject, _ssid, queueGroup: queueGroup);
      _backendSubs[_ssid] = true;
    }
    return s;
  }

  void _sub(String? subject, int sid, {String? queueGroup}) {
    if (queueGroup == null) {
      _add('sub $subject $sid');
    } else {
      _add('sub $subject $queueGroup $sid');
    }
  }

  /// Unsubscribe from a subscription
  bool unSub(Subscription<dynamic> s) {
    final sid = s.sid;

    if (_subs[sid] == null) return false;
    _unSub(sid);
    _subs.remove(sid);
    s.close();
    _backendSubs.remove(sid);
    return true;
  }

  /// Unsubscribe from a subscription using its subscriber ID
  bool unSubById(int sid) {
    if (_subs[sid] == null) return false;
    return unSub(_subs[sid]!);
  }

  void _unSub(int sid, {String? maxMsgs}) {
    if (maxMsgs == null) {
      _add('unsub $sid');
    } else {
      _add('unsub $sid $maxMsgs');
    }
  }

  void _add(String str) {
    if (status == Status.closed || status == Status.disconnected) {
      return;
    }
    if (_wsChannel != null) {
      _wsChannel?.sink.add(utf8.encode(str + '\r\n'));
      return;
    } else if (_secureSocket != null) {
      _secureSocket!.add(utf8.encode(str + '\r\n'));
      return;
    } else if (_tcpSocket != null) {
      _tcpSocket!.add(utf8.encode(str + '\r\n'));
      return;
    }
    throw Exception(NatsException('no connection'));
  }

  void _addByte(List<int> msg) {
    if (_wsChannel != null) {
      _wsChannel?.sink.add(msg);
      _wsChannel?.sink.add(utf8.encode('\r\n'));
      return;
    } else if (_secureSocket != null) {
      _secureSocket?.add(msg);
      _secureSocket?.add(utf8.encode('\r\n'));
      return;
    } else if (_tcpSocket != null) {
      _tcpSocket?.add(msg);
      _tcpSocket?.add(utf8.encode('\r\n'));
      return;
    }
    throw Exception(NatsException('no connection'));
  }

  var _inboxPrefix = '_INBOX';

  /// Get Inbox prefix configuration
  String get inboxPrefix => _inboxPrefix;

  /// Set Inbox prefix configuration
  set inboxPrefix(String i) {
    if (_clientStatus == _ClientStatus.used) {
      throw NatsException('inbox prefix can not change when connection in use');
    }
    _inboxPrefix = i;
    _inboxSubPrefix = null;
  }

  final _inboxs = <String, Subscription<dynamic>>{};
  final _mutex = Mutex();
  String? _inboxSubPrefix;
  Subscription<dynamic>? _inboxSub;

  /// Request-Response pattern: send a request and wait for single response
  Future<Message<T>> request<T>(
    String subj,
    Uint8List data, {
    Duration timeout = const Duration(seconds: 2),
    T Function(String)? jsonDecoder,
    Header? header,
  }) async {
    if (!connected) {
      throw NatsException('request error: client not connected');
    }
    late Message<dynamic> resp;
    await _mutex.acquire();

    if (T != dynamic && jsonDecoder == null) {
      jsonDecoder = _getJsonDecoder<T>();
    }

    if (_inboxSubPrefix == null) {
      if (inboxPrefix == '_INBOX') {
        _inboxSubPrefix = inboxPrefix + '.' + Nuid().next();
      } else {
        _inboxSubPrefix = inboxPrefix;
      }
      _inboxSub =
          sub<dynamic>(_inboxSubPrefix! + '.>', jsonDecoder: jsonDecoder);
    }
    final inbox = _inboxSubPrefix! + '.' + Nuid().next();
    final stream = _inboxSub!.stream;

    await pub(subj, data, replyTo: inbox, header: header);

    try {
      do {
        resp = await stream.take(1).single.timeout(timeout);
      } while (resp.subject != inbox);
    } on TimeoutException {
      throw TimeoutException('request time > $timeout');
    } finally {
      _mutex.release();
    }

    final msg = Message<T>(
      resp.subject,
      resp.sid,
      resp.byte,
      this,
      header: resp.header,
      jsonDecoder: jsonDecoder,
    );
    return msg;
  }

  /// Request-Response helper sending String payload
  Future<Message<T>> requestString<T>(
    String subj,
    String data, {
    Duration timeout = const Duration(seconds: 2),
    T Function(String)? jsonDecoder,
    Header? header,
  }) {
    return request<T>(
      subj,
      Uint8List.fromList(data.codeUnits),
      timeout: timeout,
      jsonDecoder: jsonDecoder,
      header: header,
    );
  }

  /// Flush connection (perform ping/pong roundtrip)
  Future<void> flush() => ping();

  /// Gracefully drain all subscriptions and close connection
  Future<void> drain() async {
    final subs = List<Subscription>.from(_subs.values);
    await Future.wait(subs.map((s) => s.drain()));
    await close();
  }

  /// Gracefully drain a specific subscription
  Future<void> drainSubscription(Subscription s) async {
    final sid = s.sid;
    if (_subs[sid] == null) return;

    _unSub(sid);
    _backendSubs.remove(sid);

    await flush();

    _subs.remove(sid);
    await s.close();
  }

  /// Load NATS credentials from a credential file content
  void loadCredentials(String content) {
    final creds = Credentials.parse(content);
    seed = creds.seed;
    userJwtHandler = () => creds.jwt;
  }

  /// Load NATS credentials from a file path
  Future<void> loadCredentialsFile(String filepath) async {
    final file = File(filepath);
    final content = await file.readAsString();
    loadCredentials(content);
  }

  void _setStatus(Status newStatus) {
    final oldStatus = _status;
    _status = newStatus;
    _statusController.add(newStatus);

    if (newStatus == Status.connected) {
      if (oldStatus == Status.reconnecting && onReconnect != null) {
        onReconnect!();
      } else if (onConnect != null) {
        onConnect!();
      }
    } else if (newStatus == Status.disconnected) {
      if (onDisconnect != null) {
        onDisconnect!();
      }
    } else if (newStatus == Status.closed) {
      if (onClose != null) {
        onClose!();
      }
    }
  }

  /// Close connection and prevent any future reconnect retries
  Future<void> forceClose() async {
    _retry = false;
    await close();
  }

  /// Close active connection to NATS server but keep subscriber list client side
  Future<void> close() async {
    _setStatus(Status.closed);
    _backendSubs.forEach((k, v) => _backendSubs[k] = false);
    _inboxs.clear();
    await _wsChannel?.sink.close();
    _wsChannel = null;
    await _secureSocket?.close();
    _secureSocket = null;
    await _tcpSocket?.close();
    _tcpSocket = null;
    await _inboxSub?.close();
    _inboxSub = null;
    _inboxSubPrefix = null;
    _buffer = [];
    _clientStatus = _ClientStatus.closed;
  }

  /// Connect using raw TCP socket (deprecated: use connect(Uri) instead)
  Future<dynamic> tcpConnect(
    String host, {
    int port = 4222,
    ConnectOption? connectOption,
    int timeout = 5,
    bool retry = true,
    int retryInterval = 10,
  }) {
    return connect(
      Uri(scheme: 'nats', host: host, port: port),
      retry: retry,
      retryInterval: retryInterval,
      timeout: timeout,
      connectOption: connectOption,
    );
  }

  /// Close active TCP socket connection. Used for test simulation.
  Future<void> tcpClose() async {
    await _tcpSocket?.close();
    _setStatus(Status.disconnected);
  }

  /// Wait until client connects to NATS server
  Future<void> waitUntilConnected() async {
    await waitUntil(Status.connected);
  }

  /// Wait until client status updates to a specific state
  Future<void> waitUntil(Status s) async {
    if (status == s) {
      return;
    }
    await for (final st in statusStream) {
      if (st == s) {
        break;
      }
    }
  }

  /// Get JetStream context for the client
  JetStream jetStream() => JetStream(this);
}
