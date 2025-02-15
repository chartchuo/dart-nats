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

enum _ReceiveState {
  idle, //op=msg -> msg
  msg, //newline -> idle
}

///status of the nats client
enum Status {
  /// disconnected or not connected
  disconnected,

  /// tlsHandshake
  tlsHandshake,

  /// channel layer connect wait for info connect handshake
  infoHandshake,

  ///connected to server ready
  connected,

  ///already close by close or server
  closed,

  ///automatic reconnection to server
  reconnecting,

  ///connecting by connect() method
  connecting,

  // draining_subs,
  // draining_pubs,
}

enum _ClientStatus {
  init,
  used,
  closed,
}

class _Pub {
  final String? subject;
  final List<int> data;
  final String? replyTo;

  _Pub(this.subject, this.data, this.replyTo);
}

///NATS client
class Client {
  var _ackStream = StreamController<bool>.broadcast();
  _ClientStatus _clientStatus = _ClientStatus.init;
  WebSocketChannel? _wsChannel;
  Socket? _tcpSocket;
  SecureSocket? _secureSocket;
  bool _tlsRequired = false;
  bool _retry = false;

  Info _info = Info();
  late Completer _pingCompleter;
  late Completer _connectCompleter;

  /// Error handler for websocket errors
  Function(dynamic) wsErrorHandler = (e) {
    throw NatsException('listen ws error: $e');
  };

  var _status = Status.disconnected;

  /// true if connected
  bool get connected => _status == Status.connected;

  final _statusController = StreamController<Status>.broadcast();

  var _channelStream = StreamController();

  ///status of the client
  Status get status => _status;

  /// accept bad certificate NOT recomend to use in production
  bool acceptBadCert = false;

  /// Stream status for status update
  Stream<Status> get statusStream => _statusController.stream;

  var _connectOption = ConnectOption();

  ///SecurityContext
  SecurityContext? securityContext;

  final _jsonDecoder = <Type, dynamic Function(String)>{};

  // final _jsonEncoder = <Type, String Function(Type)>{};

  /// add json decoder for type <T>
  void registerJsonDecoder<T>(T Function(String) f) {
    if (T == dynamic) {
      NatsException('can not register dyname type');
    }
    _jsonDecoder[T] = f;
  }

  /// add json encoder for type <T>
  // void registerJsonEncoder<T>(String Function(T) f) {
  //   if (T == dynamic) {
  //     NatsException('can not register dyname type');
  //   }
  //   _jsonEncoder[T] = f as String Function(Type);
  // }

  ///server info
  Info? get info => _info;

  final _subs = <int, Subscription>{};
  final _backendSubs = <int, bool>{};
  final _pubBuffer = <_Pub>[];

  int _ssid = 0;

  List<int> _buffer = [];
  _ReceiveState _receiveState = _ReceiveState.idle;
  String _receiveLine1 = '';

  Future _sign() async {
    if (_info.nonce != null && _connectOption.authenticator != null) {
      var _nkeys = Nkeys.fromSeed(_connectOption.authenticator.toString());
      var sig = _nkeys.sign(utf8.encode(_info.nonce!));
      _connectOption.sig = base64.encode(sig);
      _connectOption.nkey = _nkeys.publicKey();
    }
  }

  ///NATS Client Constructor
  Client() {
    _steamHandle();
  }

  void _steamHandle() {
    _channelStream.stream.listen((d) {
      _buffer.addAll(d);
      // org code
      // while (
      //     _receiveState == _ReceiveState.idle && _buffer.contains(13)) {
      //   _processOp();
      // }

      //Thank aktxyz for contribution
      while (_receiveState == _ReceiveState.idle && _buffer.contains(13)) {
        var n13 = _buffer.indexOf(13);
        var msgFull =
            String.fromCharCodes(_buffer.take(n13)).toLowerCase().trim();
        var msgList = msgFull.split(' ');
        var msgType = msgList[0];
        //print('... process $msgType ${_buffer.length}');

        if (msgType == 'msg' || msgType == 'hmsg') {
          var len = int.parse(msgList.last);
          if (len > 0 && _buffer.length < (msgFull.length + len + 4)) {
            break; // not a full payload, go around again
          }
        }

        _processOp();
      }
      // }, onDone: () {
      //   _setStatus(Status.disconnected);
      //   close();
      // }, onError: (err) {
      //   _setStatus(Status.disconnected);
      //   close();
    });
  }

