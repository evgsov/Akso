import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';

void main() {
  group('Task 5: Spool Callout & DXF Export Tests', () {
    test('formatCalloutTemplate resolves {L} to exact spool cut length and supports {NAME}, {SERIAL}', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2000, y: 2000, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
      );

      // Отвод 90 на n2: вычет T = 150 мм
      network.fittings['n2'] = const Fitting(
        id: 'fit_n2',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );

      network.recalculateSpools();
      expect(network.spools.length, equals(2));

      final spool1 = network.spools.values.firstWhere((s) => s.segmentId == 'seg1');
      expect(spool1.cutLengthMm, equals(1850.0));

      // 1. Выноска для сегмента seg1: {L} должна разрешаться в 1850 (длину реза катушки), а не 2000
      final segCalloutText = network.formatCalloutTemplate(
        CalloutTargetType.segment,
        'seg1',
        'Ø{DN} L={L}',
      );
      expect(segCalloutText, equals('Ø100 L=1850'));

      // 2. Назначаем катушке маркировку и заводской номер
      network.setSpoolMetadata(spool1.id, name: 'К-1', serialNumber: 'ПЛ-99');
      final spoolCalloutText = network.formatCalloutTemplate(
        CalloutTargetType.segment,
        spool1.id,
        '{NAME} L={L} {SERIAL}',
      );
      expect(spoolCalloutText, equals('К-1 L=1850 ПЛ-99'));
    });

    test('CalloutPainter.getTarget3DPoint anchors to spool midpoint', () {
      final network = PipingNetwork();
      network.nodes['n0'] = const Node3D(id: 'n0', x: 0, y: -1000, z: 0);
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);

      network.segments['seg0'] = const PipeSegment(
        id: 'seg0',
        startNodeId: 'n0',
        endNodeId: 'n1',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );

      // Отвод 90 на n1: вычет T = 150 мм в начале seg1
      network.fittings['n1'] = const Fitting(
        id: 'fit_n1',
        nodeId: 'n1',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );

      network.recalculateSpools();
      final spool = network.spools.values.firstWhere((s) => s.segmentId == 'seg1');
      // Spool идет от X=150 до X=2000. Середина = (150 + 2000)/2 = 1075
      expect(spool.startPoint?.x, closeTo(150.0, 0.01));
      expect(spool.endPoint?.x, closeTo(2000.0, 0.01));

      // Выноска на катушку
      final calloutSpool = Callout(
        id: 'c_spool',
        targetId: spool.id,
        targetType: CalloutTargetType.segment,
      );
      final anchorSpool = CalloutPainter.getTarget3DPoint(network, calloutSpool);
      expect(anchorSpool, isNotNull);
      expect(anchorSpool!.x, closeTo(1075.0, 0.01));

      // Выноска на сегмент seg1, у которого 1 катушка: тоже привязывается к 1075.0
      const calloutSeg = Callout(
        id: 'c_seg',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
      );
      final anchorSeg = CalloutPainter.getTarget3DPoint(network, calloutSeg);
      expect(anchorSeg, isNotNull);
      expect(anchorSeg!.x, closeTo(1075.0, 0.01));
    });

    test('DxfWriter exports centerline on АКСО_ОСИ_ТРАССЫ and physical spools on АКСО_ТРУБЫ', () {
      final network = PipingNetwork();
      // Два отвода встык: seg1 длиной 300 мм между n1 и n2, с отводами R=150 на обоих концах
      network.nodes['n0'] = const Node3D(id: 'n0', x: 0, y: -1000, z: 0);
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 300, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 300, y: 1000, z: 0);

      network.segments['seg_in'] = const PipeSegment(
        id: 'seg_in',
        startNodeId: 'n0',
        endNodeId: 'n1',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg_butt'] = const PipeSegment(
        id: 'seg_butt',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg_out'] = const PipeSegment(
        id: 'seg_out',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
      );

      network.fittings['n1'] = const Fitting(
        id: 'fit_n1',
        nodeId: 'n1',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );
      network.fittings['n2'] = const Fitting(
        id: 'fit_n2',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
      );

      network.recalculateSpools();
      // На seg_butt должно быть 0 катушек!
      expect(network.spools.values.where((s) => s.segmentId == 'seg_butt').length, equals(0));

      final dxf3D = DxfWriter.generate3dDxf(network);
      // Слой АКСО_ОСИ_ТРАССЫ должен присутствовать
      expect(dxf3D.contains(DxfWriter.toAutoCadString('АКСО_ОСИ_ТРАССЫ')), isTrue);

      final dxf2D = DxfWriter.generate2dGostAxonometryDxf(network);
      expect(dxf2D.contains(DxfWriter.toAutoCadString('АКСО_ОСИ_ТРАССЫ')), isTrue);
    });
  });
}
