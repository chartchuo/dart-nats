import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

var port = 8084;

void main() {
  group('all', () {
    test('seed', () async {
      var nkeys = Nkeys.fromSeed(
          'SUAKJESHKJ5POJJINJFMCVYAASA7LQTL5ZOMMTYOWRZCM3JRZRS3OIVKZA');
      var s = nkeys.seed;
      expect(s,
          equals('SUAKJESHKJ5POJJINJFMCVYAASA7LQTL5ZOMMTYOWRZCM3JRZRS3OIVKZA'));
    });
    test('public key', () async {
      var nkeys = Nkeys.fromSeed(
          'SUAKJESHKJ5POJJINJFMCVYAASA7LQTL5ZOMMTYOWRZCM3JRZRS3OIVKZA');
      var p = nkeys.publicKey();

      expect(p,
          equals('UBYKMUQEJ7U2KFHB37IUOX6NBTJAWGY6SDO3DFRVOBNXVDUPPOTNWXD5'));
    });
    test('private key', () async {
      var nkeys = Nkeys.fromSeed(
          'SUAKJESHKJ5POJJINJFMCVYAASA7LQTL5ZOMMTYOWRZCM3JRZRS3OIVKZA');
      var p = nkeys.privateKey();

      expect(
          p,
          equals(
              'PCSJER2SPL3SKKDKJLAVOAAEQH24E27OLTDE6DVUOITG2MOMMW3SE4FGKICE72NFCTQ57UKHL7GQZUQLDMPJBXNRSY2XAW32R2HXXJW3A6AQ'));
    });
    test('create', () async {
      var userPK = Nkeys.createUser();
      expect(userPK.publicKey()[0], equals('U'));
      var accountPK = Nkeys.createAccount();
      expect(accountPK.publicKey()[0], equals('A'));
      var operatorPK = Nkeys.createOperator();
      expect(operatorPK.publicKey()[0], equals('O'));
    });
    test('verify', () async {
      var sig = base64Decode(
          'WosANJXgeyxerXFo0twRiMG+/ZjYp1K/46bFeFax705yFTCTjM18jWl01gGYk4KKbadiHd+hP3WgUQ2iLZUAAA==');
      var nonce = 'DhXdTMAeiHhLDig';
      var seed = 'SUACSSL3UAHUDXKFSNVUZRF5UHPMWZ6BFDTJ7M6USDXIEDNPPQYYYCU3VY';
      var nkeys = Nkeys.fromSeed(seed);

      var result =
          Nkeys.verify(nkeys.publicKey(), utf8.encode(nonce) as Uint8List, sig);
      expect(result, equals(true));
    });
  });
}
