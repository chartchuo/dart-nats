import 'package:dart_nats/dart_nats.dart';

void main() async {
  // 1. Create a client and connect to the local NATS server.
  // Make sure NATS is running with JetStream enabled (e.g. nats-server -js)
  final client = Client();
  print('Connecting to NATS...');
  await client.connect(Uri.parse('nats://localhost:4222'));
  print('Connected!');

  // 2. Initialize JetStream context
  final js = client.jetStream();

  final bucketName = 'example_settings';
  final streamName = 'KV_$bucketName';

  try {
    // 3. Create or bind to a Key-Value bucket
    print('Creating Key-Value bucket "$bucketName" with memory storage...');
    final kv = await js.keyValue(bucketName, create: true, storage: 'memory');
    print('Key-Value bucket initialized.');

    // 4. Put string values associated with keys
    print('\n--- Put Operations ---');
    final rev1 = await kv.putString('config.theme', 'dark-mode');
    print('Put "config.theme" -> value: "dark-mode", Revision: $rev1');

    final rev2 = await kv.putString('config.volume', '80');
    print('Put "config.volume" -> value: "80", Revision: $rev2');

    // 5. Get the latest value associated with a key
    print('\n--- Get Operations ---');
    final entry = await kv.get('config.theme');
    if (entry != null) {
      print('Retrieved "config.theme":');
      print('  Key: ${entry.key}');
      print('  Value: "${entry.string}"');
      print('  Revision: ${entry.revision}');
      print('  Created: ${entry.created}');
    } else {
      print('"config.theme" not found.');
    }

    // 6. Watch a specific key for real-time updates
    print('\n--- Watching "config.theme" ---');
    final watchStream = kv.watch(key: 'config.theme', includeHistory: true);
    final subscription = watchStream.listen((update) {
      if (update != null) {
        print(
            'Watch Update -> key: ${update.key}, value: "${update.string}", Revision: ${update.revision}');
      } else {
        print('Watch Update -> key: config.theme was DELETED or PURGED.');
      }
    });

    // Allow the subscriber to bind and receive initial value
    await Future.delayed(const Duration(milliseconds: 200));

    // Update the key to trigger a watch event
    print('\nUpdating "config.theme"...');
    final rev3 = await kv.putString('config.theme', 'light-mode');
    print('Put "config.theme" -> value: "light-mode", Revision: $rev3');

    // Wait to let watch event propagate
    await Future.delayed(const Duration(milliseconds: 200));

    // 7. Delete a key
    print('\n--- Delete Operation ---');
    print('Deleting "config.theme" (soft delete, puts a tombstone)...');
    final deleteOk = await kv.delete('config.theme');
    print('Delete successful: $deleteOk');

    // Wait to let delete event propagate to the watch listener
    await Future.delayed(const Duration(milliseconds: 200));

    // Attempting to get a deleted key returns null
    final deletedEntry = await kv.get('config.theme');
    print(
        'Getting deleted "config.theme" -> entry is null: ${deletedEntry == null}');

    // Clean up the watcher subscription
    await subscription.cancel();
    print('Cancelled key watch subscription.');

    // 8. Purge a key (deletes historical versions as well)
    print('\n--- Purge Operation ---');
    print('Purging "config.volume"...');
    final purgeOk = await kv.purge('config.volume');
    print('Purge successful: $purgeOk');

    final purgedEntry = await kv.get('config.volume');
    print(
        'Getting purged "config.volume" -> entry is null: ${purgedEntry == null}');
  } catch (e) {
    print('Error: $e');
  } finally {
    // 9. Clean up backing stream and close client
    print('\nCleaning up Key-Value bucket backing stream...');
    try {
      await js.deleteStream(streamName);
      print('Backup stream "$streamName" deleted.');
    } catch (e) {
      print('Failed to delete stream: $e');
    }

    await client.close();
    print('Connection closed.');
  }
}
