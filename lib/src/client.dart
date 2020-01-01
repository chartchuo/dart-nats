import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'common.dart';
import 'message.dart';
import 'subscription.dart';

enum _ReceiveState {
  idle, //op=msg ->
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
  final List<int> msg;
  final String replyTo;

  _Pub(this.subject, this.msg, this.replyTo);
}

///NATS client
class Client {
  String _host;
  int _port;
  Socket _socket;
  Info _natsInfo;

  ///status of the client
  var status = Status.disconnected;
  var _connectOption = ConnectOption(verbose: false);

  ///server info
  Info get natsInfo => _natsInfo;

  final _subs = <int, Subscription>{};
  final _backendSubs = <int, bool>{};
  final _pubBuffer = <_Pub>[];

  int _ssid = 0;

  /// Connect to NATS server
  void connect(String host,
      {int port = 4222,
      ConnectOption connectOption,
      int timeout = 5,
      bool retry = true,
      int retryInterval = 10}) async {
    if (status != Status.disconnected && status != Status.closed) return;

    _host = host;
    _port = port;

    if (connectOption != null) _connectOption = connectOption;

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
        _drainPubBuffer();

        _buffer = Uint8List(0);
        await for (var d in _socket) {
          //work around error list<int> not subset of uint8list
          var tmp = _buffer + d;
          _buffer = Uint8List.fromList(tmp);

          switch (_receiveState) {
            case _ReceiveState.idle:
              _processOp();
              break;
            case _ReceiveState.msg:
              _processMsg();
              break;
          }
        }
        status = Status.disconnected;
        await _socket.close();
      } catch (err) {
        close();
      }
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

  void _drainPubBuffer() {
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
    var tmp = String.fromCharCodes(_buffer);
    print(tmp);

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
        // _receiveState = _ReceiveState.msg;
        _receiveLine1 = line;
        _processMsg();
        break;
      case 'info':
        _natsInfo = Info.fromJson(jsonDecode(data));
        break;
      case 'ping':
        _add('pong');
        break;
      case '-err':
        _processErr(data);
        break;
      case 'pong':
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
      _subs[sid].add(Message(subject, sid, replyTo, payload));
    }
    _receiveLine1 = '';
    _receiveState = _ReceiveState.idle;
  }

  ///ping server current not implement pong verification
  void ping() {
    _add('ping');
  }

  void _addConnectOption(ConnectOption c) {
    _add('connect ' + jsonEncode(c.toJson()));
  }

  ///publish by byte (Uint8List)
  bool pub(String subject, Uint8List msg,
      {String replyTo, bool buffer = true}) {
    if (status != Status.connected) {
      if (buffer) {
        _pubBuffer.add(_Pub(subject, msg, replyTo));
      } else {
        return false;
      }
    }

    if (replyTo == null) {
      _add('pub $subject ${msg.length}');
    } else {
      _add('pub $subject $replyTo ${msg.length}');
    }
    _addByte(msg);

    return true;
  }

  ///publish by string
  bool pubString(String subject, String msg,
      {String replyTo, bool buffer = true}) {
    return pub(subject, utf8.encode(msg), replyTo: replyTo, buffer: buffer);
  }

  bool _pub(_Pub p) {
    if (p.replyTo == null) {
      _add('pub ${p.subject} ${p.msg.length}');
    } else {
      _add('pub ${p.subject} ${p.replyTo} ${p.msg.length}');
    }
    _addByte(p.msg);

    return true;
  }

  ///subscribe to subject option with queuegroup
  Subscription sub(String subject, {String queueGroup}) {
    _ssid++;
    var s = Subscription(_ssid, subject, queueGroup: queueGroup);
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

  ///close connection to NATS server unsub to server but still keep subscription list at client
  void close() {
    _backendSubs.forEach((_, s) => s = false);
    _socket?.close();
    status = Status.closed;
  }
}
