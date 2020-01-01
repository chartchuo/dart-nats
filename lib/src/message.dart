///message model sending from NATS server
import 'dart:convert';
import 'dart:typed_data';

class Message {
  ///subscriber id auto generate by client
  final int sid;

  /// subject  and replyto
  final String subject, replyTo;

  ///payload of data in byte
  final Uint8List payload;

  ///constructure
  Message(this.subject, this.sid, this.replyTo, this.payload);

  ///payload in string
  String get payloadString => utf8.decode(payload);
}