  /// Connect to NATS server
  Future connect(
    Uri uri, {
    ConnectOption? connectOption,
    int timeout = 5,
    bool retry = true,
    int retryInterval = 10,
    int retryCount = 3,
    SecurityContext? securityContext,
  }) async {
    this._retry = retry;
    this.securityContext = securityContext;
    _connectCompleter = Completer();
    if (_clientStatus == _ClientStatus.used) {
      throw Exception(
          NatsException('client in use. must close before call connect'));
    }
    if (status != Status.disconnected && status != Status.closed) {
      return Future.error('Error: status not disconnected and not closed');
    }
    _clientStatus = _ClientStatus.used;
    if (connectOption != null) _connectOption = connectOption;
    do {
      _connectLoop(
        uri,
        timeout: timeout,
        retryInterval: retryInterval,
        retryCount: retryCount,
      );

      if (_clientStatus == _ClientStatus.closed || status == Status.closed) {
        if (!_connectCompleter.isCompleted) {
          _connectCompleter.complete();
        }
        close();
        _clientStatus = _ClientStatus.closed;
        return;
      }
      if (!this._retry || retryCount != -1) {
        return _connectCompleter.future;
      }
      await for (var s in statusStream) {
        if (s == Status.disconnected) {
          break;
        }
        if (s == Status.closed) {
          return;
        }
      }
    } while (this._retry && retryCount == -1);
    return _connectCompleter.future;
  }

