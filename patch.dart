import 'dart:io';

void main() {
  final file = File('lib/data/dxf/dxf_writer.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceAll(r"'  0\nLAYER\n  2\n", r"'  0\nLAYER\n  2\n");
  content = content.replaceAll(r"'  0\nLINE\n  8\n", r"'  0\nLINE\n  8\n");
  content = content.replaceAll(r"'  0\nTEXT\n  8\n", r"'  0\nTEXT\n  8\n");
  content = content.replaceAll(r"'  1\n", r"'  1\n");
  content = content.replaceAll(r"'  0\nCIRCLE\n  8\n", r"'  0\nCIRCLE\n  8\n");
  
  file.writeAsStringSync(content);
}
