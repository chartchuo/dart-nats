import 'dart:typed_data';
import 'dart:math';

/// inbox port from go nats
class Inbox {
  static const _inboxPrefix = '_INBOX.';

  static final _nuid = Nuid();

  ///generate inbox
  static String next() {
    return _inboxPrefix + _nuid.next();
  }
}

///nuid port from go nats
class Nuid {
  static const _digits =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  static const _base = 62;

  Uint8List _pre; // check initial
  int _seq;
  int _inc;
  // static const _maxSeq = 839299365868340224;
  // 4294967296
  static const _maxSeq = 4294967296;
  static const _minInc = 33;
  static const _maxInc = 333;
  static const _preLen = 12;
  static const _seqLen = 10;
  static const _totalLen = _preLen + _seqLen;
  static Random _rng;

  ///constructure
  Nuid() {
    _pre = Uint8List(_preLen);
    _rng = Random.secure();
    randomizePrefix();
    resetSequential();
  }

  ///
  String next() {
    _seq += _inc;
    if (_seq >= _maxSeq) {
      randomizePrefix();
      resetSequential();
    }
    var s = _seq;
    var b = _pre + Uint8List(_seqLen);
    for (var i = _totalLen, l = s; i > _preLen; i = i ~/ _base) {
      i -= 1;
      b[i] = _digits.codeUnits[l % _base];
    }
    return String.fromCharCodes(b);
  }

  ///
  void resetSequential() {
    Random();
    _seq = _rng.nextInt(_maxSeq);
    _inc = _minInc + _rng.nextInt(_maxInc - _minInc);
  }

  ///
  void randomizePrefix() {
    for (var i = 0; i < _preLen; i++) {
      var n = _rng.nextInt(255) % _base;
      _pre[i] = _digits.codeUnits[n];
    }
  }
}
