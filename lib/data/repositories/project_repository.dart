import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../domain/models/project_model.dart';

abstract class IProjectRepository {
  Future<String?> saveProject(ProjectModel project, {String? targetPath});
  Future<({ProjectModel project, String filePath})?> loadProject({String? filePath});
  Future<void> shareProjectFile(ProjectModel project, {String? customFileName});
}

class ProjectRepository implements IProjectRepository {
  @override
  Future<String?> saveProject(ProjectModel project, {String? targetPath}) async {
    final String jsonString = jsonEncode(project.toJson());
    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

    // Прямая запись по указанному пути (Ctrl+S при наличии открытого файла)
    if (targetPath != null && targetPath.isNotEmpty && !kIsWeb) {
      final file = File(targetPath);
      await file.writeAsString(jsonString, flush: true);
      return file.path;
    }

    final defaultName = project.title.trim().isNotEmpty
        ? '${project.title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.akso'
        : 'project.akso';

    final Uri? uri = await FilePicker.saveFile(
      dialogTitle: 'Сохранить проект',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['akso'],
      bytes: bytes,
    );

    if (uri == null) {
      return null;
    }

    String finalPath = uri.scheme == 'file'
        ? uri.toFilePath()
        : (uri.path.isNotEmpty ? uri.path : uri.toString());

    if (!finalPath.toLowerCase().endsWith('.akso')) {
      finalPath = '$finalPath.akso';
    }

    // На Desktop FilePicker.saveFile не сохраняет байты на диск сам — записываем вручную
    if (!kIsWeb) {
      final file = File(finalPath);
      await file.writeAsString(jsonString, flush: true);
    }

    return finalPath;
  }

  @override
  Future<({ProjectModel project, String filePath})?> loadProject({String? filePath}) async {
    if (filePath != null && filePath.isNotEmpty && !kIsWeb) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException('Файл не найден', filePath);
      }
      try {
        final jsonString = await file.readAsString();
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        return (project: ProjectModel.fromJson(jsonMap), filePath: file.path);
      } catch (e) {
        if (e is FileSystemException) rethrow;
        throw const FormatException('Неверный формат файла проекта');
      }
    }

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
        final project = ProjectModel.fromJson(jsonMap);
        return (project: project, filePath: result.path ?? '');
      } catch (e) {
        throw const FormatException('Неверный формат файла проекта');
      }
    }
    return null;
  }

  @override
  Future<void> shareProjectFile(ProjectModel project, {String? customFileName}) async {
    final cleanTitle = project.title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = customFileName ?? (cleanTitle.isNotEmpty ? '$cleanTitle.akso' : 'project.akso');

    final jsonString = jsonEncode(project.toJson());
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await tempFile.writeAsString(jsonString, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tempFile.path)],
        text: 'Проект Akso: ${project.title}',
      ),
    );
  }
}
