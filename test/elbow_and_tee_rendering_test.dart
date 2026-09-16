import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/services/spool_calculator.dart';
import 'package:akso/ui/canvas/painters/pipe_painter.dart';
import 'package:akso/ui/canvas/painters/fitting_painter.dart';
import 'package:akso/data/dxf/dxf_writer.dart';

void main() {
  group('Elbow-to-Elbow Spool and Tee Geometry Tests', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
      net.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Водоснабжение',
        code: 'В1',
        colorValue: 0xFF2196F3,
        dxfAciColor: 5,
      );
    });

    test('Segment between two 90-degree elbows generates physical spool when length > T1 + T2', () {
      // Маршрут Z-образный:
      // n1(0, 0, 0) -> n2(0, 1000, 0) -> n3(1000, 1000, 0) -> n4(1000, 2000, 0)
      // В узлах n2 и n3 отводы 90° (DN 100).
      // Сегмент между ними: n2 -> n3 (L = 1000 мм).
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 0, y: 1000, z: 0);
      final n3 = Node3D(id: 'n3', x: 1000, y: 1000, z: 0);
      final n4 = Node3D(id: 'n4', x: 1000, y: 2000, z: 0);

      net.nodes[n1.id] = n1;
      net.nodes[n2.id] = n2;
      net.nodes[n3.id] = n3;
      net.nodes[n4.id] = n4;

      final s1 = PipeSegment(id: 's1', startNodeId: n1.id, endNodeId: n2.id, systemId: 'sys1', dn: 100);
      final s2 = PipeSegment(id: 's2', startNodeId: n2.id, endNodeId: n3.id, systemId: 'sys1', dn: 100);
      final s3 = PipeSegment(id: 's3', startNodeId: n3.id, endNodeId: n4.id, systemId: 'sys1', dn: 100);

      net.segments[s1.id] = s1;
      net.segments[s2.id] = s2;
      net.segments[s3.id] = s3;

      // Отводы в n2 и n3 (R = 150 мм => T1 = 150, T2 = 150)
      net.fittings[n2.id] = Fitting(
        id: 'fit_n2',
        nodeId: n2.id,
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );
      net.fittings[n3.id] = Fitting(
        id: 'fit_n3',
        nodeId: n3.id,
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );

      // Проверяем сетевые методы
      expect(net.isElbowToElbowSegment(s2.id), isTrue);
      expect(net.isButtJoint(s2.id), isFalse); // L=1000, T1+T2=300 => не встык!

      SpoolCalculator.recalculateSpools(net);

      // Между n2 и n3 ОБЯЗАНА существовать физическая катушка длиной 1000 - 150 - 150 = 700 мм
      final intermediateSpools = net.spools.values.where((sp) => sp.segmentId == s2.id).toList();
      expect(intermediateSpools.length, equals(1));
      final spool = intermediateSpools.first;
      expect(spool.cutLengthMm, closeTo(700.0, 1.0));
      expect(spool.startPoint?.x, closeTo(150.0, 1.0));
      expect(spool.startPoint?.y, closeTo(1000.0, 1.0));
      expect(spool.endPoint?.x, closeTo(850.0, 1.0));
      expect(spool.endPoint?.y, closeTo(1000.0, 1.0));
    });

    test('Segment between two 90-degree elbows produces 0 spools when in butt joint (L = T1 + T2)', () {
      // Два отвода встык: n1(0, 0, 0) -> n2(0, 300, 0) -> n3(300, 300, 0) -> n4(300, 600, 0)
      // Длина между n2 и n3 = 300 мм (T1 + T2 = 150 + 150 = 300)
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 0, y: 300, z: 0);
      final n3 = Node3D(id: 'n3', x: 300, y: 300, z: 0);
      final n4 = Node3D(id: 'n4', x: 300, y: 600, z: 0);

      net.nodes[n1.id] = n1;
      net.nodes[n2.id] = n2;
      net.nodes[n3.id] = n3;
      net.nodes[n4.id] = n4;

      final s1 = PipeSegment(id: 's1', startNodeId: n1.id, endNodeId: n2.id, systemId: 'sys1', dn: 100);
      final s2 = PipeSegment(id: 's2', startNodeId: n2.id, endNodeId: n3.id, systemId: 'sys1', dn: 100);
      final s3 = PipeSegment(id: 's3', startNodeId: n3.id, endNodeId: n4.id, systemId: 'sys1', dn: 100);

      net.segments[s1.id] = s1;
      net.segments[s2.id] = s2;
      net.segments[s3.id] = s3;

      net.fittings[n2.id] = Fitting(
        id: 'fit_n2',
        nodeId: n2.id,
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );
      net.fittings[n3.id] = Fitting(
        id: 'fit_n3',
        nodeId: n3.id,
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );

      expect(net.isElbowToElbowSegment(s2.id), isTrue);
      expect(net.isButtJoint(s2.id), isTrue);

      SpoolCalculator.recalculateSpools(net);

      final intermediateSpools = net.spools.values.where((sp) => sp.segmentId == s2.id).toList();
      expect(intermediateSpools, isEmpty);
    });

    test('Standard Tee produces correct run deductions (L/2) and branch deduction (H)', () {
      // Магистраль: n1(0, 0, 0) -> nTee(1000, 0, 0) -> n2(2000, 0, 0)
      // Ответвление: nTee(1000, 0, 0) -> nBranch(1000, 1000, 0)
      // Тройник DN 100: L = 200 мм (L/2 = 100 мм), H = 100 мм.
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final nTee = Node3D(id: 'nTee', x: 1000, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      final nBranch = Node3D(id: 'nBranch', x: 1000, y: 1000, z: 0);

      net.nodes[n1.id] = n1;
      net.nodes[nTee.id] = nTee;
      net.nodes[n2.id] = n2;
      net.nodes[nBranch.id] = nBranch;

      final sRun1 = PipeSegment(id: 'sRun1', startNodeId: n1.id, endNodeId: nTee.id, systemId: 'sys1', dn: 100);
      final sRun2 = PipeSegment(id: 'sRun2', startNodeId: nTee.id, endNodeId: n2.id, systemId: 'sys1', dn: 100);
      final sBranch = PipeSegment(id: 'sBranch', startNodeId: nTee.id, endNodeId: nBranch.id, systemId: 'sys1', dn: 100);

      net.segments[sRun1.id] = sRun1;
      net.segments[sRun2.id] = sRun2;
      net.segments[sBranch.id] = sBranch;

      net.fittings[nTee.id] = Fitting(
        id: 'fit_tee',
        nodeId: nTee.id,
        fittingType: FittingType.tee,
        dn: 100,
        radiusMm: 100.0,
        buildingLengthMm: 200.0,
        branchLengthMm: 150.0,
      );

      SpoolCalculator.recalculateSpools(net);

      // sRun1: 1000 - 100 (вычет L/2 тройника) = 900 мм
      final spoolRun1 = net.spools.values.firstWhere((sp) => sp.segmentId == sRun1.id);
      expect(spoolRun1.cutLengthMm, closeTo(900.0, 1.0));
      expect(spoolRun1.startPoint?.x, closeTo(0.0, 1.0));
      expect(spoolRun1.endPoint?.x, closeTo(900.0, 1.0));

      // sRun2: 1000 - 100 (вычет L/2 тройника) = 900 мм
      final spoolRun2 = net.spools.values.firstWhere((sp) => sp.segmentId == sRun2.id);
      expect(spoolRun2.cutLengthMm, closeTo(900.0, 1.0));
      expect(spoolRun2.startPoint?.x, closeTo(1100.0, 1.0));
      expect(spoolRun2.endPoint?.x, closeTo(2000.0, 1.0));

      // sBranch: 1000 - 150 (вычет H тройника) = 850 мм
      final spoolBranch = net.spools.values.firstWhere((sp) => sp.segmentId == sBranch.id);
      expect(spoolBranch.cutLengthMm, closeTo(850.0, 1.0));
      expect(spoolBranch.startPoint?.x, closeTo(1000.0, 1.0));
      expect(spoolBranch.startPoint?.y, closeTo(150.0, 1.0));
      expect(spoolBranch.endPoint?.y, closeTo(1000.0, 1.0));
    });

    test('Direct branch (У18) keeps main spool un-cut and deduces D_outer/2 from branch', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final nTee = Node3D(id: 'nTee', x: 1000, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      final nBranch = Node3D(id: 'nBranch', x: 1000, y: 1000, z: 0);

      net.nodes[n1.id] = n1;
      net.nodes[nTee.id] = nTee;
      net.nodes[n2.id] = n2;
      net.nodes[nBranch.id] = nBranch;

      // Магистраль DN 100 (наружный диаметр 108 мм, радиус 54 мм)
      final sRun1 = PipeSegment(id: 'sRun1', startNodeId: n1.id, endNodeId: nTee.id, systemId: 'sys1', dn: 100);
      final sRun2 = PipeSegment(id: 'sRun2', startNodeId: nTee.id, endNodeId: n2.id, systemId: 'sys1', dn: 100);
      final sBranch = PipeSegment(id: 'sBranch', startNodeId: nTee.id, endNodeId: nBranch.id, systemId: 'sys1', dn: 50);

      net.segments[sRun1.id] = sRun1;
      net.segments[sRun2.id] = sRun2;
      net.segments[sBranch.id] = sBranch;

      net.fittings[nTee.id] = Fitting(
        id: 'fit_direct_branch',
        nodeId: nTee.id,
        fittingType: FittingType.directBranch,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 0.0,
      );

      SpoolCalculator.recalculateSpools(net);

      // Магистраль идет единой сквозной катушкой через ThroughRun: длина 2000 мм (или 2 сегмента по 1000 без вычета в nTee)
      final branchSpool = net.spools.values.firstWhere((sp) => sp.segmentId == sBranch.id);
      // DN100 outer diameter = 108 => radius = 54
      expect(branchSpool.cutLengthMm, closeTo(1000.0 - 54.0, 1.0));
      expect(branchSpool.startPoint?.y, closeTo(54.0, 1.0));
    });

    test('DXF export includes АКСО_ТРОЙНИКИ layer and tee geometry', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final nTee = Node3D(id: 'nTee', x: 1000, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      final nBranch = Node3D(id: 'nBranch', x: 1000, y: 1000, z: 0);

      net.nodes[n1.id] = n1;
      net.nodes[nTee.id] = nTee;
      net.nodes[n2.id] = n2;
      net.nodes[nBranch.id] = nBranch;

      net.segments['s1'] = PipeSegment(id: 's1', startNodeId: n1.id, endNodeId: nTee.id, systemId: 'sys1', dn: 100);
      net.segments['s2'] = PipeSegment(id: 's2', startNodeId: nTee.id, endNodeId: n2.id, systemId: 'sys1', dn: 100);
      net.segments['s3'] = PipeSegment(id: 's3', startNodeId: nTee.id, endNodeId: nBranch.id, systemId: 'sys1', dn: 100);

      net.fittings[nTee.id] = Fitting(
        id: 'fit_tee',
        nodeId: nTee.id,
        fittingType: FittingType.tee,
        dn: 100,
        radiusMm: 100.0,
      );

      final dxf3d = DxfWriter.generate3dDxf(net);
      expect(dxf3d.contains(DxfWriter.toAutoCadString('АКСО_ТРОЙНИКИ')), isTrue);

      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(net);
      expect(dxf2d.contains(DxfWriter.toAutoCadString('АКСО_ТРОЙНИКИ')), isTrue);
    });

    test('FittingPainter and PipePainter render elbows and tees without throwing', () {
      const projector = AxonometryProjector(projectionType: ProjectionType.gostFrontal45);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final screenPoints = <String, Offset>{};
      for (final n in net.nodes.values) {
        screenPoints[n.id] = projector.project(n);
      }

      expect(() {
        PipePainter.paint(
          canvas,
          const Size(800, 600),
          projector,
          net,
          null,
          null,
          screenPoints,
          false,
          false,
          null,
          false,
        );

        FittingPainter.paint(
          canvas,
          projector,
          net,
          'nTee',
          true,
          isVolumeMode: false,
        );
      }, returnsNormally);
    });
  });
}
