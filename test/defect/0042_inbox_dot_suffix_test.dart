import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

void main() {
  group('Defect #42: Inbox Dot Suffix in NATS WS Client', () {
    test('newInbox appends dot when not present', () {
      final inboxDefault = newInbox();
      expect(inboxDefault, startsWith('_INBOX.'));

      final inboxCustom = newInbox(inboxPrefix: 'custom');
      expect(inboxCustom, startsWith('custom.'));
    });

    test('newInbox does not append extra dot when already present', () {
      final inboxWithDot = newInbox(inboxPrefix: '_INBOX.');
      expect(inboxWithDot, startsWith('_INBOX.'));
      expect(inboxWithDot.substring('_INBOX.'.length), isNot(startsWith('.')));

      final inboxCustomWithDot = newInbox(inboxPrefix: 'custom.');
      expect(inboxCustomWithDot, startsWith('custom.'));
      expect(inboxCustomWithDot.substring('custom.'.length),
          isNot(startsWith('.')));
    });
  });
}
