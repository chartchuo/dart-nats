import 'dart:typed_data';
import 'dart:math';

const _inboxPrefix = '_INBOX.';
const _digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _base = 62;
const _maxSeq = 839299365868340224; // base^seqLen == 62^10;
const _minInc = 33;
const _maxInc = 333;
const _preLen = 12;
const _seqLen = 10;
const _totalLen = _preLen + _seqLen;

final _nuid = Nuid();

///generate inbox
String newInbox({bool secure = true}) {
  if (secure) {
    _nuid.randomizePrefix();
    _nuid.resetSequential();
  }
  return _inboxPrefix + _nuid.next();
}

///nuid port from go nats
class Nuid {
  static Uint8List _pre; // check initial
  static int _seq;
  static int _inc;
  static Random _rng;

  ///constructure
  Nuid() {
    _pre = Uint8List(_preLen);
    _rng = Random.secure();
    randomizePrefix();
    resetSequential();
  }

  ///generate next nuid
  String next() {
    _seq += _inc;
    if (_seq >= _maxSeq) {
      randomizePrefix();
      resetSequential();
    }
    var s = _seq;
    var b = _pre + Uint8List(_seqLen);
    for (var i = _totalLen, l = s; i > _preLen; l = l ~/ _base) {
      i -= 1;
      b[i] = _digits.codeUnits[l % _base];
    }
    return String.fromCharCodes(b);
  }

  ///reset sequential
  void resetSequential() {
    Random();
    _seq = _rng.nextInt(1 << 31) << 32 | _rng.nextInt(1 << 32);
    if (_seq > _maxSeq) {
      _seq %= _maxSeq;
    }
    _inc = _minInc + _rng.nextInt(_maxInc - _minInc);
  }

  ///random new prefix
  void randomizePrefix() {
    for (var i = 0; i < _preLen; i++) {
      var n = _rng.nextInt(255) % _base;
      _pre[i] = _digits.codeUnits[n];
    }
  }
}
