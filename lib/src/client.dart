import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:cryptography/cryptography.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'common.dart';
import 'inbox.dart';
import 'message.dart';
import 'subscription.dart';

enum _ReceiveState {
  idle, //op=msg -> msg
  msg, //newline -> idle

}

///status of the nats client
enum Status {
  /// discontected or not connected
  disconnected,

  /// tlsHandshake
  tlsHandshake,

  /// channel layer connect wait for info connect handshake
  infoHandshake,

  ///connected to server ready
  connected,

  ///alread close by close or server
  closed,

  ///automatic reconnection to server
  reconnecting,

  ///connecting by connect() method
  connecting,

  // draining_subs,
  // draining_pubs,
}

class _Pub {
  final String? subject;
  final List<int> data;
  final String? replyTo;

  _Pub(this.subject, this.data, this.replyTo);
}

///NATS client
class Client {
  WebSocketChannel? _wsChannel;
  Socket? _tcpSocket;
  SecureSocket? _secureSocket;
  bool _tlsRequired = false;

  Info _info = Info();
  late Completer _pingCompleter;
  late Completer _connectCompleter;

  var _status = Status.disconnected;

  final _statusController = StreamController<Status>();

  final _channelStream = StreamController();

  ///status of the client
  Status get status => _status;

  /// accept bad certificate NOT recomend to use in production
  bool acceptBadCert = false;

  /// Stream status for status update
  Stream<Status> get statusStream => _statusController.stream;

  var _connectOption = ConnectOption(verbose: false);

  /// Nkeys seed
  String get seed => _seed;
  set seed(String newseed) {
    // todo validate newseed
    var raw = base32.decode(newseed);

    if (raw.length != 36) throw Exception('invalid seed');
    _seed = newseed;
  }

