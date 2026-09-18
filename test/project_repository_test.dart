import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/repositories/project_repository.dart';
import 'package:akso/domain/models/project_model.dart';

void main() {
  group('ProjectRepository Direct File I/O Tests', () {
    late Directory tempDir;
    late ProjectRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('akso_repo_test_');
      repo = ProjectRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveProject with explicit targetPath writes file directly and returns path', () async {
      final project = ProjectModel(
        id: 'p_direct',
        title: 'Прямое сохранение',
        projectCode: 'ПР-01',
      );

      final filePath = '${tempDir.path}${Platform.pathSeparator}direct.akso';
      final savedPath = await repo.saveProject(project, targetPath: filePath);

      expect(savedPath, equals(filePath));
      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      expect(content, contains('Прямое сохранение'));
      expect(content, contains('ПР-01'));
    });

    test('loadProject with explicit filePath loads and parses project correctly', () async {
      final project = ProjectModel(
        id: 'p_load',
        title: 'Загружаемый проект',
        projectCode: 'ЗГ-99',
        notes: 'Важные примечания',
      );

      final filePath = '${tempDir.path}${Platform.pathSeparator}test_load.akso';
      await repo.saveProject(project, targetPath: filePath);

      final result = await repo.loadProject(filePath: filePath);
      expect(result, isNotNull);
      expect(result!.filePath, equals(filePath));
      expect(result.project.id, equals('p_load'));
      expect(result.project.title, equals('Загружаемый проект'));
      expect(result.project.projectCode, equals('ЗГ-99'));
      expect(result.project.notes, equals('Важные примечания'));
    });

    test('loadProject throws FileSystemException when explicit file does not exist', () async {
      final nonExistent = '${tempDir.path}${Platform.pathSeparator}missing.akso';
      expect(
        () async => await repo.loadProject(filePath: nonExistent),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('loadProject throws FormatException on invalid file contents', () async {
      final corruptFile = File('${tempDir.path}${Platform.pathSeparator}corrupt.akso');
      await corruptFile.writeAsString('NOT VALID JSON CONTENT');

      expect(
        () async => await repo.loadProject(filePath: corruptFile.path),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
