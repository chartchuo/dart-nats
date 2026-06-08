import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_nats/dart_nats.dart';

void main() async {
  final client = Client();
  print('Connecting to NATS...');
  await client.connect(Uri.parse('nats://localhost:4222'));
  final js = client.jetStream();

  final bucket = 'debug_bucket_${DateTime.now().millisecondsSinceEpoch}';
  print('Creating KV bucket: $bucket');
  final kv = await js.keyValue(bucket, create: true, storage: 'memory');

  print('Putting setting1 = value1');
  final rev = await kv.putString('setting1', 'value1');
  print('Put sequence: $rev');

  // Let's do the manual request to see what it returns
  final apiSubject = '\$JS.API.STREAM.MSG.GET.KV_$bucket';
  final payload = utf8.encode(jsonEncode({
    'last_by_subj': '\$KV.$bucket.setting1',
  }));

  print('Sending manual request to $apiSubject');
  try {
    final response = await client.request(apiSubject, Uint8List.fromList(payload));
    print('Response: ${response.string}');
  } catch (e, stack) {
    print('Error during manual request: $e');
    print(stack);
  }

  print('Calling kv.get()');
  final entry = await kv.get('setting1');
  print('kv.get() result: $entry');
  if (entry != null) {
    print('entry.string: ${entry.string}');
  }

  // Clean up
  await js.deleteStream('KV_$bucket');
  await client.close();
}
