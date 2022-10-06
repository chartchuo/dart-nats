import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:dart_nats/src/common.dart';

/// PrefixByteSeed is the version byte used for encoded NATS Seeds
const PrefixByteSeed = 18 << 3; // Base32-encodes to 'S...'

/// PrefixBytePrivate is the version byte used for encoded NATS Private keys
const PrefixBytePrivate = 15 << 3; // Base32-encodes to 'P...'

/// PrefixByteServer is the version byte used for encoded NATS Servers
const PrefixByteServer = 13 << 3; // Base32-encodes to 'N...'

/// PrefixByteCluster is the version byte used for encoded NATS Clusters
const PrefixByteCluster = 2 << 3; // Base32-encodes to 'C...'

/// PrefixByteOperator is the version byte used for encoded NATS Operators
const PrefixByteOperator = 14 << 3; // Base32-encodes to 'O...'

/// PrefixByteAccount is the version byte used for encoded NATS Accounts
const PrefixByteAccount = 0; // Base32-encodes to 'A...'

/// PrefixByteUser is the version byte used for encoded NATS Users
const PrefixByteUser = 20 << 3; // Base32-encodes to 'U...'

/// PrefixByteUnknown is for unknown prefixes.
const PrefixByteUnknown = 23 << 3; // Base32-encodes to 'X...'

///Nkeys
class Nkeys {
  /// key pair
  SimpleKeyPair keyPair;

  /// seed string
  Uint8List? rawSeed;

  /// prefixByte
  int prefixByte;

  ///create nkeys by keypair
  Nkeys(this.prefixByte, this.keyPair, {this.rawSeed}) {
    if (!_checkValidPrefixByte(prefixByte)) {
      throw NkeysException('invalid prefix byte $prefixByte');
    }
  }

  /// generate new nkeys
  static Future<Nkeys> newNkeys(int prefixByte) async {
    var ed = DartEd25519();
    var kp = await ed.newKeyPair();
    return Nkeys(prefixByte, kp);
  }

  /// new nkeys from seed
  static Future<Nkeys> fromSeed(String seed) async {
    var raw = base32.decode(seed);

    // Need to do the reverse here to get back to internal representation.
    var b1 = raw[0] & 248; // 248 = 11111000
    var b2 = ((raw[0] & 7) << 5) | ((raw[1] & 248) >> 3); // 7 = 00000111

    if (b1 != PrefixByteSeed) {
      throw Exception(NkeysException('not seed prefix byte'));
    }
    if (_checkValidPublicPrefixByte(b2) == PrefixByteUnknown) {
      throw Exception(NkeysException('not public prefix byte'));
    }

    var rawSeed = raw.sublist(2, 34);
    var ed = DartEd25519();
    var kp = await ed.newKeyPairFromSeed(rawSeed);

    return Nkeys(b2, kp, rawSeed: rawSeed);
  }

  /// get public key
  String get seed {
    if (rawSeed == null) throw NatsException('no seed');
    return _encodeSeed(prefixByte, rawSeed!);
  }

  /// get public key
  // Future<String> publicKey() async {
  //   var pub = await keyPair.extractPublicKey();
  //   var bytes = <int>[prefixByte];
  //   bytes.addAll(pub.bytes);
  //   return _encode(prefixByte, bytes);
  // }

  /// get private key
  // Future<String> privateKey() async {
  //   var pri = await keyPair.extractPrivateKeyBytes();
  //   var bytes = <int>[prefixByte];
  //   bytes.addAll(pri);
  //   return _encode(PrefixBytePrivate, bytes);
  // }

  /// Sign message
  Future<Signature> sign(List<int> message) {
    var ed = DartEd25519();
    return ed.sign(message, keyPair: keyPair);
  }

  /// verify
  // static Future<bool> verify(List<int> message, Signature signature) {
  //   var ed = DartEd25519();
  //   return ed.verify(message, signature: signature);
  // }
}

// int _prefix(String src) {
//   var b = base32.decode(src);

//   var prefix = b[0];
//   if (_checkValidPrefixByte(prefix)) {
//     return prefix;
//   }

//   // Might be a seed.
//   var b1 = b[0] & 248;
//   if (b1 == PrefixByteSeed) {
//     return PrefixByteSeed;
//   }
//   return PrefixByteUnknown;
// }

int _checkValidPublicPrefixByte(int prefix) {
  switch (prefix) {
    case PrefixByteServer:
    case PrefixByteCluster:
    case PrefixByteOperator:
    case PrefixByteAccount:
    case PrefixByteUser:
      return prefix;
  }
  return PrefixByteUnknown;
}

bool _checkValidPrefixByte(int prefix) {
  switch (prefix) {
    case PrefixByteOperator:
    case PrefixByteServer:
    case PrefixByteCluster:
    case PrefixByteAccount:
    case PrefixByteUser:
    case PrefixByteSeed:
    case PrefixBytePrivate:
      return true;
  }
  return false;
}

// String _encode(int prefix, List<int> src) {
//   if (!_checkValidPrefixByte(prefix)) {
//     throw NkeysException('encode invalid prefix');
//   }

//   var raw = [prefix];
//   raw.addAll(src);

//   // Calculate and write crc16 checksum
//   raw.addAll(_crc16(raw));
//   var bytes = Uint8List.fromList(raw);

//   return _b32Encode(bytes);
// }

Uint8List _crc16(List<int> bytes) {
  // CCITT
  const POLYNOMIAL = 0x1021;
  // XMODEM
  const INIT_VALUE = 0x0000;

  final bitRange = Iterable.generate(8);

  var crc = INIT_VALUE;
  for (var byte in bytes) {
    crc ^= (byte << 8);
    // ignore: unused_local_variable
    for (var i in bitRange) {
      crc = (crc & 0x8000) != 0 ? (crc << 1) ^ POLYNOMIAL : crc << 1;
    }
  }
  var byteData = ByteData(2)..setUint16(0, crc, Endian.little);
  return byteData.buffer.asUint8List();
}

// EncodeSeed will encode a raw key with the prefix and then seed prefix and crc16 and then base32 encoded.
String _encodeSeed(int public, List<int> src) {
  if (_checkValidPublicPrefixByte(public) == PrefixByteUnknown) {
    throw NatsException('Invalid public prefix byte');
  }

  if (src.length != 32) {
    throw NatsException('Invalid src langth');
  }

  // In order to make this human printable for both bytes, we need to do a little
  // bit manipulation to setup for base32 encoding which takes 5 bits at a time.
  var b1 = PrefixByteSeed | ((public) >> 5);
  var b2 = ((public) & 31) << 3; // 31 = 00011111

  var raw = [b1, b2];

  raw.addAll(src);

  // Calculate and write crc16 checksum
  raw.addAll(_crc16(raw));

  return _b32Encode(raw);
}

String _b32Encode(List<int> bytes) {
  var b = Uint8List.fromList(bytes);
  var str = base32.encode(b).replaceAll(RegExp('='), '');
  return str;
}
