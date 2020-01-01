///subscription model
import 'dart:async';

import 'message.dart';

/// subscription class
class Subscription {
  ///subscriber id (audo generate)
  final int sid;

  ///subject and queuegroup of this subscription
  final String subject, queueGroup;

  final _controller = StreamController<Message>();

  ///constructure
  Subscription(this.sid, this.subject, {this.queueGroup});

  ///Stream output when server publish message
  Stream<Message> get stream => _controller.stream;

  ///sink messat to listener
  void add(Message msg) {
    _controller.sink.add(msg);
  }

  ///close the stream
  void close() {
    _controller.close();
  }
}
