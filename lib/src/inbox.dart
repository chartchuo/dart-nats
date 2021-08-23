import 'dart:typed_data';
import 'dart:math';

var _nuid = Nuid();

///generate inbox
String newInbox({bool secure = true}) {
  const _inboxPrefix = '_INBOX.';
  if (secure) {
    _nuid = Nuid();
  }
  return _inboxPrefix + _nuid.next();
}

///nuid port from go nats
class Nuid {
  static const _digits =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  static const _base = 62;
  static const _maxSeq = 839299365868340224; // base^seqLen == 62^10;
  static const _minInc = 33;
  static const _maxInc = 333;
  static const _preLen = 12;
  static const _seqLen = 10;
  static const _totalLen = _preLen + _seqLen;

  late Uint8List _pre; // check initial
  late int _seq;
  late int _inc;

  ///constructure
  Nuid() {
    randomizePrefix();
    resetSequential();
  }

  ///generate next nuid
  String next() {
    _seq = _seq + _inc;
    if (_seq >= _maxSeq) {
      randomizePrefix();
      resetSequential();
    }
    var s = _seq;
    var b = List<int>.from(_pre);
    b.addAll(Uint8List(_seqLen));
    for (int? i = _totalLen, l = s; i! > _preLen; l = l ~/ _base) {
      i -= 1;
      b[i] = _digits.codeUnits[l! % _base];
    }
    return String.fromCharCodes(b);
  }

  ///reset sequential
  void resetSequential() {
    Random();
    var _rng = Random.secure();

    _seq = _rng.nextInt(1 << 31) << 32 | _rng.nextInt(1 << 31);
    if (_seq > _maxSeq) {
      _seq = _seq % _maxSeq;
    }
    _inc = _minInc + _rng.nextInt(_maxInc - _minInc);
  }

  ///random new prefix
  void randomizePrefix() {
    _pre = Uint8List(_preLen);
    var _rng = Random.secure();
    for (var i = 0; i < _preLen; i++) {
      var n = _rng.nextInt(255) % _base;
      _pre[i] = _digits.codeUnits[n];
    }
  }
}
