import 'dart:io';

void main() {
  int count = 0;
  final dir = Directory('e:/FlutterProjects/focus_mate/lib');
  for (var entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = entity.readAsStringSync();
      final newContent = content.replaceAllMapped(
        RegExp(r'\.withOpacity\((.*?)\)'),
        (match) => '.withValues(alpha: ${match.group(1)})',
      );
      if (content != newContent) {
        entity.writeAsStringSync(newContent);
        count++;
      }
    }
  }
  print('Modifications applied. Count: $count');
}
