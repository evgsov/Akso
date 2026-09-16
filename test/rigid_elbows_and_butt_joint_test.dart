import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/services/fitting_detector.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/core/math/snap_engine.dart';
import 'package:akso/core/math/axonometry_projector.dart';

void main() {
  group('Rigid Elbows & Butt Joint Tests', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
    });

    test('getElbowTangentMm returns exact construction length T = R * tan(alpha/2)', () {
      // Создаем поворот 90 градусов Ду100 (R = 150 мм)
      net.nodes['n1'] = const Node3D(id: 'n1', x: -1000, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 1000, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 100);

      FittingDetector.autoDetectAllFittings(net);

      final fit = net.fittings['n2'];
      expect(fit, isNotNull);
      expect(fit!.fittingType, FittingType.elbow90);
      expect(fit.effectiveRadiusMm, 150.0);

      // Для 90°: tan(45°) = 1.0 => T = 150.0
      final t = net.getElbowTangentMm('n2');
      expect(t, closeTo(150.0, 0.01));
    });

    test('getElbowTangentMm is symmetric even with very short pipe segment (no hose effect)', () {
      // Одно плечо 1000 мм, другое очень короткое (60 мм)
      net.nodes['n1'] = const Node3D(id: 'n1', x: -1000, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 60, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 100);

      FittingDetector.autoDetectAllFittings(net);

      // Тангенс отвода должен оставаться 150.0 мм, а не сплющиваться в 0.45 * 60 = 27 мм!
      final t = net.getElbowTangentMm('n2');
      expect(t, closeTo(150.0, 0.01));
    });

    test('isElbowToElbowSegment and target length for U-turn or Z-bend', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: -500, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 350, z: 0);
      net.nodes['n4'] = const Node3D(id: 'n4', x: 500, y: 350, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);
      net.segments['s_mid'] = const PipeSegment(id: 's_mid', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys_b1', dn: 100);

      FittingDetector.autoDetectAllFittings(net);

      expect(net.fittings['n2']?.fittingType, FittingType.elbow90);
      expect(net.fittings['n3']?.fittingType, FittingType.elbow90);

      expect(net.isElbowToElbowSegment('s_mid'), isTrue);
      // Для двух отводов Ду100 R=150 мм целевая длина = 150 + 150 = 300 мм
      expect(net.getElbowToElbowTargetLength('s_mid'), closeTo(300.0, 0.01));

      // Сейчас длина 350 мм => не встык (есть паразитная катушка 50 мм)
      expect(net.isButtJoint('s_mid'), isFalse);
    });

    test('collapseElbowToElbow closes the parasitic gap to exact butt joint', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: -500, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 350, z: 0);
      net.nodes['n4'] = const Node3D(id: 'n4', x: 500, y: 350, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);
      net.segments['s_mid'] = const PipeSegment(id: 's_mid', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys_b1', dn: 100);

      FittingDetector.autoDetectAllFittings(net);
      net.recalculateSpools();

      // До стягивания катушка на s_mid равна 350 - 150 - 150 = 50 мм
      final spoolMidBefore = net.spools.values.firstWhere((s) => s.segmentId == 's_mid');
      expect(spoolMidBefore.cutLengthMm, closeTo(50.0, 0.5));

      // Стягиваем встык
      final collapsed = net.collapseElbowToElbow('s_mid');
      expect(collapsed, isTrue);

      // Длина s_mid стала ровно 300 мм
      final distMid = net.nodes['n2']!.distanceTo(net.nodes['n3']!);
      expect(distMid, closeTo(300.0, 0.01));
      expect(net.isButtJoint('s_mid'), isTrue);

      // Downstream узел n4 также сдвинулся по Y на 50 мм (с 350 до 300)
      expect(net.nodes['n4']!.y, closeTo(300.0, 0.01));

      // В SpoolCalculator катушка 0 мм для s_mid ИСКЛЮЧЕНА
      final spoolsAfter = net.spools.values.where((s) => s.segmentId == 's_mid');
      expect(spoolsAfter, isEmpty);
    });

    test('generateElementWeldJoints creates exactly 1 weld seam on butt joint', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: -500, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 300, z: 0); // Стык встык 300 мм
      net.nodes['n4'] = const Node3D(id: 'n4', x: 500, y: 300, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);
      net.segments['s_mid'] = const PipeSegment(id: 's_mid', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys_b1', dn: 100);

      FittingDetector.autoDetectAllFittings(net);

      net.generateElementWeldJoints();

      // На s_mid должен быть ровно 1 сварной шов (в точке контакта двух отводов)
      final midWelds = net.weldJoints.values.where((w) => w.segmentId == 's_mid').toList();
      expect(midWelds.length, 1);
      expect(midWelds.first.ratio, closeTo(0.5, 0.01));
    });

    test('PipingInputController collapseSelectedSegmentToButtJoint collapses selected segment', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: -500, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 380, z: 0);
      net.nodes['n4'] = const Node3D(id: 'n4', x: 500, y: 380, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);
      net.segments['s_mid'] = const PipeSegment(id: 's_mid', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys_b1', dn: 100);

      FittingDetector.autoDetectAllFittings(net);

      final controller = PipingInputController(initialNetwork: net);
      controller.selectedSegmentId = 's_mid';

      expect(controller.isSelectedSegmentElbowToElbow, isTrue);
      expect(controller.isSelectedSegmentButtJoint, isFalse);
      expect(controller.selectedSegmentButtJointLength, closeTo(300.0, 0.01));

      controller.collapseSelectedSegmentToButtJoint();

      expect(controller.isSelectedSegmentButtJoint, isTrue);
      expect(controller.selectedSegmentLength, closeTo(300.0, 0.01));
    });

    test('PipingInputController isAngleLocked defaults to true and can be toggled', () {
      final controller = PipingInputController();
      expect(controller.isAngleLocked, isTrue);
      controller.toggleAngleLock();
      expect(controller.isAngleLocked, isFalse);
      controller.toggleAngleLock();
      expect(controller.isAngleLocked, isTrue);
    });

    test('SnapEngine provides magnetic snap to butt joint distance (T1 + T2)', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: -500, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 100);
      FittingDetector.autoDetectAllFittings(net);

      final snapEngine = SnapEngine();
      const projector = AxonometryProjector(projectionType: ProjectionType.gostFrontal45);

      // При трассировке от n2 по оси +Y (вверх на 305 мм, что близко к 300 мм)
      final nearTargetScreen = projector.project(const Node3D(id: 'test', x: 0, y: 305, z: 0));

      final snap = snapEngine.findSnap(
        screenPos: nearTargetScreen,
        network: net,
        projector: projector,
        currentElevationZ: 0,
        traceStartNode: net.nodes['n2'],
      );

      expect(snap.type, SnapType.polarAngle);
      expect(snap.label, contains('Стык встык (300 мм)'));
      expect(snap.worldPoint.y, closeTo(300.0, 0.1));
    });
  });
}
