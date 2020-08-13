import 'dart:async';

import 'client.dart';

/// status connection class
class Healthcheck {

  /// current connection status
  Status status;

  final _controller = StreamController<Status>();

  Stream<Status> _stream;

  ///constructor
  Healthcheck(this.status) {
    _stream = _controller.stream.asBroadcastStream();
  }

  ///Stream output when status is updated
  Stream<Status> get stream => _stream;

  ///add status to stream
  void add(Status status) {
    this.status = status;
    _controller.add(status);
  }

  ///close the stream
  void close() {
    _controller.close();
  }
}
