import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart';
import 'package:test/test.dart';

import 'model/student.dart';

void main() {
  group('all', () {
    test('string to string', () async {
      var client = Client();

      await client.connect(Uri.parse('nats://localhost:4222'),
          retryInterval: 1);
      var sub = client.sub<String>('subject1', jsonConverter: string2string);
      client.pub('subject1', Uint8List.fromList('message1'.codeUnits));
      var msg = await sub.stream.first;
      await client.close();
      expect(msg.data, equals('message1'));
    });

    test('sub', () async {
      var client = Client();
      await client.connect(Uri.parse('nats://localhost:4222'),
          retryInterval: 1);
      var sub = client.sub<Student>('subject1', jsonConverter: josn2Student);
      var student = Student(id: 'id', name: 'name', score: 1);
      client.pubString('subject1', jsonEncode(student.toJson()));
      var msg = await sub.stream.first;
      await client.close();
      expect(msg.data.id, student.id);
      expect(msg.data.name, student.name);
      expect(msg.data.score, student.score);
    });
  });
}

String string2string(String input) {
  return input;
}

Student josn2Student(String json) {
  var map = jsonDecode(json);
  return Student.fromJson(map);
}
