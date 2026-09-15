import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/ui/canvas/painters/solid_3d_engine.dart';

void main() {
  group('Solid3dEngine & 3D Math Tests', () {
    test('Vector3D basic operations', () {
      const v1 = Vector3D(1, 2, 3);
      const v2 = Vector3D(4, 5, 6);

      final sum = v1 + v2;
      expect(sum.x, 5);
      expect(sum.y, 7);
      expect(sum.z, 9);

      final diff = v2 - v1;
      expect(diff.x, 3);
      expect(diff.y, 3);
      expect(diff.z, 3);

      final scaled = v1 * 2;
      expect(scaled.x, 2);
      expect(scaled.y, 4);
      expect(scaled.z, 6);

      final dot = v1.dot(v2); // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
      expect(dot, 32);

      const vx = Vector3D(1, 0, 0);
      const vy = Vector3D(0, 1, 0);
      final cross = vx.cross(vy);
      expect(cross.x, 0);
      expect(cross.y, 0);
      expect(cross.z, 1);

      final norm = const Vector3D(0, 3, 4).normalized();
      expect(norm.length, closeTo(1.0, 1e-6));
      expect(norm.y, closeTo(0.6, 1e-6));
      expect(norm.z, closeTo(0.8, 1e-6));
    });

    test('Directional Lighting computation', () {
      const normalTowardsLight = Vector3D(0.4, -0.6, 0.7); // aligned with lightDir
      const normalAwayFromLight = Vector3D(-0.4, 0.6, -0.7); // opposite to lightDir
      const baseColor = Color(0xFF2196F3);

      final litTowards = Solid3dEngine.computeLighting(normalTowardsLight.normalized(), baseColor);
      final litAway = Solid3dEngine.computeLighting(normalAwayFromLight.normalized(), baseColor);

      // Normal facing light should be noticeably brighter than normal facing away
      final brightTowards = litTowards.r + litTowards.g + litTowards.b;
      final brightAway = litAway.r + litAway.g + litAway.b;
      expect(brightTowards > brightAway, isTrue);
    });

    test('AxonometryProjector depth calculation', () {
      const projector = AxonometryProjector(
        projectionType: ProjectionType.orbit3d,
        orbitAzimuth: 0,
        orbitElevation: 0,
      );

      // При azimuth=0, elevation=0 луч взгляда направлен вдоль оси +Y
      // Точка с большим Y находится глубже (дальше от камеры)
      final d1 = projector.computeDepth(0, 100, 0);
      final d2 = projector.computeDepth(0, 500, 0);
      expect(d2 > d1, isTrue);

      const gostProjector = AxonometryProjector(
        projectionType: ProjectionType.gostFrontal45,
      );
      // В ГОСТ 45° ось X уходит в глубину
      final gx1 = gostProjector.computeDepth(50, 0, 0);
      final gx2 = gostProjector.computeDepth(200, 0, 0);
      expect(gx2 > gx1, isTrue);
    });

    test('Solid3dEngine renders network to canvas without crashing', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 2000, y: 1500, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      const seg1 = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_t1',
        dn: 100,
      );
      const seg2 = PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys_t1',
        dn: 80,
      );
      network.segments['seg1'] = seg1;
      network.segments['seg2'] = seg2;

      // Добавим арматуру и переход
      const valve = Valve(
        id: 'valve1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка Ду100',
        dn: 100,
        lengthMm: 250,
      );
      network.valves['valve1'] = valve;

      const fit = Fitting(
        id: 'fit1',
        nodeId: 'n2',
        fittingType: FittingType.reducerConcentric,
        dn: 100,
        dnSecondary: 80,
        radiusMm: 150,
      );
      network.fittings['fit1'] = fit;

      const projector = AxonometryProjector(
        projectionType: ProjectionType.orbit3d,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      // Не должно выбрасывать исключений при генерации и рендеринге 3D полигонов
      expect(() {
        Solid3dEngine.renderNetwork(
          canvas,
          projector,
          network,
          selectedSegmentId: 'seg1',
          cylinderFacets: 8,
        );
      }, returnsNormally);

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('Vector3D unary minus operator', () {
      const v = Vector3D(1.5, -2.5, 3.0);
      final neg = -v;
      expect(neg.x, -1.5);
      expect(neg.y, 2.5);
      expect(neg.z, -3.0);
    });

    test('Solid3dEngine renders 3D Toroidal Elbows (90° and 45°) with trimmed pipes', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      const n4 = Node3D(id: 'n4', x: 1707, y: 1707, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;
      network.nodes['n4'] = n4;

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);
      network.segments['s3'] = const PipeSegment(id: 's3', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys1', dn: 100);

      // Отвод 90° в узле n2
      network.fittings['fit90'] = const Fitting(
        id: 'fit90',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150,
      );

      // Отвод 45° в узле n3
      network.fittings['fit45'] = const Fitting(
        id: 'fit45',
        nodeId: 'n3',
        fittingType: FittingType.elbow45,
        dn: 100,
        radiusMm: 150,
      );

      const projector = AxonometryProjector(projectionType: ProjectionType.orbit3d);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() {
        Solid3dEngine.renderNetwork(canvas, projector, network, cylinderFacets: 8);
      }, returnsNormally);

      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });

    test('Solid3dEngine renders Eccentric Reducers with flat-bottom alignment', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 150);
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 80);

      network.fittings['fit_ecc'] = const Fitting(
        id: 'fit_ecc',
        nodeId: 'n2',
        fittingType: FittingType.reducerEccentric,
        dn: 150,
        dnSecondary: 80,
        radiusMm: 200,
        buildingLengthMm: 180,
      );

      const projector = AxonometryProjector(projectionType: ProjectionType.orbit3d);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() {
        Solid3dEngine.renderNetwork(canvas, projector, network, cylinderFacets: 8);
      }, returnsNormally);

      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });

    test('Solid3dEngine renders 3D WeldJoint beads and Flange Pairs', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1500, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Сварной шов посередине трубы
      network.weldJoints['w1'] = const WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.5,
        number: 1,
        stamp: 'АК-01',
      );

      // Фланцевая пара на конце трубы
      network.fittings['f_pair'] = const Fitting(
        id: 'f_pair',
        nodeId: 'n2',
        fittingType: FittingType.flange,
        dn: 100,
        radiusMm: 100,
        isFlangePair: true,
        buildingLengthMm: 40,
      );

      const projector = AxonometryProjector(projectionType: ProjectionType.orbit3d);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() {
        Solid3dEngine.renderNetwork(canvas, projector, network, cylinderFacets: 8);
      }, returnsNormally);

      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });

    test('Solid3dEngine renders 3D PipeSupports (fixed, sliding, spring)', () {
      final network = PipingNetwork();
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Неподвижная, скользящая и пружинная опоры
      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 's1',
        distanceRatio: 0.25,
        type: PipeSupportType.fixed,
      );
      network.supports['sup2'] = const PipeSupport(
        id: 'sup2',
        segmentId: 's1',
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
      );
      network.supports['sup3'] = const PipeSupport(
        id: 'sup3',
        segmentId: 's1',
        distanceRatio: 0.75,
        type: PipeSupportType.spring,
      );

      const projector = AxonometryProjector(projectionType: ProjectionType.orbit3d);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() {
        Solid3dEngine.renderNetwork(canvas, projector, network, cylinderFacets: 8);
      }, returnsNormally);

      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });
  });
}
