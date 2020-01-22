import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';

import 'common.dart';
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

  ///connected to server
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
  final String subject;
  final List<int> data;
  final String replyTo;

  _Pub(this.subject, this.data, this.replyTo);
}

///NATS client
class Client {
  String _host;
  int _port;
  Socket _socket;
  Info _info;
  Completer _pingCompleter;

  ///status of the client
  var status = Status.disconnected;
  var _connectOption = ConnectOption(verbose: false);

  ///server info
  Info get info => _info;

  final _subs = <int, Subscription>{};
  final _backendSubs = <int, bool>{};
  final _pubBuffer = <_Pub>[];

  int _ssid = 0;

  /// Connect to NATS server
  // void connectOld(String host,
  //     {int port = 4222,
  //     ConnectOption connectOption,
  //     int timeout = 5,
  //     bool retry = true,
  //     int retryInterval = 10}) async {
  //   if (status != Status.disconnected && status != Status.closed) return;

  //   _host = host;
  //   _port = port;

  //   if (connectOption != null) _connectOption = connectOption;

  //   for (var i = 0; i == 0 || retry; i++) {
  //     if (i == 0) {
  //       status = Status.connecting;
  //     } else {
  //       status = Status.reconnecting;
  //       await Future.delayed(Duration(seconds: retryInterval));
  //     }

  //     try {
  //       _socket = await Socket.connect(_host, _port,
  //           timeout: Duration(seconds: timeout));
  //       status = Status.connected;

  //       _addConnectOption(_connectOption);
  //       _backendSubscriptAll();
  //       _flushPubBuffer();

  //       _buffer = Uint8List(0);
  //       await for (var d in _socket) {
  //         //work around error list<int> not subset of uint8list
  //         var tmp = _buffer + d;
  //         _buffer = Uint8List.fromList(tmp);

  //         switch (_receiveState) {
  //           case _ReceiveState.idle:
  //             _processOp();
  //             break;
  //           case _ReceiveState.msg:
  //             _processMsg();
  //             break;
  //         }
  //       }
  //       status = Status.disconnected;
  //       await _socket.close();
  //     } catch (err) {
  //       close();
  //     }
  //   }
  // }

  /// Connect to NATS server
  Future connect(String host,
      {int port = 4222,
      ConnectOption connectOption,
      int timeout = 5,
      bool retry = true,
      int retryInterval = 10}) async {
    if (status != Status.disconnected && status != Status.closed) {
      return Future.error('Error: status not disconnected and not closed');
    }
    _host = host;
    _port = port;

    if (connectOption != null) _connectOption = connectOption;

    void loop() async {
      for (var i = 0; i == 0 || retry; i++) {
        if (i == 0) {
          status = Status.connecting;
        } else {
          status = Status.reconnecting;
          await Future.delayed(Duration(seconds: retryInterval));
        }

        try {
          _socket = await Socket.connect(_host, _port,
              timeout: Duration(seconds: timeout));
          status = Status.connected;

          _addConnectOption(_connectOption);
          _backendSubscriptAll();
          _flushPubBuffer();

          _buffer = Uint8List(0);
          _socket.listen((d) {
            var tmp = _buffer + d;
            _buffer = Uint8List.fromList(tmp);
            while (
                _receiveState == _ReceiveState.idle && _buffer.contains(13)) {
              _processOp();
              // switch (_receiveState) {
              //   case _ReceiveState.idle:
              // _processOp();
              //     break;
              //   case _ReceiveState.msg:
              //     _processMsg();
              //     break;
              // }
            }
          }, onDone: () {
            status = Status.disconnected;
            _socket.close();
          }, onError: (err) {
            // print(err);
            status = Status.disconnected;
            _socket.close();
          });
          return;
        } catch (err) {
          // print(err);
          close();
        }
      }
    }

    return Future.microtask(loop);
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

  var _buffer = Uint8List(0);
  _ReceiveState _receiveState = _ReceiveState.idle;
  String _receiveLine1 = '';
  void _processOp() {
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
    _buffer = _buffer.sublist(nextLineIndex + 2);
    // var tmp = String.fromCharCodes(_buffer);
    // print(tmp);

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
        break;
      case 'info':
        _info = Info.fromJson(jsonDecode(data));
        break;
      case 'ping':
        _add('pong');
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
    /// print('NATS Client Error: $data');
    close();
  }

  void _processMsg() {
    var s = _receiveLine1.split(' ');
    // if (s.length == 4) s.insert(3, '');
    var subject = s[1];
    var sid = int.parse(s[2]);
    String replyTo;
    int length;
    if (s.length == 4) {
      length = int.parse(s[3]);
    } else {
      replyTo = s[3];
      length = int.parse(s[4]);
    }
    if (_buffer.length < length) return;
    var payload = _buffer.sublist(0, length);
    _buffer = _buffer.sublist(length + 2);

    if (_subs[sid] != null) {
      _subs[sid].add(Message(subject, sid, payload, this, replyTo: replyTo));
    }
    _receiveLine1 = '';
    _receiveState = _ReceiveState.idle;
  }

  /// get server max payload
  int maxPayload() => _info?.maxPayload;

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
  bool pub(String subject, Uint8List data, {String replyTo, bool buffer}) {
    buffer ??= defaultPubBuffer;
    if (status != Status.connected) {
      if (buffer) {
        _pubBuffer.add(_Pub(subject, data, replyTo));
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
      {String replyTo, bool buffer = true}) {
    return pub(subject, utf8.encode(str), replyTo: replyTo, buffer: buffer);
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
  Subscription sub(String subject, {String queueGroup}) {
    _ssid++;
    var s = Subscription(_ssid, subject, this, queueGroup: queueGroup);
    _subs[_ssid] = s;
    if (status == Status.connected) {
      _sub(subject, _ssid, queueGroup: queueGroup);
      _backendSubs[_ssid] = true;
    }
    return s;
  }

  void _sub(String subject, int sid, {String queueGroup}) {
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
    return unSub(_subs[sid]);
  }

  //todo unsub with max msgs

  void _unSub(int sid, {String maxMsgs}) {
    if (maxMsgs == null) {
      _add('unsub $sid');
    } else {
      _add('unsub $sid $maxMsgs');
    }
  }

  bool _add(String str) {
    if (_socket == null) return false; //todo throw error
    _socket.add(utf8.encode(str + '\r\n'));
    return true;
  }

  bool _addByte(List<int> msg) {
    if (_socket == null) return false; //todo throw error

    _socket.add(msg);
    _socket.add(utf8.encode('\r\n'));
    return true;
  }

  final _inboxs = <String, Subscription>{};

  /// Request will send a request payload and deliver the response message,
  /// or an error, including a timeout if no message was received properly.
  Future<Message> request(String subj, Uint8List data,
      {String queueGroup, Duration timeout}) {
    timeout ??= Duration(seconds: 2);

    if (_inboxs[subj] == null) {
      var inbox = newInbox();
      _inboxs[subj] = sub(inbox, queueGroup: queueGroup);
    }

    pub(subj, data, replyTo: _inboxs[subj].subject);
    var respond = _inboxs[subj].stream.asBroadcastStream().first;

    // todo timeout

    return respond;
  }

  ///close connection to NATS server unsub to server but still keep subscription list at client
  void close() {
    _backendSubs.forEach((_, s) => s = false);
    _inboxs.clear();
    _socket?.close();
    status = Status.closed;
  }
}