  void _connectLoop(Uri uri,
      {int timeout = 5,
      required int retryInterval,
      required int retryCount}) async {
    for (var count = 0;
        count == 0 || ((count < retryCount || retryCount == -1) && this._retry);
        count++) {
      if (count == 0) {
        _setStatus(Status.connecting);
      } else {
        _setStatus(Status.reconnecting);
      }

      try {
        if (_channelStream.isClosed) {
          _channelStream = StreamController();
        }
        var sucess = await _connectUri(uri, timeout: timeout);
        if (!sucess) {
          await Future.delayed(Duration(seconds: retryInterval));
          continue;
        }

        _buffer = [];

        return;
      } catch (err) {
        await close();
        if (!_connectCompleter.isCompleted) {
          _connectCompleter.completeError(err);
        }
        _setStatus(Status.disconnected);
      }
    }
    if (!_connectCompleter.isCompleted) {
      _clientStatus = _ClientStatus.closed;
      _connectCompleter
          .completeError(NatsException('can not connect ${uri.toString()}'));
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
          _wsChannel?.stream.listen((event) {
            if (_channelStream.isClosed) return;
            _channelStream.add(event);
          }, onDone: () {
            _setStatus(Status.disconnected);
          }, onError: (e) {
            print(e);
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
          _tcpSocket = await Socket.connect(uri.host, port,
              timeout: Duration(seconds: timeout));
          if (_tcpSocket == null) break;
          _setStatus(Status.infoHandshake);
          _tcpSocket!.listen((event) {
            if (_secureSocket == null) {
              if (_channelStream.isClosed) return;
              _channelStream.add(event);
            }
          });
          return true;
        default:
          throw Exception(NatsException('schema ${uri.scheme} not support'));
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  void _backendSubscriptAll() {
    _backendSubs.clear();
    _subs.forEach((sid, s) async {
      _sub(s.subject, sid, queueGroup: s.queueGroup);
      // s.backendSubscription = true;
      _backendSubs[sid] = true;
    });
  }

  void _flushPubBuffer() {
    _pubBuffer.forEach((p) {
      _pub(p);
    });
  }

  void _processOp() async {
    ///find endline
    var nextLineIndex = _buffer.indexWhere((c) {
      if (c == 13) {
        return true;
      }
      return false;
    });
    if (nextLineIndex == -1) return;
    var line =
        String.fromCharCodes(_buffer.sublist(0, nextLineIndex)); // retest
    if (_buffer.length > nextLineIndex + 2) {
      _buffer.removeRange(0, nextLineIndex + 2);
    } else {
      _buffer = [];
    }

    ///decode operation
    var i = line.indexOf(' ');
    String op, data;
    if (i != -1) {
      op = line.substring(0, i).trim().toLowerCase();
      data = line.substring(i).trim();
    } else {
      op = line.trim().toLowerCase();
      data = '';
    }

    ///process operation
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
        _info = Info.fromJson(jsonDecode(data));
        if (_tlsRequired && !(_info.tlsRequired ?? false)) {
          throw Exception(NatsException('require TLS but server not required'));
        }

        if ((_info.tlsRequired ?? false) && _tcpSocket != null) {
          _setStatus(Status.tlsHandshake);
          var secureSocket = await SecureSocket.secure(
            _tcpSocket!,
            context: this.securityContext,
            onBadCertificate: (certificate) {
              if (acceptBadCert) return true;
              return false;
            },
          );

          _secureSocket = secureSocket;
          secureSocket.listen((event) {
            if (_channelStream.isClosed) return;
            _channelStream.add(event);
          }, onError: (error) {
            print('Socket error: $error');
            _setStatus(Status.disconnected);

            if (error is TlsException) {
              this._retry = false;
              this.close();
              throw Exception(NatsException(error.message));
            }
          });
        }

        await _sign();
        _addConnectOption(_connectOption);
        if (_connectOption.verbose == true) {
          var ack = await _ackStream.stream.first;
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
        // _processErr(data);
        if (_connectOption.verbose == true) {
          _ackStream.sink.add(false);
        }
        break;
      case 'pong':
        _pingCompleter.complete();
        break;
      case '+ok':
        //do nothing
        if (_connectOption.verbose == true) {
          _ackStream.sink.add(true);
        }
        break;
    }
  }

  void _processMsg() {
    var s = _receiveLine1.split(' ');
    var subject = s[1];
    var sid = int.parse(s[2]);
    String? replyTo;
    int length;
    if (s.length == 4) {
      length = int.parse(s[3]);
    } else {
      replyTo = s[3];
      length = int.parse(s[4]);
    }
    if (_buffer.length < length) return;
    var payload = Uint8List.fromList(_buffer.sublist(0, length));
    // _buffer = _buffer.sublist(length + 2);
    if (_buffer.length > length + 2) {
      _buffer.removeRange(0, length + 2);
    } else {
      _buffer = [];
    }

    if (_subs[sid] != null) {
      _subs[sid]?.add(Message(subject, sid, payload, this, replyTo: replyTo));
    }
  }

  void _processHMsg() {
    var s = _receiveLine1.split(' ');
    var subject = s[1];
    var sid = int.parse(s[2]);
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
    var header = Uint8List.fromList(_buffer.sublist(0, headerLength));
    var payload = Uint8List.fromList(_buffer.sublist(headerLength, length));
    // _buffer = _buffer.sublist(length + 2);
    if (_buffer.length > length + 2) {
      _buffer.removeRange(0, length + 2);
    } else {
      _buffer = [];
    }

    if (_subs[sid] != null) {
      var msg = Message(subject, sid, payload, this,
          replyTo: replyTo, header: Header.fromBytes(header));
      _subs[sid]?.add(msg);
    }
  }

  /// get server max payload
  int? maxPayload() => _info.maxPayload;

  ///ping server current not implement pong verification
  Future ping() {
    _pingCompleter = Completer();
    _add('ping');
    return _pingCompleter.future;
  }

  void _addConnectOption(ConnectOption c) {
    _add('connect ' + jsonEncode(c.toJson()));
  }

  ///default buffer action for pub
  var defaultPubBuffer = true;

  ///publish by byte (Uint8List) return true if sucess sending or buffering
  ///return false if not connect
  Future<bool> pub(String? subject, Uint8List data,
      {String? replyTo, bool? buffer, Header? header}) async {
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
    var headerByte = header?.toBytes();
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
      var dataWithHeader = headerByte.toList();
      dataWithHeader.addAll(data.toList());
      _addByte(dataWithHeader);
    } else {
      cmd += ' ${data.length}';
      _add(cmd);
      _addByte(data);
    }

    if (_connectOption.verbose == true) {
      var ack = await _ackStream.stream.first;
      return ack;
    }
    return true;
  }

  ///publish by string
  Future<bool> pubString(String subject, String str,
      {String? replyTo, bool buffer = true, Header? header}) async {
    return pub(subject, Uint8List.fromList(utf8.encode(str)),
        replyTo: replyTo, buffer: buffer);
  }

  Future<bool> _pub(_Pub p) async {
    if (p.replyTo == null) {
      _add('pub ${p.subject} ${p.data.length}');
    } else {
      _add('pub ${p.subject} ${p.replyTo} ${p.data.length}');
    }
    _addByte(p.data);
    if (_connectOption.verbose == true) {
      var ack = await _ackStream.stream.first;
      return ack;
    }
    return true;
  }

  T Function(String) _getJsonDecoder<T>() {
    var c = _jsonDecoder[T];
    if (c == null) {
      throw NatsException('no decoder for type $T');
    }
    return c as T Function(String);
  }

  // String Function(dynamic) _getJsonEncoder(Type T) {
  //   var c = _jsonDecoder[T];
  //   if (c == null) {
  //     throw NatsException('no encoder for type $T');
  //   }
  //   return c as String Function(dynamic);
  // }

  ///subscribe to subject option with queuegroup
  Subscription<T> sub<T>(
    String subject, {
    String? queueGroup,
    T Function(String)? jsonDecoder,
  }) {
    _ssid++;

    //get registered json decoder
    if (T != dynamic && jsonDecoder == null) {
      jsonDecoder = _getJsonDecoder();
    }

    var s = Subscription<T>(_ssid, subject, this,
        queueGroup: queueGroup, jsonDecoder: jsonDecoder);
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

  ///unsubscribe
  bool unSub(Subscription s) {
    var sid = s.sid;

    if (_subs[sid] == null) return false;
    _unSub(sid);
    _subs.remove(sid);
    s.close();
    _backendSubs.remove(sid);
    return true;
  }

  ///unsubscribe by id
  bool unSubById(int sid) {
    if (_subs[sid] == null) return false;
    return unSub(_subs[sid]!);
  }

  //todo unsub with max msgs

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
      // if (_wsChannel?.closeCode == null) return;
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

  /// get Inbox prefix default '_INBOX'
  set inboxPrefix(String i) {
    if (_clientStatus == _ClientStatus.used) {
      throw NatsException('inbox prefix can not change when connection in use');
    }
    _inboxPrefix = i;
    _inboxSubPrefix = null;
  }

  /// set Inbox prefix default '_INBOX'
  String get inboxPrefix => _inboxPrefix;

  final _inboxs = <String, Subscription>{};
  final _mutex = Mutex();
  String? _inboxSubPrefix;
  Subscription? _inboxSub;

  /// Request will send a request payload and deliver the response message,
  /// TimeoutException on timeout.
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   await client.request('service', Uint8List.fromList('request'.codeUnits),
  ///       timeout: Duration(seconds: 2));
  /// } on TimeoutException {
  ///   timeout = true;
  /// }
  /// ```
  Future<Message<T>> request<T>(
    String subj,
    Uint8List data, {
    Duration timeout = const Duration(seconds: 2),
    T Function(String)? jsonDecoder,
  }) async {
    if (!connected) {
      throw NatsException("request error: client not connected");
    }
    Message resp;
    //ensure no other request
    await _mutex.acquire();
    //get registered json decoder
    if (T != dynamic && jsonDecoder == null) {
      jsonDecoder = _getJsonDecoder();
    }

    if (_inboxSubPrefix == null) {
      if (inboxPrefix == '_INBOX') {
        _inboxSubPrefix = inboxPrefix + '.' + Nuid().next();
      } else {
        _inboxSubPrefix = inboxPrefix;
      }
      _inboxSub = sub<T>(_inboxSubPrefix! + '.>', jsonDecoder: jsonDecoder);
    }
    var inbox = _inboxSubPrefix! + '.' + Nuid().next();
    var stream = _inboxSub!.stream;

    pub(subj, data, replyTo: inbox);

    try {
      do {
        resp = await stream.take(1).single.timeout(timeout);
      } while (resp.subject != inbox);
    } on TimeoutException {
      throw TimeoutException('request time > $timeout');
    } catch (e) {
      throw NatsException(e.toString());
    } finally {
      _mutex.release();
    }
    var msg = Message<T>(
      resp.subject,
      resp.sid,
      resp.byte,
      this,
      header: resp.header,
      jsonDecoder: jsonDecoder,
    );
    return msg;
  }

  /// requestString() helper to request()
  Future<Message<T>> requestString<T>(
    String subj,
    String data, {
    Duration timeout = const Duration(seconds: 2),
    T Function(String)? jsonDecoder,
  }) {
    return request<T>(
      subj,
      Uint8List.fromList(data.codeUnits),
      timeout: timeout,
      jsonDecoder: jsonDecoder,
    );
  }

  void _setStatus(Status newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  /// close connection and cancel all future retries
  Future forceClose() async {
    this._retry = false;
    this.close();
  }

  ///close connection to NATS server unsub to server but still keep subscription list at client
  Future close() async {
    _setStatus(Status.closed);
    _backendSubs.forEach((_, s) => s = false);
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

  /// discontinue tcpConnect. use connect(uri) instead
  ///Backward compatible with 0.2.x version
  Future tcpConnect(String host,
      {int port = 4222,
      ConnectOption? connectOption,
      int timeout = 5,
      bool retry = true,
      int retryInterval = 10}) {
    return connect(
      Uri(scheme: 'nats', host: host, port: port),
      retry: retry,
      retryInterval: retryInterval,
      timeout: timeout,
      connectOption: connectOption,
    );
  }

  /// close tcp connect Only for testing
  Future<void> tcpClose() async {
    await _tcpSocket?.close();
    _setStatus(Status.disconnected);
  }

  /// wait until client connected
  Future<void> waitUntilConnected() async {
    await waitUntil(Status.connected);
  }

  /// wait untril status
  Future<void> waitUntil(Status s) async {
    if (status == s) {
      return;
    }
    await for (var st in statusStream) {
      if (st == s) {
        break;
      }
    }
  }
}
