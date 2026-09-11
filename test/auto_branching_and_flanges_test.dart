import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('Auto-Branching, Flanges, Materials & MTO Tests', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('Прямая врезка (У18) не делит катушку магистрали и не производит вычет', () {
      // Создаем магистраль 3000 мм Ду100
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 100,
        material: '09Г2С',
      );

      // Ответвление Ду50 в сторону Y=1000
      network.nodes['n_branch'] = const Node3D(id: 'n_branch', x: 1500, y: 1000, z: 0);
      final fit = network.connectBranchToSegment(
        hostSegmentId: 'seg1',
        ratio: 0.5,
        branchEndNodeId: 'n_branch',
        branchDn: 50,
        useDirectBranch: true,
      );

      expect(fit, isNotNull);
      expect(fit!.fittingType, equals(FittingType.directBranch));
      expect(fit.cutsMainPipe, isFalse);
      expect(fit.weldType, equals(WeldType.u18));
      expect(fit.material, equals('09Г2С'));

      // Катушки магистрали (seg1_a и seg1_b по 1500 мм) не должны иметь вычета от врезки
      final spoolA = network.spools.values.firstWhere((s) => s.segmentId == 'seg1_a');
      final spoolB = network.spools.values.firstWhere((s) => s.segmentId == 'seg1_b');
      expect(spoolA.cutLengthMm, equals(1500.0));
      expect(spoolB.cutLengthMm, equals(1500.0));
      expect(spoolA.material, equals('09Г2С'));
    });

    test('Стандартный тройник (ГОСТ 17376) производит вычет из обеих сторон катушки', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 100,
        material: 'Сталь 20',
      );

      network.nodes['n_branch'] = const Node3D(id: 'n_branch', x: 1500, y: 1000, z: 0);
      final fit = network.connectBranchToSegment(
        hostSegmentId: 'seg1',
        ratio: 0.5,
        branchEndNodeId: 'n_branch',
        branchDn: 100,
        useDirectBranch: false,
      );

      expect(fit, isNotNull);
      expect(fit!.fittingType, equals(FittingType.tee));
      expect(fit.cutsMainPipe, isTrue);

      // Для тройника Ду100 радиус/вычет равен 100 мм (1.0 * DN)
      final spoolA = network.spools.values.firstWhere((s) => s.segmentId == 'seg1_a');
      expect(spoolA.cutLengthMm, equals(1400.0)); // 1500 - 100 = 1400
    });

    test('Врезка фланцевой пары (ГОСТ 33259) формирует стыки и уменьшает длину катушек', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 80,
        material: '12Х18Н10Т',
      );

      final flange = network.insertFlange(
        segmentId: 'seg1',
        ratio: 0.5,
        isPair: true,
        pressurePn: 25,
      );

      expect(flange, isNotNull);
      expect(flange!.fittingType, equals(FittingType.flange));
      expect(flange.isFlangePair, isTrue);
      expect(flange.pressurePn, equals(25));
      expect(flange.material, equals('12Х18Н10Т'));

      // Должны появиться сварные швы по обе стороны
      expect(network.weldJoints.length, greaterThanOrEqualTo(2));
      final weld = network.weldJoints.values.first;
      expect(weld.steelGrade, equals('12Х18Н10Т'));

      // Катушки укорачиваются на строительную толщину фланцев
      final spoolA = network.spools.values.firstWhere((s) => s.segmentId == 'seg1_a');
      expect(spoolA.cutLengthMm, lessThan(1000.0));
    });

    test('Формирование Спецификации оборудования и материалов (СО по ГОСТ 21.110-2013)', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 4000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 80,
        material: '09Г2С',
      );

      network.insertFlange(segmentId: 'seg1', ratio: 0.5, isPair: true, pressurePn: 16);

      final mtoCsv = DxfWriter.generateMtoCsv(network);
      expect(mtoCsv.contains('Поз.;Наименование и техническая характеристика;Тип, марка;ГОСТ / ТУ;Материал;Кол-во;Ед. изм.;Примечание'), isTrue);
      expect(mtoCsv.contains('09Г2С'), isTrue);
      expect(mtoCsv.contains('Труба стальная'), isTrue);
      expect(mtoCsv.contains('Фланцевая пара Ду80 Ру16'), isTrue);
      expect(mtoCsv.contains('ГОСТ 33259-2015'), isTrue);
    });

    test('2D и 3D DXF экспорт поддерживает слои фланцев и врезок', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_b1',
        dn: 50,
      );

      network.insertFlange(segmentId: 'seg1', ratio: 0.5, isPair: true);

      final dxf2d = DxfWriter.generate2dGostAxonometryDxf(network);
      expect(dxf2d.contains('АКСО_ФЛАНЦЫ'), isTrue);

      final dxf3d = DxfWriter.generate3dDxf(network);
      expect(dxf3d.contains('АКСО_ФЛАНЦЫ'), isTrue);
    });
  });
}
