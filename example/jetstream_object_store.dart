import 'dart:typed_data';
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

  final bucketName = 'example_files';
  final streamName = 'OBJ_$bucketName';

  try {
    // 3. Create or bind to an Object Store bucket
    print('Creating Object Store bucket "$bucketName" with memory storage...');
    final os = await js.objectStore(bucketName, create: true, storage: 'memory');
    print('Object Store bucket initialized.');

    // 4. Store a text file
    print('\n--- Put (String) Operation ---');
    final stringInfo = await os.putString(
      'hello.txt',
      'Hello, NATS JetStream Object Store from Dart!',
      description: 'A simple text file',
    );
    print('Stored "hello.txt":');
    print('  Size: ${stringInfo.size} bytes');
    print('  Digest: ${stringInfo.digest}');
    print('  Chunks: ${stringInfo.chunks}');

    // 5. Store larger binary data (chunked automatic handling)
    print('\n--- Put (Binary Chunked) Operation ---');
    // Generate a 150 KiB byte array (which exceeds the default 128 KiB chunk size)
    final binarySize = 150 * 1024;
    final binaryData = Uint8List(binarySize);
    for (var i = 0; i < binarySize; i++) {
      binaryData[i] = i % 256;
    }
    
    print('Storing binary file "data.bin" of size 150 KiB (should be split into multiple chunks)...');
    final binInfo = await os.put(
      'data.bin',
      binaryData,
      description: 'Larger chunked binary data',
    );
    print('Stored "data.bin":');
    print('  Size: ${binInfo.size} bytes');
    print('  Digest: ${binInfo.digest}');
    print('  Chunks: ${binInfo.chunks}'); // Should be 2 chunks

    // 6. Retrieve string contents of a file
    print('\n--- Get (String) Operation ---');
    final textContent = await os.getString('hello.txt');
    print('Retrieved "hello.txt" content: "$textContent"');

    // 7. Retrieve binary contents of a file and verify SHA-256 integrity
    print('\n--- Get (Binary) Operation ---');
    final retrievedData = await os.get('data.bin');
    if (retrievedData != null) {
      print('Retrieved "data.bin" size: ${retrievedData.length} bytes');
      var matched = true;
      for (var i = 0; i < binarySize; i++) {
        if (retrievedData[i] != binaryData[i]) {
          matched = false;
          break;
        }
      }
      print('Retrieved binary data matches original: $matched');
    } else {
      print('Failed to retrieve "data.bin".');
    }

    // 8. List all files in the Object Store
    print('\n--- List Objects ---');
    final objects = await os.list();
    print('Found ${objects.length} active object(s) in store:');
    for (final obj in objects) {
      print('  - Name: ${obj.name}');
      print('    Size: ${obj.size} bytes');
      print('    Description: "${obj.description}"');
      print('    Modified Time: ${obj.mtime}');
    }

    // 9. Delete a file and verify it's no longer accessible
    print('\n--- Delete Operation ---');
    print('Deleting "hello.txt"...');
    final delOk = await os.delete('hello.txt');
    print('Delete request processed: $delOk');

    final infoAfterDel = await os.getInfo('hello.txt');
    if (infoAfterDel != null) {
      print('Checking deleted metadata -> Deleted flag status: ${infoAfterDel.deleted}');
    }

    final dataAfterDel = await os.get('hello.txt');
    print('Attempting to fetch deleted "hello.txt" -> Data is null: ${dataAfterDel == null}');

  } catch (e) {
    print('Error: $e');
  } finally {
    // 10. Clean up backing stream and close connection
    print('\nCleaning up Object Store bucket backing stream...');
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
