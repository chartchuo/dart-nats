///message model sending from NATS server
import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';

/// Message class
class Message<T> {
  ///subscriber id auto generate by client
  final int sid;

  /// subject  and replyto
  final String? subject, replyTo;
  final Client _client;

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
      {this.replyTo, this.jsonDecoder});

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
