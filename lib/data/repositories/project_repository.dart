import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../domain/models/project_model.dart';

class ProjectRepository {
  Future<void> saveProject(ProjectModel project) async {
    final String jsonString = jsonEncode(project.toJson());
    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

    await FilePicker.saveFile(
      fileName: 'my_project.akso',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['akso'],
      dialogTitle: 'Сохранить проект',
    );
  }

  Future<ProjectModel?> loadProject() async {
    final PlatformFile? result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['akso'],
      dialogTitle: 'Загрузить проект',
    );

    if (result != null) {
      final bytes = await result.readAsBytes();
      final jsonString = utf8.decode(bytes);
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return ProjectModel.fromJson(jsonMap);
    }
    return null;
  }
}
