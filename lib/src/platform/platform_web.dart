import 'dart:async';
import 'dart:typed_data';

/// Security context placeholder for the web platform.
class SecurityContext {}

/// Socket placeholder for the web platform (TCP sockets are unavailable).
class Socket extends Stream<Uint8List> {
  /// Connect to a TCP socket (unsupported on the web).
  static Future<Socket> connect(dynamic host, int port, {Duration? timeout}) {
    throw UnsupportedError('TCP sockets are not supported on the web.');
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    throw UnsupportedError('TCP sockets are not supported on the web.');
  }

  /// Add data to the socket (unsupported on the web).
  void add(List<int> data) {}

  /// Close the socket connection (unsupported on the web).
  Future<void> close() async {}
}

/// Secure socket placeholder for the web platform (TLS sockets are unavailable).
class SecureSocket extends Stream<Uint8List> {
  /// Upgrade an existing socket to a secure TLS socket (unsupported on the web).
  static Future<SecureSocket> secure(dynamic socket,
      {dynamic context, bool Function(dynamic)? onBadCertificate}) {
    throw UnsupportedError('Secure TCP sockets are not supported on the web.');
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    throw UnsupportedError('Secure TCP sockets are not supported on the web.');
  }

  /// Add data to the secure socket (unsupported on the web).
  void add(List<int> data) {}

  /// Close the secure socket (unsupported on the web).
  Future<void> close() async {}
}

/// TLS exception placeholder for the web platform.
class TlsException {
  /// Description of the TLS error.
  final String message;

  /// Create a [TlsException] with an optional [message].
  TlsException([this.message = '']);
}

/// File placeholder for the web platform (file access is unavailable).
class File {
  /// Path the file would point to.
  final String path;

  /// Create a [File] reference for [path] (operations are unsupported on the web).
  File(this.path);

  /// Check if the file exists (unsupported on the web).
  Future<bool> exists() async {
    return false;
  }

  /// Read the entire file as a string (unsupported on the web).
  Future<String> readAsString() async {
    throw UnsupportedError('File operations are not supported on the web.');
  }
}
