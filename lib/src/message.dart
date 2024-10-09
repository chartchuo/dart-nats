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

  /// constructor
  Header({this.headers, this.version = 'NATS/1.0'}) {
    this.headers ??= {};
  }

  /// add key, value
  Header add(String key, String value) {
    headers![key] = value;
    return this;
  }

  /// get value from key
  /// return null if notfound
  String? get(String key) {
    return headers![key];
  }

  /// construct from bytes
  static Header fromBytes(Uint8List b) {
    var str = utf8.decode(b);
    Map<String, String> m = {};
    var strList = str.split('\r\n');
    var version = strList[0];
    strList.removeAt(0);
    for (var h in strList) {
      /// values of headers can contain ':' so find the first index for the
      /// correct split index
      var splitIndex = h.indexOf(':');

      /// if the index is <= to 0 it means there was either no ':' or its the
      /// first character. In either case its not a valid header to split.
      if (splitIndex <= 0) {
        continue;
      }
      var key = h.substring(0, splitIndex);
      var value = h.substring(splitIndex + 1);
      m[key] = value;
    }

    return Header(headers: m, version: version);
  }

  /// convert to bytes
  Uint8List toBytes() {
    var str = '${this.version}\r\n';

    headers?.forEach((k, v) {
      str = str + '$k:$v\r\n';
    });

    return utf8.encode(str);
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

  ///constructor
  Message(this.subject, this.sid, this.byte, this._client,
      {this.replyTo, this.jsonDecoder, this.header});

  ///payload in string
  String get string => utf8.decode(byte);

  ///Respond to message
  bool respond(Uint8List data) {
    if (replyTo == null || replyTo == '') return false;
    _client.pub(replyTo, data);
    return true;
  }

  ///Respond to string message
  bool respondString(String str) {
    return respond(utf8.encode(str));
  }
}
