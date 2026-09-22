import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/services/segment_positioning_service.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('SegmentPositioningService Unit Tests', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
      net.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Отопление',
        code: 'Т1',
        colorValue: 0xFFF44336,
        dxfAciColor: 1,
      );
    });

    test('Single vertical riser without fittings: position info and mutual recalculations', () {
      // Вертикальный стояк от 0 до 6000 мм (6.0 м)
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 6000);
      net.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );

      final w1 = net.addWeldJoint(segmentId: 's1', ratio: 0.5);

      final info = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        w1.ratio,
        currentElementId: w1.id,
      );

      expect(info.elevationM, closeTo(3.0, 0.001));
      expect(info.elevationString, equals('+3.000 м'));
      expect(info.isElevationEditable, isTrue);
      expect(info.lengthToPrevMm, closeTo(3000.0, 0.1));
      expect(info.lengthToNextMm, closeTo(3000.0, 0.1));
      expect(info.distanceFromStartMm, closeTo(3000.0, 0.1));
      expect(info.distanceToEndMm, closeTo(3000.0, 0.1));

      // 1. Изменение по высотной отметке Z = 4.500 м
      final newRatioZ = SegmentPositioningService.calculateRatioFromElevation(
        net,
        's1',
        4.5,
        currentElementId: w1.id,
      );
      expect(newRatioZ, closeTo(0.75, 0.001));

      final infoZ = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        newRatioZ,
        currentElementId: w1.id,
      );
      expect(infoZ.elevationM, closeTo(4.5, 0.001));
      expect(infoZ.lengthToPrevMm, closeTo(4500.0, 0.1));
      expect(infoZ.lengthToNextMm, closeTo(1500.0, 0.1));

      // 2. Изменение по длине предыдущей катушки L1 = 1200 мм
      final newRatioL1 = SegmentPositioningService.calculateRatioFromLengthToPrev(
        net,
        's1',
        1200.0,
        currentElementId: w1.id,
      );
      expect(newRatioL1, closeTo(1200.0 / 6000.0, 0.001));

      final infoL1 = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        newRatioL1,
        currentElementId: w1.id,
      );
      expect(infoL1.elevationM, closeTo(1.2, 0.001));
      expect(infoL1.lengthToPrevMm, closeTo(1200.0, 0.1));
      expect(infoL1.lengthToNextMm, closeTo(4800.0, 0.1));

      // 3. Изменение по длине следующей катушки L2 = 2000 мм
      final newRatioL2 = SegmentPositioningService.calculateRatioFromLengthToNext(
        net,
        's1',
        2000.0,
        currentElementId: w1.id,
      );
      expect(newRatioL2, closeTo((6000.0 - 2000.0) / 6000.0, 0.001));

      final infoL2 = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        newRatioL2,
        currentElementId: w1.id,
      );
      expect(infoL2.elevationM, closeTo(4.0, 0.001));
      expect(infoL2.lengthToPrevMm, closeTo(4000.0, 0.1));
      expect(infoL2.lengthToNextMm, closeTo(2000.0, 0.1));
    });

    test('Vertical riser with 90° elbow at base accounts for fitting deduction', () {
      // Горизонтальный подвод в n1 и вертикальный стояк n1->n2 (угол 90° в n1)
      net.nodes['n0'] = const Node3D(id: 'n0', x: -2000, y: 0, z: 0);
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 5000);

      net.segments['s0'] = const PipeSegment(id: 's0', startNodeId: 'n0', endNodeId: 'n1', systemId: 'sys1', dn: 100);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      net.recalculateSpools();

      // Отвод 90° в n1: вычет тангенса = 150 мм
      final w1 = net.addWeldJoint(segmentId: 's1', ratio: 0.4); // 2000 мм от n1
      final info = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        w1.ratio,
        currentElementId: w1.id,
      );

      expect(info.startDeductionMm, closeTo(150.0, 0.1));
      // Длина до отвода: 2000 - 150 = 1850 мм
      expect(info.lengthToPrevMm, closeTo(1850.0, 0.1));
      expect(info.prevItemLabel, contains('Отвод 90°'));
      // Длина до конца: 5000 - 2000 = 3000 мм
      expect(info.lengthToNextMm, closeTo(3000.0, 0.1));

      // Задаем длину первой катушки ровно 1500 мм
      final targetR = SegmentPositioningService.calculateRatioFromLengthToPrev(
        net,
        's1',
        1500.0,
        currentElementId: w1.id,
      );
      // Новая позиция от n1 = 150 + 1500 = 1650 мм
      expect(targetR, closeTo(1650.0 / 5000.0, 0.001));

      final updatedInfo = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        targetR,
        currentElementId: w1.id,
      );
      expect(updatedInfo.lengthToPrevMm, closeTo(1500.0, 0.1));
      expect(updatedInfo.elevationM, closeTo(1.65, 0.001));
    });

    test('Two welds on same segment: mutual boundaries and preventing overlap', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 6000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      net.addWeldJoint(segmentId: 's1', ratio: 0.3); // 1800 мм
      final w2 = net.addWeldJoint(segmentId: 's1', ratio: 0.7); // 4200 мм

      final infoW2 = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        w2.ratio,
        currentElementId: w2.id,
      );
      // Между w1 и w2: 4200 - 1800 = 2400 мм
      expect(infoW2.lengthToPrevMm, closeTo(2400.0, 0.1));
      expect(infoW2.prevItemLabel, contains('Стык №'));
      // До конца трубы: 6000 - 4200 = 1800 мм
      expect(infoW2.lengthToNextMm, closeTo(1800.0, 0.1));

      // Пытаемся опустить w2 ниже w1 (на отметку 1.0 м, когда w1 на 1.8 м)
      final clampedRatio = SegmentPositioningService.calculateRatioFromElevation(
        net,
        's1',
        1.0,
        currentElementId: w2.id,
        currentRatio: w2.ratio,
      );
      // Должен быть безопасно зажат чуть выше w1 (w1 = 1800 мм, clamp > 1801 мм)
      expect(clampedRatio * 6000.0, greaterThan(1800.0));
      expect(clampedRatio, lessThan(w2.ratio));
    });

    test('Valve positioning accounts for body length', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 6000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Задвижка Ду100 со строительной длиной 200 мм на ratio = 0.5 (центр на 3000 мм)
      final v1 = net.addValve(
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
      );
      net.updateValveLength(v1.id, 200.0);

      final info = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        v1.ratio,
        elementLengthMm: 200.0,
        currentElementId: v1.id,
      );

      // Катушка до задвижки: 3000 - 100 = 2900 мм
      expect(info.lengthToPrevMm, closeTo(2900.0, 0.1));
      // Катушка после задвижки: 6000 - (3000 + 100) = 2900 мм
      expect(info.lengthToNextMm, closeTo(2900.0, 0.1));

      // Задаем высоту оси задвижки 2.500 м
      final newRatio = SegmentPositioningService.calculateRatioFromElevation(
        net,
        's1',
        2.5,
        elementLengthMm: 200.0,
        currentElementId: v1.id,
      );
      expect(newRatio, closeTo(2500.0 / 6000.0, 0.001));

      final updatedInfo = SegmentPositioningService.getPositionInfo(
        net,
        's1',
        newRatio,
        elementLengthMm: 200.0,
        currentElementId: v1.id,
      );
      // Катушка до задвижки: 2500 - 100 = 2400 мм
      expect(updatedInfo.lengthToPrevMm, closeTo(2400.0, 0.1));
      // Катушка после задвижки: 6000 - 2600 = 3400 мм
      expect(updatedInfo.lengthToNextMm, closeTo(3400.0, 0.1));
    });

    test('Batch riser sectioning: by equal step', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 7000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Шаг 2500 мм снизу вверх
      final ratios = SegmentPositioningService.calculateRiserWeldRatiosByStep(
        net,
        's1',
        2500.0,
        fromBottom: true,
      );
      // Ожидаем 2 стыка: на 2500 мм и 5000 мм, остаток 2000 мм
      expect(ratios.length, equals(2));
      expect(ratios[0] * 7000.0, closeTo(2500.0, 0.1));
      expect(ratios[1] * 7000.0, closeTo(5000.0, 0.1));

      final previews = SegmentPositioningService.previewSections(net, 's1', ratios);
      expect(previews.length, equals(3));
      expect(previews[0].cutLengthMm, closeTo(2500.0, 0.1));
      expect(previews[1].cutLengthMm, closeTo(2500.0, 0.1));
      expect(previews[2].cutLengthMm, closeTo(2000.0, 0.1));
    });

    test('Batch riser sectioning: by floor elevations', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 9000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Отметки перекрытий 2.800 м и 5.600 м
      final ratios = SegmentPositioningService.calculateRiserWeldRatiosByElevations(
        net,
        's1',
        [2.8, 5.6],
      );
      expect(ratios.length, equals(2));
      expect(ratios[0] * 9000.0, closeTo(2800.0, 0.1));
      expect(ratios[1] * 9000.0, closeTo(5600.0, 0.1));

      final previews = SegmentPositioningService.previewSections(net, 's1', ratios);
      expect(previews.length, equals(3));
      expect(previews[0].cutLengthMm, closeTo(2800.0, 0.1));
      expect(previews[0].startElevationM, closeTo(0.0, 0.001));
      expect(previews[0].endElevationM, closeTo(2.8, 0.001));

      expect(previews[1].cutLengthMm, closeTo(2800.0, 0.1));
      expect(previews[1].startElevationM, closeTo(2.8, 0.001));
      expect(previews[1].endElevationM, closeTo(5.6, 0.001));

      expect(previews[2].cutLengthMm, closeTo(3400.0, 0.1));
      expect(previews[2].startElevationM, closeTo(5.6, 0.001));
      expect(previews[2].endElevationM, closeTo(9.0, 0.001));
    });

    test('Batch riser sectioning: by spool lengths chain', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 6500);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      final ratios = SegmentPositioningService.calculateRiserWeldRatiosByLengths(
        net,
        's1',
        [1500.0, 2500.0],
        fromBottom: true,
      );
      expect(ratios.length, equals(2));
      expect(ratios[0] * 6500.0, closeTo(1500.0, 0.1));
      expect(ratios[1] * 6500.0, closeTo(4000.0, 0.1));

      final previews = SegmentPositioningService.previewSections(net, 's1', ratios);
      expect(previews.length, equals(3));
      expect(previews[0].cutLengthMm, closeTo(1500.0, 0.1));
      expect(previews[1].cutLengthMm, closeTo(2500.0, 0.1));
      expect(previews[2].cutLengthMm, closeTo(2500.0, 0.1)); // 6500 - 4000 = 2500
    });
  });

  group('PipingInputController Positioning & Riser Sectioning Tests', () {
    test('updateValvePositionByElevation and toggleValveElevationCallout', () {
      final net = PipingNetwork();
      net.systems['sys1'] = const PipingSystem(id: 'sys1', name: 'Система 1', code: 'В1', colorValue: 0xFF2196F3, dxfAciColor: 5);
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 5000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      final v = net.addValve(segmentId: 's1', ratio: 0.5, valveType: ValveType.gateValve, dn: 100);
      net.recalculateSpools();

      final controller = PipingInputController(network: net);

      // 1. Изменяем отметку арматуры на 3.500 м
      controller.updateValvePositionByElevation(v.id, 3.5);
      final updatedV = controller.network.valves[v.id]!;
      expect(updatedV.ratio, closeTo(3500.0 / 5000.0, 0.001));

      // 2. Включаем выноску высотной отметки на арматуре
      expect(controller.valveHasElevationCallout(v.id), isFalse);
      final added = controller.toggleValveElevationCallout(v.id);
      expect(added, isTrue);
      expect(controller.valveHasElevationCallout(v.id), isTrue);

      final callout = controller.getValveElevationCallout(v.id)!;
      final text = controller.network.generateCalloutText(callout, {});
      expect(text, equals('+3.500'));

      // 3. Отключаем выноску
      final removed = controller.toggleValveElevationCallout(v.id);
      expect(removed, isFalse);
      expect(controller.valveHasElevationCallout(v.id), isFalse);

      controller.dispose();
    });

    test('divideRiserIntoSpools generates welds and correct spool cuts', () {
      final net = PipingNetwork();
      net.systems['sys1'] = const PipingSystem(id: 'sys1', name: 'Система 1', code: 'В1', colorValue: 0xFF2196F3, dxfAciColor: 5);
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 9000);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      final controller = PipingInputController(network: net);

      final ratios = SegmentPositioningService.calculateRiserWeldRatiosByStep(
        controller.network,
        's1',
        3000.0,
      );
      expect(ratios.length, equals(2)); // Стыки на 3.0 м и 6.0 м

      controller.divideRiserIntoSpools('s1', ratios, stamp: 'ИВ-99');

      final welds = controller.network.weldJoints.values.where((w) => w.segmentId == 's1').toList();
      expect(welds.length, equals(2));
      expect(welds.every((w) => w.stamp == 'ИВ-99'), isTrue);

      final spools = controller.network.spools.values.where((s) => s.segmentId == 's1').toList();
      expect(spools.length, equals(3));
      expect(spools[0].cutLengthMm, closeTo(3000.0, 1.0));
      expect(spools[1].cutLengthMm, closeTo(3000.0, 1.0));
      expect(spools[2].cutLengthMm, closeTo(3000.0, 1.0));

      // Проверяем undo: откат возвращает исходное состояние сети
      controller.undo();
      expect(controller.network.weldJoints.values.where((w) => w.segmentId == 's1').length, equals(0));

      controller.dispose();
    });
  });
}
