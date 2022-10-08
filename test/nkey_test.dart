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
  });
}
