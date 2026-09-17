import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/enums/weld_joint_style.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/ui/canvas/painters/annotation_painter.dart';
import 'package:akso/ui/canvas/painters/fitting_painter.dart';

void main() {
  group('WeldJointStyle and Model Tests', () {
    test('WeldJointStyle enum and fromString', () {
      expect(WeldJointStyle.tick.label, equals('Засечка ГОСТ'));
      expect(WeldJointStyle.ring3d.label, equals('3D-кольцо'));
      expect(WeldJointStyle.circle.label, equals('Кружок'));
      expect(WeldJointStyle.dot.label, equals('Точка'));

      expect(WeldJointStyle.fromString('tick'), equals(WeldJointStyle.tick));
      expect(WeldJointStyle.fromString('ring3d'), equals(WeldJointStyle.ring3d));
      expect(WeldJointStyle.fromString('circle'), equals(WeldJointStyle.circle));
      expect(WeldJointStyle.fromString('dot'), equals(WeldJointStyle.dot));
      expect(WeldJointStyle.fromString('unknown'), equals(WeldJointStyle.tick));
      expect(WeldJointStyle.fromString(null), equals(WeldJointStyle.tick));
    });

    test('WeldJoint getEffectiveStyle fallback and override', () {
      final wDefault = WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.5,
        number: 1,
        stamp: 'ИВ-01',
      );

      // Без переопределения — наследует от сети
      expect(wDefault.getEffectiveStyle(WeldJointStyle.tick), equals(WeldJointStyle.tick));
      expect(wDefault.getEffectiveStyle(WeldJointStyle.ring3d), equals(WeldJointStyle.ring3d));
      expect(wDefault.getEffectiveStyle(WeldJointStyle.circle), equals(WeldJointStyle.circle));
      expect(wDefault.getEffectiveStyle(WeldJointStyle.dot), equals(WeldJointStyle.dot));

      // С переопределением на уровне шва
      final wOverridden = wDefault.copyWith(style: WeldJointStyle.circle);
      expect(wOverridden.getEffectiveStyle(WeldJointStyle.tick), equals(WeldJointStyle.circle));

      // Сброс переопределения обратно на по умолчанию
      final wCleared = wOverridden.copyWith(clearStyle: true);
      expect(wCleared.style, isNull);
      expect(wCleared.getEffectiveStyle(WeldJointStyle.ring3d), equals(WeldJointStyle.ring3d));
    });

    test('WeldJoint JSON serialization preserves style', () {
      final w = WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.3,
        number: 5,
        stamp: 'ИВ-05',
        style: WeldJointStyle.ring3d,
      );

      final json = w.toJson();
      expect(json['style'], equals('ring3d'));

      final restored = WeldJoint.fromJson(json);
      expect(restored.style, equals(WeldJointStyle.ring3d));

      final wNull = WeldJoint(
        id: 'w2',
        segmentId: 's1',
        ratio: 0.7,
        number: 6,
        stamp: 'ИВ-06',
      );
      expect(wNull.toJson()['style'], isNull);
      expect(WeldJoint.fromJson(wNull.toJson()).style, isNull);
    });

    test('PipingNetwork JSON serialization preserves defaultWeldStyle', () {
      final net = PipingNetwork();
      expect(net.defaultWeldStyle, equals(WeldJointStyle.tick));

      net.defaultWeldStyle = WeldJointStyle.circle;
      final json = net.toJson();
      expect(json['defaultWeldStyle'], equals('circle'));

      final restored = PipingNetwork.fromJson(json);
      expect(restored.defaultWeldStyle, equals(WeldJointStyle.circle));
    });

    test('PipingNetwork.bulkUpdateWeldJoints updates styles and clearStyle', () {
      final net = PipingNetwork();
      net.weldJoints['w1'] = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.2, number: 1, stamp: 'A');
      net.weldJoints['w2'] = WeldJoint(id: 'w2', segmentId: 's1', ratio: 0.8, number: 2, stamp: 'B');

      net.bulkUpdateWeldJoints({'w1', 'w2'}, style: WeldJointStyle.dot);
      expect(net.weldJoints['w1']!.style, equals(WeldJointStyle.dot));
      expect(net.weldJoints['w2']!.style, equals(WeldJointStyle.dot));

      net.bulkUpdateWeldJoints({'w1'}, clearStyle: true);
      expect(net.weldJoints['w1']!.style, isNull);
      expect(net.weldJoints['w2']!.style, equals(WeldJointStyle.dot));
    });

    test('WeldJoint getEffectiveTickSize fallback hierarchy', () {
      final w = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: 'W');

      // 1. По умолчанию: берется диаметр трубы
      expect(w.getEffectiveTickSize(null, 108.0), equals(108.0));

      // 2. Задан дефолт сети, но у шва нет индивидуального переопределения
      expect(w.getEffectiveTickSize(60.0, 108.0), equals(60.0));

      // 3. У шва задан свой размер — он имеет наивысший приоритет
      final wCustom = w.copyWith(tickSizeMm: 75.0);
      expect(wCustom.getEffectiveTickSize(null, 108.0), equals(75.0));
      expect(wCustom.getEffectiveTickSize(60.0, 108.0), equals(75.0));

      // 4. Сброс индивидуального размера
      final wReset = wCustom.copyWith(clearTickSize: true);
      expect(wReset.tickSizeMm, isNull);
      expect(wReset.getEffectiveTickSize(60.0, 108.0), equals(60.0));
    });

    test('WeldJoint and PipingNetwork JSON serialization preserves tickSizeMm', () {
      final w = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: 'W', tickSizeMm: 85.0);
      final jsonW = w.toJson();
      expect(jsonW['tickSizeMm'], equals(85.0));
      expect(WeldJoint.fromJson(jsonW).tickSizeMm, equals(85.0));

      final net = PipingNetwork();
      net.defaultWeldTickSizeMm = 65.0;
      final jsonNet = net.toJson();
      expect(jsonNet['defaultWeldTickSizeMm'], equals(65.0));
      expect(PipingNetwork.fromJson(jsonNet).defaultWeldTickSizeMm, equals(65.0));
    });

    test('PipingNetwork.bulkUpdateWeldJoints updates tickSizeMm and clearTickSize', () {
      final net = PipingNetwork();
      net.weldJoints['w1'] = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.2, number: 1, stamp: 'A');
      net.weldJoints['w2'] = WeldJoint(id: 'w2', segmentId: 's1', ratio: 0.8, number: 2, stamp: 'B');

      net.bulkUpdateWeldJoints({'w1', 'w2'}, tickSizeMm: 90.0);
      expect(net.weldJoints['w1']!.tickSizeMm, equals(90.0));
      expect(net.weldJoints['w2']!.tickSizeMm, equals(90.0));

      net.bulkUpdateWeldJoints({'w1'}, clearTickSize: true);
      expect(net.weldJoints['w1']!.tickSizeMm, isNull);
      expect(net.weldJoints['w2']!.tickSizeMm, equals(90.0));
    });
  });

  group('Element3dGeometry 3D Weld Wireframes', () {
    test('generateWeld3d produces lines according to style and orientation', () {
      final start = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final end = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final weld = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: 'W');

      // 1. Труба вдоль оси Y (горизонталь) -> засечка строго в плоскости X, Y вдоль оси X (под 0° к горизонту, перпендикулярно Y)
      final startY = Node3D(id: 'nY1', x: 0, y: 0, z: 0);
      final endY = Node3D(id: 'nY2', x: 0, y: 1000, z: 0);
      final linesTickY = Element3dGeometry.generateWeld3d(
        weld,
        startY,
        endY,
        pipeOuterDiameter: 108.0,
        style: WeldJointStyle.tick,
      );
      expect(linesTickY.length, equals(1));
      expect(linesTickY[0].layer, equals(Element3dGeometry.layerWelds));
      // Перпендикулярно оси Y на плоскости XY: deltaX == 108.0, deltaY == 0, deltaZ == 0 (под 0° по Z)
      expect((linesTickY[0].x2 - linesTickY[0].x1).abs(), closeTo(108.0, 0.001));
      expect(linesTickY[0].y1, closeTo(500.0, 0.001));
      expect(linesTickY[0].y2, closeTo(500.0, 0.001));
      expect(linesTickY[0].z1, closeTo(0.0, 0.001));
      expect(linesTickY[0].z2, closeTo(0.0, 0.001));

      // 2. Труба вдоль оси Z (стояк) -> засечка строго в плоскости X, Y вдоль оси Y (под 0° по Z)
      final startZ = Node3D(id: 'nZ1', x: 0, y: 0, z: 0);
      final endZ = Node3D(id: 'nZ2', x: 0, y: 0, z: 1000);
      final linesTickZ = Element3dGeometry.generateWeld3d(
        weld,
        startZ,
        endZ,
        pipeOuterDiameter: 108.0,
        style: WeldJointStyle.tick,
      );
      expect(linesTickZ.length, equals(1));
      expect(linesTickZ[0].x1, closeTo(0.0, 0.001));
      expect(linesTickZ[0].x2, closeTo(0.0, 0.001));
      expect(linesTickZ[0].z1, closeTo(500.0, 0.001));
      expect(linesTickZ[0].z2, closeTo(500.0, 0.001));
      expect((linesTickZ[0].y2 - linesTickZ[0].y1).abs(), closeTo(108.0, 0.001));

      // 3. Труба вдоль оси X -> засечка строго в плоскости X, Y вдоль оси Y (deltaX == 0, deltaZ == 0)
      final linesTickX = Element3dGeometry.generateWeld3d(
        weld,
        start,
        end,
        pipeOuterDiameter: 108.0,
        style: WeldJointStyle.tick,
      );
      expect(linesTickX.length, equals(1));
      expect(linesTickX[0].x1, closeTo(500.0, 0.001));
      expect(linesTickX[0].x2, closeTo(500.0, 0.001));
      expect((linesTickX[0].y2 - linesTickX[0].y1).abs(), closeTo(108.0, 0.001));
      expect(linesTickX[0].z1, closeTo(0.0, 0.001));
      expect(linesTickX[0].z2, closeTo(0.0, 0.001));

      // Tick с явно заданным размером (например, 50 мм) на плоскости XY
      final linesTickCustom = Element3dGeometry.generateWeld3d(
        weld,
        startY,
        endY,
        pipeOuterDiameter: 108.0,
        style: WeldJointStyle.tick,
        tickSizeMm: 50.0,
      );
      expect(linesTickCustom.length, equals(1));
      expect((linesTickCustom[0].x2 - linesTickCustom[0].x1).abs(), closeTo(50.0, 0.001));
      expect(linesTickCustom[0].z1, closeTo(0.0, 0.001));
      expect(linesTickCustom[0].z2, closeTo(0.0, 0.001));

      // Ring3d: кольцо из 16 сегментов
      final linesRing = Element3dGeometry.generateWeld3d(
        weld,
        start,
        end,
        pipeOuterDiameter: 108.0,
        style: WeldJointStyle.ring3d,
      );
      expect(linesRing.length, equals(16));

      // Dot: короткий отрезок точки
      final linesDot = Element3dGeometry.generateWeld3d(
        weld,
        start,
        end,
        pipeOuterDiameter: 108.0,
        style: WeldJointStyle.dot,
      );
      expect(linesDot.length, equals(1));
    });
  });

  group('Direct Branch Calculation and Visual Axis Rendering', () {
    test('Cut length is L_axial - R_main while startPoint stays at node axis', () {
      final net = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      final nBranch = Node3D(id: 'nBranch', x: 1000, y: 600, z: 0);

      net.nodes['n1'] = n1;
      net.nodes['n2'] = n2;
      net.nodes['n3'] = n3;
      net.nodes['nBranch'] = nBranch;

      // Магистраль DN150 (наружный диаметр 159 мм, радиус 79.5 мм)
      net.segments['s_m1'] = PipeSegment(id: 's_m1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'T1', dn: 150);
      net.segments['s_m2'] = PipeSegment(id: 's_m2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'T1', dn: 150);

      // Ответвление DN80, длина 600 мм
      net.segments['s_b'] = PipeSegment(id: 's_b', startNodeId: 'n2', endNodeId: 'nBranch', systemId: 'T1', dn: 80);

      net.fittings['n2'] = Fitting(
        id: 'fit_dir',
        nodeId: 'n2',
        fittingType: FittingType.directBranch,
        dn: 150,
        dnSecondary: 80,
        radiusMm: 0.0,
        cutsMainPipe: false,
        weldType: WeldType.u18,
      );

      net.recalculateSpools();

      final spoolBranch = net.spools.values.firstWhere((s) => s.segmentId == 's_b');

      // Фактическая заготовительная длина: L_заг = 600 - (159 / 2) = 600 - 79.5 = 520.5 мм
      expect(spoolBranch.cutLengthMm, closeTo(520.5, 0.5));

      // Для визуальной отрисовки труба должна доходить строго до оси магистрали (n2: x=1000, y=0, z=0)
      expect(spoolBranch.startPoint?.x, closeTo(1000.0, 0.1));
      expect(spoolBranch.startPoint?.y, closeTo(0.0, 0.1));
      expect(spoolBranch.startPoint?.z, closeTo(0.0, 0.1));
    });
  });

  group('Canvas Painters Rendering with Weld Styles and Amber Glow', () {
    late PipingNetwork net;
    late AxonometryProjector projector;

    setUp(() {
      net = PipingNetwork();
      projector = AxonometryProjector();

      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 2000, y: 0, z: 0);
      final nBranch = Node3D(id: 'nBranch', x: 1000, y: 800, z: 0);

      net.nodes['n1'] = n1;
      net.nodes['n2'] = n2;
      net.nodes['n3'] = n3;
      net.nodes['nBranch'] = nBranch;

      net.segments['s_m1'] = PipeSegment(id: 's_m1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'T1', dn: 100);
      net.segments['s_m2'] = PipeSegment(id: 's_m2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'T1', dn: 100);
      net.segments['s_b'] = PipeSegment(id: 's_b', startNodeId: 'n2', endNodeId: 'nBranch', systemId: 'T1', dn: 50);

      net.fittings['n2'] = Fitting(
        id: 'fit_dir',
        nodeId: 'n2',
        fittingType: FittingType.directBranch,
        dn: 100,
        dnSecondary: 50,
        radiusMm: 0.0,
        cutsMainPipe: false,
        weldType: WeldType.u18,
      );

      // Создаем сварной шов на ответвлении
      net.weldJoints['w_branch'] = WeldJoint(
        id: 'w_branch',
        segmentId: 's_b',
        ratio: 0.0,
        number: 1,
        stamp: 'ИВ-01',
        weldType: WeldType.u18,
      );

      // Создаем стык посреди прямой трубы
      net.weldJoints['w_line'] = WeldJoint(
        id: 'w_line',
        segmentId: 's_m1',
        ratio: 0.5,
        number: 2,
        stamp: 'ИВ-02',
      );
    });

    test('AnnotationPainter renders weld joints in all styles without exception', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      for (final style in WeldJointStyle.values) {
        net.defaultWeldStyle = style;

        expect(
          () => AnnotationPainter.paint(
            canvas,
            projector,
            net,
            null,
            true, // showWelds
            true, // showCallouts
            selectedWeldId: 'w_branch', // amber glow on selected weld
          ),
          returnsNormally,
        );
      }
    });

    test('FittingPainter renders direct branch with weld joint style and amber glow without exception', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      for (final style in WeldJointStyle.values) {
        net.defaultWeldStyle = style;

        expect(
          () => FittingPainter.paint(
            canvas,
            projector,
            net,
            'n2', // selectedNodeId -> amber glow on direct branch
            true,
          ),
          returnsNormally,
        );
      }
    });

    test('Perpendicular tick vector math verifies orthogonal dot product across all axes', () {
      // Для любой трубы с экранным вектором v = (dx, dy) засечка строится вдоль нормали:
      // normal = (-dy / len, dx / len), что дает dotProduct == 0 (строго 90°)
      final directions = [
        const Offset(200, 0), // Горизонтальная труба (Y в ГОСТ) -> нормаль строго вертикальна (0, 1)
        const Offset(0, 300), // Вертикальная труба (Z в ГОСТ) -> нормаль строго горизонтальна (-1, 0)
        const Offset(-150, -150), // Наклонная 45° (X в ГОСТ) -> нормаль под -45° (135°)
        const Offset(120, -80), // Произвольный пространственный наклон
      ];

      for (final v in directions) {
        final len = v.distance;
        final normal = Offset(-v.dy / len, v.dx / len);
        final dotProduct = v.dx * normal.dx + v.dy * normal.dy;
        expect(dotProduct.abs(), lessThan(1e-10));
        expect(normal.distance, closeTo(1.0, 1e-10));
      }
    });

    test('FittingPainter paints direct branch dash-dot centerline and suppresses fallback text when callouts exist', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Без сгенерированных callouts - вызывается нормально
      expect(
        () => FittingPainter.paint(
          canvas,
          projector,
          net,
          null,
          true,
        ),
        returnsNormally,
      );

      // Добавляем Callout в сеть
      net.callouts['c_fit'] = const Callout(
        id: 'c_fit',
        targetId: 'fit_dir',
        targetType: CalloutTargetType.fitting,
      );

      // С наличием callouts - подавляет нередактируемый текст
      expect(
        () => FittingPainter.paint(
          canvas,
          projector,
          net,
          null,
          true,
        ),
        returnsNormally,
      );
    });

    test('AnnotationPainter paints without uneditable SmartCallout.drawWeldCallout duplicates', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      expect(
        () => AnnotationPainter.paint(
          canvas,
          projector,
          net,
          null,
          true,
          true,
        ),
        returnsNormally,
      );
    });

    test('Element3dGeometry.generateDirectBranch3d generates axial centerline connecting node to contact seam', () {
      final nNode = net.nodes['n2']!;
      final nOther = net.nodes['nBranch']!;
      final fit = net.fittings['n2']!;

      final wireSegments = Element3dGeometry.generateDirectBranch3d(
        fit,
        nNode,
        nOther,
        mainOuterDiameter: 108.0,
        branchOuterDiameter: 57.0,
      );

      // Содержит как 12 сегментов кольца, так и 1 осевой сегмент сопряжения (всего 13)
      expect(wireSegments.length, equals(13));
      final centerline = wireSegments.firstWhere(
        (w) => (w.x1 - nNode.x).abs() < 0.1 && (w.y1 - nNode.y).abs() < 0.1 && (w.z1 - nNode.z).abs() < 0.1,
      );
      expect(centerline, isNotNull);
      // Конечная точка осевого отрезка лежит на расстоянии R_main = 54 мм от nNode (вдоль Y)
      expect(centerline.y2, closeTo(nNode.y + 54.0, 0.1));
    });
  });
}
