import 'dart:async';
import 'dart:typed_data';

abstract class SecurityContext {}

abstract class Socket extends Stream<Uint8List> {
  static Future<Socket> connect(dynamic host, int port, {Duration? timeout}) {
    throw UnsupportedError('Sockets are not supported on this platform.');
  }

  void add(List<int> data);
  Future<void> close();
}

abstract class SecureSocket extends Stream<Uint8List> {
  static Future<SecureSocket> secure(dynamic socket,
      {dynamic context, bool Function(dynamic)? onBadCertificate}) {
    throw UnsupportedError(
        'Secure sockets are not supported on this platform.');
  }

  void add(List<int> data);
  Future<void> close();
}

abstract class TlsException {
  final String message;
  TlsException([this.message = '']);
}

abstract class File {
  factory File(String path) {
    throw UnsupportedError(
        'File operations are not supported on this platform.');
  }
  Future<bool> exists();
  Future<String> readAsString();
}
