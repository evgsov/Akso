import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/repositories/project_repository.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/ui/canvas/input_controller.dart';

class MockProjectRepository implements IProjectRepository {
  ProjectModel? savedProject;
  ProjectModel? projectToReturn;
  int saveCount = 0;
  int loadCount = 0;

  @override
  Future<void> saveProject(ProjectModel project) async {
    savedProject = project;
    saveCount++;
  }

  @override
  Future<ProjectModel?> loadProject() async {
    loadCount++;
    return projectToReturn;
  }
}

void main() {
  group('Project Serialization Tests', () {
    test('ProjectModel JSON round-trip serialization preserves all data', () {
      final network = PipingNetwork();

      const node1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const node2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = node1;
      network.nodes['n2'] = node2;

      const segment = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 50,
        outerDiameterMm: 57.0,
        wallThicknessMm: 3.5,
        slope: 0.002,
        material: '09Г2С',
      );
      network.segments['seg1'] = segment;

      const valve = Valve(
        id: 'val1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка клиновая 30с41нж',
        dn: 50,
        lengthMm: 180,
      );
      network.valves['val1'] = valve;

      final project = ProjectModel(
        id: 'test-project-uuid-1234',
        title: 'Узел учета тепла',
        objectAddress: 'г. Москва, ул. Ленина, д. 15',
        engineerName: 'Петров П.П.',
        creationDate: '2026-09-12',
        projectionType: ProjectionType.iso30,
        activeSystemId: 'sys_t3',
        activeDn: 50,
        currentElevationZ: 150.0,
        network: network,
      );

      // Round-trip serialization: Model -> JSON String -> Model
      final jsonMap = project.toJson();
      final jsonString = jsonEncode(jsonMap);
      final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final restoredProject = ProjectModel.fromJson(decodedMap);

      // Assert project metadata
      expect(restoredProject.id, equals(project.id));
      expect(restoredProject.title, equals(project.title));
      expect(restoredProject.objectAddress, equals(project.objectAddress));
      expect(restoredProject.engineerName, equals(project.engineerName));
      expect(restoredProject.creationDate, equals(project.creationDate));
      expect(restoredProject.projectionType, equals(project.projectionType));
      expect(restoredProject.activeSystemId, equals(project.activeSystemId));
      expect(restoredProject.activeDn, equals(project.activeDn));
      expect(restoredProject.currentElevationZ, equals(project.currentElevationZ));

      // Assert network structure
      expect(restoredProject.network.nodes.length, equals(2));
      expect(restoredProject.network.segments.length, equals(1));
      expect(restoredProject.network.valves.length, equals(1));

      // Assert node details
      final restoredNode1 = restoredProject.network.nodes['n1']!;
      expect(restoredNode1.x, equals(0.0));
      expect(restoredNode1.y, equals(0.0));
      expect(restoredNode1.z, equals(0.0));

      final restoredNode2 = restoredProject.network.nodes['n2']!;
      expect(restoredNode2.x, equals(1000.0));
      expect(restoredNode2.y, equals(0.0));
      expect(restoredNode2.z, equals(0.0));

      // Assert segment details
      final restoredSeg = restoredProject.network.segments['seg1']!;
      expect(restoredSeg.startNodeId, equals('n1'));
      expect(restoredSeg.endNodeId, equals('n2'));
      expect(restoredSeg.systemId, equals('sys_b1'));
      expect(restoredSeg.dn, equals(50));
      expect(restoredSeg.outerDiameterMm, equals(57.0));
      expect(restoredSeg.wallThicknessMm, equals(3.5));
      expect(restoredSeg.slope, equals(0.002));
      expect(restoredSeg.material, equals('09Г2С'));

      // Assert valve details
      final restoredValve = restoredProject.network.valves['val1']!;
      expect(restoredValve.id, equals('val1'));
      expect(restoredValve.segmentId, equals('seg1'));
      expect(restoredValve.ratio, equals(0.5));
      expect(restoredValve.valveType, equals(ValveType.gateValve));
      expect(restoredValve.name, equals('Задвижка клиновая 30с41нж'));
      expect(restoredValve.dn, equals(50));
      expect(restoredValve.lengthMm, equals(180.0));
    });

    test('PipingInputController accepts IProjectRepository via DI', () async {
      final mockRepo = MockProjectRepository();
      final controller = PipingInputController(repository: mockRepo);
      addTearDown(() => controller.dispose());

      expect(controller.projectRepository, equals(mockRepo));

      // Test save delegation
      await controller.saveProject();
      expect(mockRepo.saveCount, equals(1));
      expect(mockRepo.savedProject?.id, equals(controller.currentProject.id));

      // Test load delegation
      final networkToLoad = PipingNetwork();
      networkToLoad.nodes['loaded_n1'] = const Node3D(id: 'loaded_n1', x: 50, y: 60, z: 70);
      mockRepo.projectToReturn = ProjectModel(
        id: 'loaded-uuid-5678',
        title: 'Загруженный проект',
        network: networkToLoad,
      );

      await controller.loadProject();
      expect(mockRepo.loadCount, equals(1));
      expect(controller.currentProject.id, equals('loaded-uuid-5678'));
      expect(controller.currentProject.title, equals('Загруженный проект'));
      expect(controller.network.nodes.containsKey('loaded_n1'), isTrue);
    });
  });
}
