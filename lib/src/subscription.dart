///subscription model
import 'dart:async';

import 'client.dart';
import 'message.dart';

/// subscription class
class Subscription<T> {
  ///subscriber id (audo generate)
  final int sid;

  ///subject and queuegroup of this subscription
  final String? subject, queueGroup;

  final Client _client;

  late StreamController<Message<T>> _controller;

  late Stream<Message<T>> _stream;

  ///convert from json string to T for structure data
  T Function(String)? jsonConverter;

  ///constructure
  Subscription(this.sid, this.subject, this._client,
      {this.queueGroup, this.jsonConverter}) {
    _controller = StreamController<Message<T>>();
    _stream = _controller.stream.asBroadcastStream();
  }

  ///
  void unSub() {
    _client.unSub(this);
  }

  ///Stream output when server publish message
  Stream<Message<T>> get stream => _stream;

  ///sink messat to listener
  void add(Message raw) {
    if (_controller.isClosed) return;
    _controller.sink.add(Message<T>(
      raw.subject,
      raw.sid,
      raw.byte,
      _client,
      replyTo: raw.replyTo,
      jsonConverter: jsonConverter,
    ));
  }

  ///close the stream
  Future close() async {
    await _controller.close();
  }
}
