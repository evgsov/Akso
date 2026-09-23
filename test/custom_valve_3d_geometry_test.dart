import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/custom_valve_definition.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/services/custom_valve_catalog.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/ui/canvas/painters/solid_3d_engine.dart';
import 'package:akso/ui/canvas/painters/valve_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Valve valve;
  late Node3D startNode;
  late Node3D endNode;

  setUp(() {
    startNode = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    endNode = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
    valve = const Valve(
      id: 'v1',
      name: 'Задвижка',
      segmentId: 'seg1',
      ratio: 0.5,
      dn: 50,
      valveType: ValveType.gateValve,
      lengthMm: 150,
    );
  });

  group('Element3dGeometry Wireframe Custom Valve Tests', () {
    test('generates wireframe for bellows body and none actuator', () {
      const antiVibDef = CustomValveDefinition(
        id: 'anti_vib',
        name: 'Антивибрационный',
        geometry3d: ValveGeometry3dConfig(
          bodyShape: Valve3dBodyShape.bellows,
          actuatorType: Valve3dActuatorType.none,
        ),
      );

      final segments = Element3dGeometry.generateValveWireframe(
        valve,
        startNode,
        endNode,
        customDefinition: antiVibDef,
      );

      expect(segments.isNotEmpty, isTrue);
      // Since actuatorType is none, there shouldn't be high stem segments
      final maxY = segments.map((s) => s.y1.abs()).reduce((a, b) => a > b ? a : b);
      final maxZ = segments.map((s) => s.z1.abs()).reduce((a, b) => a > b ? a : b);
      expect(maxY < 100, isTrue);
      expect(maxZ < 100, isTrue);
    });

    test('generates wireframe for actuatorBox', () {
      const electricDef = CustomValveDefinition(
        id: 'electric',
        name: 'Электропривод',
        geometry3d: ValveGeometry3dConfig(
          bodyShape: Valve3dBodyShape.doubleCones,
          actuatorType: Valve3dActuatorType.actuatorBox,
        ),
      );

      final segments = Element3dGeometry.generateValveWireframe(
        valve,
        startNode,
        endNode,
        customDefinition: electricDef,
      );

      expect(segments.isNotEmpty, isTrue);
      // Contains stem and box edges
      expect(segments.length > 8, isTrue);
    });

    test('generates wireframe for diaphragm and springBonnet', () {
      const diaphragmDef = CustomValveDefinition(
        id: 'diaphragm',
        name: 'Мембранный',
        geometry3d: ValveGeometry3dConfig(
          bodyShape: Valve3dBodyShape.cylinder,
          actuatorType: Valve3dActuatorType.diaphragm,
        ),
      );

      final segments = Element3dGeometry.generateValveWireframe(
        valve,
        startNode,
        endNode,
        customDefinition: diaphragmDef,
      );
      expect(segments.isNotEmpty, isTrue);
    });
  });

  group('Solid3dEngine & ValvePainter Custom Valve Integration Tests', () {
    test('ValvePainter renders custom valve wireframe onto canvas', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        systemId: 'sys1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
      );

      final customDef = CustomValveCatalog.instance.getById('preset_anti_vibration_valve')!;

      network.valves['v_custom'] = Valve(
        id: 'v_custom',
        name: 'Виброкомпенсатор',
        segmentId: 'seg1',
        ratio: 0.5,
        dn: 50,
        lengthMm: 150,
        valveType: ValveType.gateValve,
        customDefinitionId: customDef.id,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const projector = AxonometryProjector(projectionType: ProjectionType.gostFrontal45);

      ValvePainter.paint(
        canvas,
        projector,
        network,
        customValves: {customDef.id: customDef},
      );

      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });

    test('Solid3dEngine renders custom valve meshes with actuator box and bellows', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        systemId: 'sys1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
      );

      final customDef = CustomValveCatalog.instance.getById('preset_electric_actuator_valve')!;

      network.valves['v_electric'] = Valve(
        id: 'v_electric',
        name: 'Электрозадвижка',
        segmentId: 'seg1',
        ratio: 0.5,
        dn: 50,
        lengthMm: 180,
        valveType: ValveType.gateValve,
        customDefinitionId: customDef.id,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const projector = AxonometryProjector(projectionType: ProjectionType.gostFrontal45);

      Solid3dEngine.renderNetwork(
        canvas,
        projector,
        network,
        customValves: {customDef.id: customDef},
      );

      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });
  });
}
