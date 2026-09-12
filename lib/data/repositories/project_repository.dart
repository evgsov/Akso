import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/models/project_model.dart';

abstract class IProjectRepository {
  Future<void> saveProject(ProjectModel project);
  Future<ProjectModel?> loadProject();
}

class ProjectRepository implements IProjectRepository {
  @override
  Future<void> saveProject(ProjectModel project) async {
    final String jsonString = jsonEncode(project.toJson());
    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

    await FilePicker.saveFile(
      dialogTitle: 'Сохранить проект',
      fileName: 'my_project.akso',
      type: FileType.custom,
      allowedExtensions: ['akso'],
      bytes: bytes,
    );
  }

  @override
  Future<ProjectModel?> loadProject() async {
    final PlatformFile? result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['akso'],
      dialogTitle: 'Загрузить проект',
    );

    if (result != null) {
      try {
        final Uint8List content = await result.readAsBytes();
        final jsonString = utf8.decode(content);
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        return ProjectModel.fromJson(jsonMap);
      } catch (e) {
        throw const FormatException('Неверный формат файла проекта');
      }
    }
    return null;
  }
}
