/*!
 * Author: Frank Moreno <frankmoreno1993@gmail.com>
 * Copyright(c) 2018 ariot.pe. All rights reserved.
 * MIT Licensed
 */
library nuid;

import 'dart:math' show Random;

class Nuid {
  static const String digits = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static List<int> get binaryDigits => digits.runes.toList();
  static const int base = 36;
  static const int preLen = 12;
  static const int seqLen = 10;
  static const int maxSeq = 3656158440062976; // base^seqLen == 36^10
  static const int minInc = 33;
  static const int maxInc = 333;
  static const int totalLen = preLen + seqLen;

  /// Global [Nuid] instance
  static final Nuid instance = Nuid();

  List<int> _buf;
  int seq;
  int inc;

  /// Makes a copy to keep the `_buf` inmutable
  List<int> get buffer => _buf.toList();

  /// Return the buffer as [String]
  String get current => String.fromCharCodes(_buf);

  /// Create and initialize a [Nuid].
  Nuid() : _buf = List<int>(totalLen) {
    this.reset();
  }

  /// Initializes or reinitializes a nuid with a crypto random prefix,
  /// and pseudo-random sequence and increment.
  void reset() {
    _setPre();
    _initSeqAndInc();
    _fillSeq();
  }

  /// Initializes the pseudo randmon sequence number and the increment range.
  void _initSeqAndInc() {
    final rng = Random();
    seq = (rng.nextDouble() * maxSeq).floor();
    inc = rng.nextInt(maxInc - minInc) + minInc;
  }

  /// Sets the prefix from crypto random bytes. Converts to base36.
  void _setPre() {
    final rs = Random.secure();
    for (int i = 0; i < preLen; i++) {
      final di = rs.nextInt(21701) % base;
      _buf[i] = digits.codeUnitAt(di);
    }
  }

  /// Fills the sequence part of the nuid as base36 from `seq`.
  void _fillSeq() {
    var n = this.seq;
    for (var i = totalLen - 1; i >= preLen; i--) {
      _buf[i] = digits.codeUnitAt(n % base);
      n = (n / base).floor();
    }
  }

  /// Returns the next [Nuid]
  String next() {
    _next();
    return current;
  }

  /// Returns the next [Nuid] as a [List<int>]
  List<int> nextBytes() {
    _next();
    return buffer;
  }

  void _next() {
    seq += inc;
    if (seq > maxSeq) {
      _setPre();
      _initSeqAndInc();
    }
    _fillSeq();
  }
}
