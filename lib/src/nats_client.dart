import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'nats_model.dart';

enum _ReceiveState {
  idle, //op=msg ->
  msg, //newline -> idle

}

enum Status {
  disconnected,
  connected,
  closed,
  reconnecting,
  connecting,
  // draining_subs,
  // draining_pubs,
}

class Client {
  String _host;
  int _port;
  Socket _socket;
  Info _natsInfo;
  var status = Status.disconnected;
  var _connectOption = ConnectOption(verbose: false);

  Info get natsInfo => _natsInfo;

  final _subs = Map<int, Subscription>();
  final _backendSubs = Map<int, bool>();
  int _ssid = 0;

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

    for (int i = 0; i == 0 || retry; i++) {
      if (i == 0)
        status = Status.connecting;
      else {
        status = Status.reconnecting;
        await Future.delayed(Duration(seconds: retryInterval));
      }

      try {
        _socket = await Socket.connect(_host, _port,
            timeout: Duration(seconds: timeout));
        status = Status.connected;

        _addConnectOption(_connectOption);
        _backendSubscriptAll();

        String buffer = '';
        await for (var d in _socket) {
          buffer += utf8.decode(d);
          var split = buffer.split('\r\n');
          buffer = split.removeLast();
          split.forEach((line) {
            _processLine(line);
          });
        }
        status = Status.disconnected;
        _socket.close();
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

  _ReceiveState _receiveState = _ReceiveState.idle;
  String _receiveLine1 = '';
  void _processLine(String line) {
    switch (_receiveState) {
      case _ReceiveState.idle:
        //decode operation
        var i = line.indexOf(' ');
        String op, data;
        if (i != -1) {
          op = line.substring(0, i).trim().toLowerCase();
          data = line.substring(i).trim();
        } else {
          op = line.trim().toLowerCase();
          data = '';
        }

        //process operation
        switch (op) {
          case 'msg':
            _receiveState = _ReceiveState.msg;
            _receiveLine1 = line;
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

        break;
      case _ReceiveState.msg:
        _processMsg(_receiveLine1, line);
        _receiveLine1 = '';
        _receiveState = _ReceiveState.idle;
        break;
    }
  }

  void _processErr(String data) {
    // print('NATS Client Error: $data');
    close();
  }

  void _processMsg(String line1, String line2) {
    var s = line1.split(' ');
    if (s.length == 4) s.insert(3, '');
    var subject = s[1];
    int sid = int.parse(s[2]);
    String replyTo = s[3];
    // int bytes = s[4];
    String payload = line2;

    if (_subs[sid] != null) {
      _subs[sid].add(Message(subject, sid, replyTo, payload));
    }
  }

  void ping() {
    _add('ping');
  }

  _addConnectOption(ConnectOption c) {
    _add('connect ' + jsonEncode(c.toJson()));
  }

  bool pub(String subject, String msg, {String replyTo}) {
    if (status != Status.connected) return false;

    if (replyTo == null)
      _add('pub $subject ${msg.length}');
    else
      _add('pub $subject $replyTo ${msg.length}');
    _add(msg);

    return true;
  }

  Subscription sub(String subject, {String queueGroup}) {
    _ssid++;
    Subscription s = Subscription(_ssid, subject, queueGroup: queueGroup);
    _subs[_ssid] = s;
    if (status == Status.connected) {
      _sub(subject, _ssid, queueGroup: queueGroup);
      _backendSubs[_ssid] = true;
    }
    return s;
  }

  void _sub(String subject, int sid, {String queueGroup}) {
    if (queueGroup == null)
      _add('sub $subject $sid');
    else
      _add('sub $subject $queueGroup $sid');
  }

  bool unSub(Subscription s) {
    var sid = s.sid;

    if (_subs[sid] == null) return false;
    _unSub(sid);
    _subs.remove(sid);
    s.close();
    _backendSubs.remove(sid);
    return true;
  }

  bool unSubById(int sid) {
    if (_subs[sid] == null) return false;
    return unSub(_subs[sid]);
  }

  //todo unsub with max msgs

  void _unSub(int sid, {String maxMsgs}) {
    if (maxMsgs == null)
      _add('unsub $sid');
    else
      _add('unsub $sid $maxMsgs');
  }

  bool _add(String str) {
    if (_socket == null) return false; //todo throw error
    _socket.add(utf8.encode(str + '\r\n'));
    return true;
  }

  void close() {
    _backendSubs.forEach((_, s) => s = false);
    _socket?.close();
  }
}

class Subscription {
  final int sid;
  final String subject, queueGroup;

  final _controller = StreamController<Message>();

  Subscription(this.sid, this.subject, {this.queueGroup});
  Stream<Message> get stream => _controller.stream;

  add(Message msg) {
    _controller.sink.add(msg);
  }

  void close() {
    _controller.close();
  }
}

class Message {
  final int sid;
  final String subject, replyTo, payload;
  Message(this.subject, this.sid, this.replyTo, this.payload);
  @override
  String toString() {
    return payload;
  }
}
