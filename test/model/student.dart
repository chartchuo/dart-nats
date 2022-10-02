class Student {
  String id;
  String name;
  int score;

  Student(this.id, this.name, this.score);

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        json['id'] as String,
        json['name'] as String,
        json['score'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'score': score,
      };
}
