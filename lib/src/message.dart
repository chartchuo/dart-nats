///message model sending from NATS server
import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';

/// Message Header
class Header {
  /// header version
  String version;

  /// headers key value
  Map<String, String>? headers;

  /// constructure
  Header({this.headers, this.version = 'NATS/1.0'}) {
    this.headers ??= {};
  }

  /// add key, value
  Header add(String key, String value) {
    headers![key] = value;
    return this;
  }

  /// get valure from key
  /// return null if notfound
  String? get(String key) {
    return headers![key];
  }

  /// constructure from bytes
  static Header fromBytes(Uint8List b) {
    var str = utf8.decode(b);
    Map<String, String> m = {};
    var strList = str.split('\r\n');
    var version = strList[0];
    strList.removeAt(0);
    for (var h in strList) {
      var kvStr = h.split(':');
      if (kvStr.length != 2) {
        continue;
      }
      m[kvStr[0]] = kvStr[1];
    }

    return Header(headers: m, version: version);
  }

  /// conver to bytes
  Uint8List toBytes() {
    var str = '${this.version}\r\n';

    headers?.forEach((k, v) {
      str = str + '$k:$v\r\n';
    });

    return utf8.encode(str) as Uint8List;
  }
}

/// Message class
class Message<T> {
  ///subscriber id auto generate by client
  final int sid;

  /// subject  and replyto
  final String? subject, replyTo;
  final Client _client;

  /// message header
  final Header? header;

  ///payload of data in byte
  final Uint8List byte;

  ///convert from json string to T for structure data
  T Function(String)? jsonDecoder;

  ///payload of data in byte
  T get data {
    // if (jsonDecoder == null) throw Exception('no converter. can not convert. use msg.byte instead');
    if (jsonDecoder == null) {
      return byte as T;
    }
    return jsonDecoder!(string);
  }

  ///constructure
  Message(this.subject, this.sid, this.byte, this._client,
      {this.replyTo, this.jsonDecoder, this.header});

  ///payload in string
  String get string => utf8.decode(byte);

  ///Repond to message
  bool respond(Uint8List data) {
    if (replyTo == null || replyTo == '') return false;
    _client.pub(replyTo, data);
    return true;
  }

  ///Repond to string message
  bool respondString(String str) {
    return respond(utf8.encode(str) as Uint8List);
  }
}
