import 'dart:async';
import 'dart:typed_data';

class SecurityContext {}

class Socket extends Stream<Uint8List> {
  static Future<Socket> connect(dynamic host, int port, {Duration? timeout}) {
    throw UnsupportedError('TCP sockets are not supported on the web.');
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    throw UnsupportedError('TCP sockets are not supported on the web.');
  }

  void add(List<int> data) {}
  Future<void> close() async {}
}

class SecureSocket extends Stream<Uint8List> {
  static Future<SecureSocket> secure(dynamic socket,
      {dynamic context, bool Function(dynamic)? onBadCertificate}) {
    throw UnsupportedError('Secure TCP sockets are not supported on the web.');
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    throw UnsupportedError('Secure TCP sockets are not supported on the web.');
  }

  void add(List<int> data) {}
  Future<void> close() async {}
}

class TlsException {
  final String message;
  TlsException([this.message = '']);
}

class File {
  final String path;
  File(this.path);

  Future<bool> exists() async {
    return false;
  }

  Future<String> readAsString() async {
    throw UnsupportedError('File operations are not supported on the web.');
  }
}
