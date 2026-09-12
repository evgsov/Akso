import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/repositories/project_repository.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/ui/canvas/input_controller.dart';

class FakeProjectRepository extends ProjectRepository {
  ProjectModel? lastSavedProject;
  ProjectModel? projectToLoad;
  int saveCount = 0;
  int loadCount = 0;

  @override
  Future<void> saveProject(ProjectModel project) async {
    lastSavedProject = project;
    saveCount++;
  }

  @override
  Future<ProjectModel?> loadProject() async {
    loadCount++;
    return projectToLoad;
  }
}

void main() {
  group('PipingInputController Persistent Project Identity Tests', () {
    late FakeProjectRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeProjectRepository();
    });

    test('Initializes currentProject with UUID, title and initial network', () {
      final controller = PipingInputController(projectRepository: fakeRepo);

      expect(controller.currentProject, isNotNull);
      expect(controller.currentProject.id, isNotEmpty);
      expect(controller.currentProject.title, equals('Новый проект'));
      expect(controller.currentProject.network, equals(controller.network));
    });

    test('Preserves currentProject.id across multiple saveProject calls', () async {
      final controller = PipingInputController(projectRepository: fakeRepo);
      final initialId = controller.currentProject.id;

      // First save
      await controller.saveProject();
      expect(fakeRepo.saveCount, equals(1));
      expect(fakeRepo.lastSavedProject?.id, equals(initialId));
      expect(controller.currentProject.id, equals(initialId));

      // Modify network
      controller.network.nodes['n1'] = const Node3D(id: 'n1', x: 100, y: 200, z: 300);

      // Second save
      await controller.saveProject();
      expect(fakeRepo.saveCount, equals(2));
      expect(fakeRepo.lastSavedProject?.id, equals(initialId));
      expect(controller.currentProject.id, equals(initialId));
      expect(fakeRepo.lastSavedProject?.network.nodes.containsKey('n1'), isTrue);
    });

    test('loadProject updates currentProject and subsequent saves keep loaded project id', () async {
      final controller = PipingInputController(projectRepository: fakeRepo);
      final initialId = controller.currentProject.id;

      final loadedNetwork = PipingNetwork();
      loadedNetwork.nodes['loaded_node'] = const Node3D(id: 'loaded_node', x: 500, y: 500, z: 0);

      final loadedProject = ProjectModel(
        id: 'custom-loaded-uuid-999',
        title: 'Загруженный проект ТЭЦ-1',
        network: loadedNetwork,
      );
      fakeRepo.projectToLoad = loadedProject;

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      await controller.loadProject();

      expect(fakeRepo.loadCount, equals(1));
      expect(controller.currentProject.id, equals('custom-loaded-uuid-999'));
      expect(controller.currentProject.id, isNot(equals(initialId)));
      expect(controller.currentProject.title, equals('Загруженный проект ТЭЦ-1'));
      expect(controller.network.nodes.containsKey('loaded_node'), isTrue);
      expect(notified, isTrue);

      // Save again after loading: must retain loaded project ID
      await controller.saveProject();
      expect(fakeRepo.lastSavedProject?.id, equals('custom-loaded-uuid-999'));
      expect(fakeRepo.lastSavedProject?.title, equals('Загруженный проект ТЭЦ-1'));
    });

    test('loadProject returning null does not overwrite currentProject', () async {
      final controller = PipingInputController(projectRepository: fakeRepo);
      final initialId = controller.currentProject.id;
      fakeRepo.projectToLoad = null;

      await controller.loadProject();

      expect(fakeRepo.loadCount, equals(1));
      expect(controller.currentProject.id, equals(initialId));
    });
  });
}
