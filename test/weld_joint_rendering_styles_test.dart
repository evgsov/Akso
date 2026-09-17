import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
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
  });

  group('Element3dGeometry 3D Weld Wireframes', () {
    test('generateWeld3d produces lines according to style', () {
      final start = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final end = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      final weld = WeldJoint(id: 'w1', segmentId: 's1', ratio: 0.5, number: 1, stamp: 'W');

      // Tick: 1 линия засечки
      final linesTick = Element3dGeometry.generateWeld3d(
        weld,
        start,
        end,
        pipeOuterDiameter: 108.0,
        style: WeldJointStyle.tick,
      );
      expect(linesTick.length, equals(1));
      expect(linesTick[0].layer, equals(Element3dGeometry.layerWelds));

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
  });
}