  String _seed = '';

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
    if (_info.nonce != null) {
      var algo = Ed25519();
      var raw = base32.decode(seed);
      var key = raw.sublist(2, 34);

      var keyPair = await algo.newKeyPairFromSeed(key);

      var sig =
          await algo.sign(utf8.encode(_info.nonce ?? ''), keyPair: keyPair);

      _connectOption.sig = base64.encode(sig.bytes);
    }
  }

  /// Connect to NATS server
  Future connect(
    Uri uri, {
    ConnectOption? connectOption,
    int timeout = 5,
    bool retry = true,
    int retryInterval = 10,
  }) async {
    _connectCompleter = Completer();
    if (status != Status.disconnected && status != Status.closed) {
      return Future.error('Error: status not disconnected and not closed');
    }
    if (connectOption != null) _connectOption = connectOption;
    _connectOption.verbose = false;

    void loop() async {
      for (var retryCount = 0; retryCount == 0 || retry; retryCount++) {
        if (retryCount == 0) {
          _setStatus(Status.connecting);
        } else {
          _setStatus(Status.reconnecting);
          await Future.delayed(Duration(seconds: retryInterval));
        }

        try {
          await _connectUri(uri, timeout: timeout);

          _setStatus(Status.infoHandshake);
          retryCount = 0;

          _buffer = [];
          _channelStream.stream.listen((d) {
            _buffer.addAll(d);
            // org code
            // while (
            //     _receiveState == _ReceiveState.idle && _buffer.contains(13)) {
            //   _processOp();
            // }

            //Thank aktxyz for contribution
            while (
                _receiveState == _ReceiveState.idle && _buffer.contains(13)) {
              var n13 = _buffer.indexOf(13);
              var msgFull =
                  String.fromCharCodes(_buffer.take(n13)).toLowerCase().trim();
              var msgList = msgFull.split(' ');
              var msgType = msgList[0];
              //print('... process $msgType ${_buffer.length}');

              if (msgType == 'msg') {
                var len =
                    int.parse((msgList.length == 4 ? msgList[3] : msgList[4]));
                if (len > 0 && _buffer.length < (msgFull.length + len + 4)) {
                  break; // not a full payload, go around again
                }
              }

              _processOp();
            }
          }, onDone: () {
            _setStatus(Status.disconnected);
            close();
          }, onError: (err) {
            _setStatus(Status.disconnected);
            close();
          });
          return;
        } catch (err) {
          await close();
          if (!_connectCompleter.isCompleted) {
            _connectCompleter.completeError(err);
          }
          _setStatus(Status.disconnected);
        }
      }
    }

    loop();
    return _connectCompleter.future;
  }

  Future _connectUri(Uri uri, {int timeout = 5}) async {
    if (uri.scheme == '') {
      throw Exception('No scheme in uri');
    }
    switch (uri.scheme) {
      case 'wss':
      case 'ws':
        _wsChannel = WebSocketChannel.connect(uri);
        if (_wsChannel == null) break;
        _setStatus(Status.infoHandshake);
        _wsChannel!.stream.listen((event) {
          if (_channelStream.isClosed) return;
          _channelStream.add(event);
        });
        break;
      case 'nats':
        var port = uri.port;
        if (port == 0) {
          port = 4222;
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
        break;
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
        break;
      default:
        throw Exception('schema ${uri.scheme} not support');
    }
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
      case 'info':
        _info = Info.fromJson(jsonDecode(data));
        if (_tlsRequired && !(_info.tlsRequired ?? false)) {
          throw Exception('require TLS but server not required');
        }

        if (_info.tlsRequired ?? false) {
          _setStatus(Status.tlsHandshake);
          var secureSocket = await SecureSocket.secure(
            _tcpSocket!,
            onBadCertificate: (certificate) {
              if (acceptBadCert) return true;
              return false;
            },
          );

          _secureSocket = secureSocket;
          secureSocket.listen((event) {
            if (_channelStream.isClosed) return;
            _channelStream.add(event);
          });
        }

        await _sign();
        _addConnectOption(_connectOption);
        _setStatus(Status.connected);
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
        _processErr(data);
        break;
      case 'pong':
        _pingCompleter.complete();
        break;
      case '+ok':
        //do nothing
        break;
    }
  }

  void _processErr(String data) {
    close();
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
      _subs[sid]!.add(Message(subject, sid, payload, this, replyTo: replyTo));
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
  bool pub(String? subject, Uint8List data, {String? replyTo, bool? buffer}) {
    buffer ??= defaultPubBuffer;
    if (status != Status.connected) {
      if (buffer) {
        _pubBuffer.add(_Pub(subject, data, replyTo));
        return true;
      } else {
        return false;
      }
    }

    if (replyTo == null) {
      _add('pub $subject ${data.length}');
    } else {
      _add('pub $subject $replyTo ${data.length}');
    }
    _addByte(data);

    return true;
  }

  ///publish by string
  bool pubString(String subject, String str,
      {String? replyTo, bool buffer = true}) {
    return pub(subject, utf8.encode(str) as Uint8List,
        replyTo: replyTo, buffer: buffer);
  }

  bool _pub(_Pub p) {
    if (p.replyTo == null) {
      _add('pub ${p.subject} ${p.data.length}');
    } else {
      _add('pub ${p.subject} ${p.replyTo} ${p.data.length}');
    }
    _addByte(p.data);

    return true;
  }

  ///subscribe to subject option with queuegroup
  Subscription<T> sub<T>(String subject,
      {String? queueGroup, T Function(String)? jsonConverter}) {
    _ssid++;
    var s = Subscription<T>(_ssid, subject, this,
        queueGroup: queueGroup, jsonConverter: jsonConverter);
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
    if (_wsChannel != null) {
      // if (_wsChannel?.closeCode == null) return;
      _wsChannel!.sink.add(utf8.encode(str + '\r\n'));
      return;
    } else if (_secureSocket != null) {
      _secureSocket!.add(utf8.encode(str + '\r\n'));
      return;
    } else if (_tcpSocket != null) {
      _tcpSocket!.add(utf8.encode(str + '\r\n'));
      return;
    }
    throw Exception('no connection');
  }

  void _addByte(List<int> msg) {
    if (_wsChannel != null) {
      _wsChannel!.sink.add(msg);
      _wsChannel!.sink.add(utf8.encode('\r\n'));
      return;
    } else if (_secureSocket != null) {
      _secureSocket!.add(msg);
      _secureSocket!.add(utf8.encode('\r\n'));
      return;
    } else if (_tcpSocket != null) {
      _tcpSocket!.add(msg);
      _tcpSocket!.add(utf8.encode('\r\n'));
      return;
    }
    throw Exception('no connection');
  }

  final _inboxs = <String, Subscription>{};

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
  Future<Message> request(String subj, Uint8List data,
      {String? queueGroup, Duration? timeout}) {
    if (_inboxs[subj] == null) {
      var inbox = newInbox();
      _inboxs[subj] = sub(inbox, queueGroup: queueGroup);
    }

    var stream = _inboxs[subj]!.stream;

    var respond = stream.take(1).single;
    pub(subj, data, replyTo: _inboxs[subj]!.subject);

    if (timeout != null) return respond.timeout(timeout);
    return respond;
  }

  /// requestString() helper to request()
  Future<Message> requestString(String subj, String data,
      {String? queueGroup, Duration? timeout}) {
    return request(subj, Uint8List.fromList(data.codeUnits),
        queueGroup: queueGroup, timeout: timeout);
  }

  void _setStatus(Status newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  ///close connection to NATS server unsub to server but still keep subscription list at client
  Future close() async {
    _backendSubs.forEach((_, s) => s = false);
    _inboxs.clear();
    _setStatus(Status.closed);
    await _wsChannel?.sink.close();
    _wsChannel = null;
    await _secureSocket?.close();
    _secureSocket = null;
    await _tcpSocket?.close();
    _tcpSocket = null;
    await _channelStream.close();

    _buffer = [];
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
}
