import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/repositories/project_repository.dart';
import 'package:akso/data/repositories/recent_projects_manager.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/ui/canvas/input_controller.dart';

class TestProjectRepository implements IProjectRepository {
  ProjectModel? savedProject;
  String? lastTargetPath;
  ProjectModel? projectToLoad;
  String? loadPath;
  bool returnNullOnSave = false;

  @override
  Future<String?> saveProject(ProjectModel project, {String? targetPath}) async {
    if (returnNullOnSave) return null;
    savedProject = project;
    lastTargetPath = targetPath;
    return targetPath ?? 'C:/projects/saved_project.akso';
  }

  @override
  Future<({ProjectModel project, String filePath})?> loadProject({String? filePath}) async {
    if (projectToLoad != null) {
      return (project: projectToLoad!, filePath: filePath ?? 'C:/projects/loaded.akso');
    }
    return null;
  }

  @override
  Future<void> shareProjectFile(ProjectModel project, {String? customFileName}) async {}
}

void main() {
  group('PipingInputController Project Lifecycle Integration Tests', () {
    late Directory tempDir;
    late RecentProjectsManager recentManager;
    late TestProjectRepository repo;
    late PipingInputController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('akso_ctrl_test_');
      recentManager = RecentProjectsManager(
        getStorageDir: () async => tempDir,
      );
      repo = TestProjectRepository();
      controller = PipingInputController(
        projectRepository: repo,
        recentProjectsManager: recentManager,
      );
    });

    tearDown(() async {
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initial state has no file path and hasUnsavedChanges is false', () {
      expect(controller.currentFilePath, isNull);
      expect(controller.hasUnsavedChanges, isFalse);
    });

    test('mutating network marks hasUnsavedChanges as true', () {
      expect(controller.hasUnsavedChanges, isFalse);

      controller.network.nodes['n1'] = const Node3D(id: 'n1', x: 100, y: 0, z: 0);
      controller.markDirty();

      expect(controller.hasUnsavedChanges, isTrue);
    });

    test('saveProject on unsaved project invokes saveAs behavior, sets path, and adds to recents', () async {
      controller.currentProject = controller.currentProject.copyWith(
        title: 'Тест Сохранения',
        projectCode: 'ТХ-01',
      );
      controller.markDirty();
      expect(controller.hasUnsavedChanges, isTrue);

      final success = await controller.saveProject();
      expect(success, isTrue);
      expect(controller.currentFilePath, equals('C:/projects/saved_project.akso'));
      expect(controller.hasUnsavedChanges, isFalse);

      final recents = await recentManager.getRecentProjects();
      expect(recents, isNotEmpty);
      expect(recents.first.filePath, equals('C:/projects/saved_project.akso'));
      expect(recents.first.title, equals('Тест Сохранения'));
    });

    test('saveProject on existing project uses currentFilePath without dialog prompt', () async {
      controller.currentFilePath = 'C:/work/existing.akso';
      controller.markDirty();

      final success = await controller.saveProject();
      expect(success, isTrue);
      expect(repo.lastTargetPath, equals('C:/work/existing.akso'));
      expect(controller.currentFilePath, equals('C:/work/existing.akso'));
      expect(controller.hasUnsavedChanges, isFalse);
    });

    test('openProject loads project, updates network, resets dirty flag and registers in recents', () async {
      final loadedNetwork = PipingNetwork();
      loadedNetwork.nodes['loaded_node'] = const Node3D(id: 'loaded_node', x: 500, y: 500, z: 100);

      repo.projectToLoad = ProjectModel(
        id: 'p_loaded',
        title: 'Загруженный чертеж',
        projectCode: 'ОВ-10',
        network: loadedNetwork,
      );

      final ok = await controller.openProject(filePath: 'C:/docs/blueprint.akso');
      expect(ok, isTrue);
      expect(controller.currentProject.id, equals('p_loaded'));
      expect(controller.currentProject.title, equals('Загруженный чертеж'));
      expect(controller.currentProject.projectCode, equals('ОВ-10'));
      expect(controller.network.nodes.containsKey('loaded_node'), isTrue);
      expect(controller.currentFilePath, equals('C:/docs/blueprint.akso'));
      expect(controller.hasUnsavedChanges, isFalse);

      final recents = await recentManager.getRecentProjects();
      expect(recents.first.filePath, equals('C:/docs/blueprint.akso'));
      expect(recents.first.title, equals('Загруженный чертеж'));
    });

    test('newProject resets network, title, path, and dirty flag', () async {
      controller.currentFilePath = 'C:/some/file.akso';
      controller.markDirty();

      controller.newProject(force: true);

      expect(controller.currentFilePath, isNull);
      expect(controller.hasUnsavedChanges, isFalse);
      expect(controller.currentProject.title, equals('Новый проект'));
      expect(controller.network.nodes, isEmpty);
    });

    test('updateProjectMetadata updates fields and sets hasUnsavedChanges', () {
      expect(controller.hasUnsavedChanges, isFalse);

      controller.updateProjectMetadata(
        title: 'Новое имя',
        projectCode: 'ШИФР-1',
        objectAddress: 'Москва',
        engineerName: 'Сидоров',
        notes: 'Срочно в печать',
      );

      expect(controller.currentProject.title, equals('Новое имя'));
      expect(controller.currentProject.projectCode, equals('ШИФР-1'));
      expect(controller.currentProject.objectAddress, equals('Москва'));
      expect(controller.currentProject.engineerName, equals('Сидоров'));
      expect(controller.currentProject.notes, equals('Срочно в печать'));
      expect(controller.hasUnsavedChanges, isTrue);
    });
  });
}
