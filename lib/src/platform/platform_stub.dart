import 'dart:async';
import 'dart:typed_data';

/// Abstract security context placeholder for platform‑specific implementations.
abstract class SecurityContext {}

/// Abstract socket class placeholder for platform‑specific implementations.
abstract class Socket extends Stream<Uint8List> {
    /// Connect to a TCP socket (unsupported on this platform).
  static Future<Socket> connect(dynamic host, int port, {Duration? timeout}) {
    throw UnsupportedError('Sockets are not supported on this platform.');
  }

    /// Add data to the socket (unsupported on this platform).
  void add(List<int> data);
    /// Close the socket connection (unsupported on this platform).
  Future<void> close();
}

/// Abstract secure socket class placeholder for platform‑specific implementations.
abstract class SecureSocket extends Stream<Uint8List> {
    /// Upgrade an existing socket to a secure TLS socket (unsupported on this platform).
  static Future<SecureSocket> secure(dynamic socket,
      {dynamic context, bool Function(dynamic)? onBadCertificate}) {
    throw UnsupportedError(
        'Secure sockets are not supported on this platform.');
  }

    /// Add data to the secure socket (unsupported on this platform).
  void add(List<int> data);
    /// Close the secure socket (unsupported on this platform).
  Future<void> close();
}

/// Abstract TLS exception placeholder for platform‑specific implementations.
abstract class TlsException {
  final String message;
  TlsException([this.message = '']);
}

/// Abstract file class placeholder for platform‑specific implementations.
abstract class File {
    /// Factory constructor to create a file instance (unsupported on this platform).
  factory File(String path) {
    throw UnsupportedError(
        'File operations are not supported on this platform.');
  }
    /// Check if the file exists (unsupported on this platform).
  Future<bool> exists();
    /// Read the entire file as a string (unsupported on this platform).
  Future<String> readAsString();
}
