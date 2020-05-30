///subscription model
import 'dart:async';

import 'message.dart';
import 'client.dart';

/// subscription class
class Subscription {
  ///subscriber id (audo generate)
  final int sid;

  ///subject and queuegroup of this subscription
  final String subject, queueGroup;

  final Client _client;

  final _controller = StreamController<Message>();

  Stream<Message> _stream;

  ///constructure
  Subscription(this.sid, this.subject, this._client, {this.queueGroup}) {
    _stream = _controller.stream.asBroadcastStream();
  }

  ///
  void unSub() {
    _client.unSub(this);
  }

  ///Stream output when server publish message
  Stream<Message> get stream => _stream;

  ///sink messat to listener
  void add(Message msg) {
    _controller.sink.add(msg);
  }

  ///close the stream
  void close() {
    _controller.close();
  }
}
