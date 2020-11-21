import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_nats_client/dart_nats_client.dart';

import 'common.dart';
import 'message.dart';
import 'subscription.dart';
import 'healthcheck.dart';

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
  /// Subject of publication
  final String subject;

  /// Data array
  final List<int> data;

  /// Name of user if it is reply
  final String replyTo;

  _Pub(this.subject, this.data, this.replyTo);
}

/// NATS client
class Client {
  /// Host name
  String _host;

  /// NATS port
  int _port;

  /// Socket connection object
  Socket _socket;

  /// Connection info
  Info _info;

  /// Ping controller
  Completer _pingCompleter;

  /// Connection controller
  Completer _connectCompleter;

  /// Status of the client
  Status status;

  /// Healthcheck status
  Healthcheck _healthcheck;

  /// Connection options
  var _connectOption = ConnectOption(verbose: false);

  ///server info
  Info get info => _info;

  ///connection status
  Healthcheck get healthcheck => _healthcheck;

  /// Subscriptions map
  final _subs = <int, Subscription>{};

  /// Subscription backend
  final _backendSubs = <int, bool>{};

  /// Publication buffer
  final _pubBuffer = <_Pub>[];

  /// Instance ID
  int _ssid = 0;

  /// Default constructor
  Client() {
    // Set status default disconnected
    status = Status.disconnected;
    // Init healthcheck
    _healthcheck = Healthcheck(status);
  }

  /// Connect to NATS server
  Future connect(String host,
      {int port = 4222,
      ConnectOption connectOption,
      int timeout = 5,
      bool retry = true,
      int retryInterval = 10}) async {
    // Init connection controller
    _connectCompleter = Completer();
    // Check  connection status. If connected, don't allow connect again
    if (status != Status.disconnected && status != Status.closed) {
      // Return Future error for await catch
      return Future.error('Error: status not disconnected and not closed');
    }
    // Save hostname
    _host = host;
    // Save port name
    _port = port;
    // Check connection options validity and save
    if (connectOption != null) _connectOption = connectOption;

    // Start for loop for cennection with retries
    for (var i = 0; i == 0 || retry; i++) {
      if (i == 0) {
        // If first attempt, status - connecting
        status = Status.connecting;
        // Add status to health check controller
        _healthcheck.add(status);
      } else {
        // If not first attempt, set status reconnecting
        status = Status.reconnecting;
        // Add status to health check controller
        _healthcheck.add(status);
        // Add delay on retryInterval for next attempt
        await Future.delayed(Duration(seconds: retryInterval));
      }

      // Try-Catch socket exceptions
      try {
        // Init socket connection.
        // On this stage exception can be caught.
        _socket = await Socket.connect(_host, _port,
            timeout: Duration(seconds: timeout));
        // Set status connected after socket was inited
        status = Status.connected;
        // Add status to health check controller
        _healthcheck.add(status);
        // Set complete status to connect controller
        _connectCompleter.complete();
        // Add connecton options
        _addConnectOption(_connectOption);
        // Clear backend subscriptions
        _backendSubscriptAll();
        // Clear publications buffer
        _flushPubBuffer();

        _buffer = [];
        _socket.listen((d) {
          _buffer.addAll(d);
          while (_receiveState == _ReceiveState.idle && _buffer.contains(13)) {
            _processOp();
          }
        }, onDone: () {
          status = Status.disconnected;
          _healthcheck.add(status);
          _socket.close();
        }, onError: (err) {
          status = Status.disconnected;
          _healthcheck.add(status);
          _socket.close();
        });
        // Exit from loop on success
        break;
      } catch (err) {
        // Close connection
        close();
        // Set error into Completer
        _connectCompleter.completeError(err);
      }
    }

    return _connectCompleter.future;
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

  List<int> _buffer = [];
  _ReceiveState _receiveState = _ReceiveState.idle;
  String _receiveLine1 = '';
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
    close();
  }

  void _processMsg() {
    var s = _receiveLine1.split(' ');
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
    var payload = Uint8List.fromList(_buffer.sublist(0, length));
    // _buffer = _buffer.sublist(length + 2);
    if (_buffer.length > length + 2) {
      _buffer.removeRange(0, length + 2);
    } else {
      _buffer = [];
    }

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
    data ??= Uint8List(0);

    if (_inboxs[subj] == null) {
      var inbox = newInbox();
      _inboxs[subj] = sub(inbox, queueGroup: queueGroup);
    }

    var stream = _inboxs[subj].stream;
    var respond = stream.take(1).single;
    pub(subj, data, replyTo: _inboxs[subj].subject);

    // todo timeout

    return respond;
  }

  /// requestString() helper to request()
  Future<Message> requestString(String subj, String data,
      {String queueGroup, Duration timeout}) {
    data ??= '';
    return request(subj, Uint8List.fromList(data.codeUnits),
        queueGroup: queueGroup, timeout: timeout);
  }

  ///close connection to NATS server unsub to server but still keep subscription list at client
  void close() {
    _backendSubs.forEach((_, s) => s = false);
    _inboxs.clear();
    _socket?.close();
    status = Status.closed;
    _healthcheck.add(status);
  }
}
