import 'dart:math' as math;
import 'dart:ui';
import '../../core/math/axonometry_projector.dart';
import '../../domain/enums/fitting_type.dart';
import '../../domain/enums/inspection_method.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/enums/valve_type.dart';
import '../../domain/enums/weld_type.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/piping_network.dart';

/// Генератор файлов AutoCAD DXF (ASCII R2000 / AC1015)
class DxfWriter {
  /// Генерация 3D DXF файла (пространственные трубы, слои по системам, 3D-отметки)
  static String generate3dDxf(PipingNetwork network) {
    final buffer = StringBuffer();

    _writeHeader(buffer);
    _writeLayers(buffer, network);
    _writeBlocks(buffer);

    buffer.writeln('  0\nSECTION\n  2\nENTITIES');

    // 1. Отрезки труб в 3D
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final sys = network.systems[seg.systemId];
      final layerName = sys != null ? 'АКСО_${sys.code}' : 'АКСО_ТРУБЫ';

      _write3dLine(
        buffer,
        layer: layerName,
        x1: start.x,
        y1: start.y,
        z1: start.z,
        x2: end.x,
        y2: end.y,
        z2: end.z,
      );

      // Диаметр трубы как текст в 3D
      final midX = (start.x + end.x) / 2;
      final midY = (start.y + end.y) / 2;
      final midZ = (start.z + end.z) / 2 + 50.0;
      _writeText(
        buffer,
        layer: 'АКСО_ДИАМЕТРЫ',
        text: seg.shortCallout,
        x: midX,
        y: midY,
        z: midZ,
        height: 60.0,
      );
    }

    // 2. Сварные стыки в 3D
    for (final weld in network.weldJoints.values) {
      final seg = network.segments[weld.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final pos = weld.calculatePosition(start, end);
      _writePoint(buffer, layer: 'АКСО_СВАРКА', x: pos.x, y: pos.y, z: pos.z);
      _writeText(
        buffer,
        layer: 'АКСО_СВАРКА_ТЕКСТ',
        text: '№${weld.number} (${weld.stamp})',
        x: pos.x,
        y: pos.y,
        z: pos.z + 80.0,
        height: 50.0,
      );
    }

    // 3. Арматура в 3D
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final pos = valve.calculatePosition(start, end);
      _writeText(
        buffer,
        layer: 'АКСО_АРМАТУРА',
        text: valve.name,
        x: pos.x,
        y: pos.y,
        z: pos.z + 100.0,
        height: 70.0,
      );
    }

    // 4. Высотные отметки
    for (final node in network.nodes.values) {
      _writeText(
        buffer,
        layer: 'АКСО_ОТМЕТКИ',
        text: node.elevationString,
        x: node.x,
        y: node.y,
        z: node.z + 30.0,
        height: 50.0,
      );
    }

    // 5. Переходы в 3D
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final typeName = fit.fittingType == FittingType.reducerEccentric ? 'Переход эксц.' : 'Переход конц.';
        _writePoint(buffer, layer: 'АКСО_ПЕРЕХОДЫ', x: node.x, y: node.y, z: node.z);
        _writeText(
          buffer,
          layer: 'АКСО_ПЕРЕХОДЫ_ТЕКСТ',
          text: '$typeName Ду${fit.dn}xДу${fit.dnSecondary}',
          x: node.x,
          y: node.y,
          z: node.z + 80.0,
          height: 50.0,
        );
      }
    }

    // 6. Фланцы и врезки в 3D
    for (final fit in network.fittings.values) {
      final node = network.nodes[fit.nodeId];
      if (node == null) continue;
      if (fit.fittingType == FittingType.flange) {
        _writePoint(buffer, layer: 'АКСО_ФЛАНЦЫ', x: node.x, y: node.y, z: node.z);
        _writeText(
          buffer,
          layer: 'АКСО_ФЛАНЦЫ_ТЕКСТ',
          text: fit.displayName,
          x: node.x,
          y: node.y,
          z: node.z + 80.0,
          height: 45.0,
        );
      } else if (fit.fittingType == FittingType.directBranch) {
        _writePoint(buffer, layer: 'АКСО_ВРЕЗКИ', x: node.x, y: node.y, z: node.z);
        _writeText(
          buffer,
          layer: 'АКСО_СВАРКА_ТЕКСТ',
          text: 'Врезка У18 (Ду${fit.dnSecondary ?? fit.dn})',
          x: node.x,
          y: node.y,
          z: node.z + 80.0,
          height: 45.0,
        );
      }
    }

    // 7. Строительные оси в 3D
    for (final axis in network.axes.values) {
      _write3dLine(
        buffer,
        layer: 'АКСО_ОСИ',
        x1: axis.startPoint.x,
        y1: axis.startPoint.y,
        z1: axis.startPoint.z,
        x2: axis.endPoint.x,
        y2: axis.endPoint.y,
        z2: axis.endPoint.z,
      );
      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        _writePoint(buffer, layer: 'АКСО_ОСИ', x: axis.startPoint.x, y: axis.startPoint.y, z: axis.startPoint.z);
        _writeText(
          buffer,
          layer: 'АКСО_ОСИ_ТЕКСТ',
          text: axis.label,
          x: axis.startPoint.x,
          y: axis.startPoint.y,
          z: axis.startPoint.z + 50.0,
          height: 80.0,
        );
      }
    }

    buffer.writeln('  0\nENDSEC\n  0\nEOF');
    return buffer.toString();
  }

  /// Генерация плоского 2D DXF чертежа в аксонометрии по ГОСТ 21.602 / СПДС
  /// Готовый к печати плоский чертеж с выносками, полочками, клеймами сварки
  static String generate2dGostAxonometryDxf(
    PipingNetwork network, {
    ProjectionType projection = ProjectionType.gostFrontal45,
  }) {
    final buffer = StringBuffer();
    final projector = AxonometryProjector(projectionType: projection, scale: 1.0);

    _writeHeader(buffer);
    _writeLayers(buffer, network);
    _writeBlocks(buffer);

    buffer.writeln('  0\nSECTION\n  2\nENTITIES');

    // 1. Отрезки труб в проекции ГОСТ
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = _projectTo2d(projector, start);
      final p2 = _projectTo2d(projector, end);

      final sys = network.systems[seg.systemId];
      final layerName = sys != null ? 'АКСО_${sys.code}' : 'АКСО_ТРУБЫ';

      _write2dLine(buffer, layer: layerName, x1: p1.dx, y1: p1.dy, x2: p2.dx, y2: p2.dy);

      // Выноска диаметра (горизонтальный текст над трубой)
      final midX = (p1.dx + p2.dx) / 2;
      final midY = (p1.dy + p2.dy) / 2 + 30.0;
      _writeText(
        buffer,
        layer: 'АКСО_ДИАМЕТРЫ',
        text: seg.shortCallout,
        x: midX - 30.0,
        y: midY,
        z: 0.0,
        height: 50.0,
      );

      // Уклон трубы
      if (seg.slope > 0.0001) {
        _writeText(
          buffer,
          layer: 'АКСО_УКЛОНЫ',
          text: 'i=${seg.slope.toStringAsFixed(3)}',
          x: midX - 40.0,
          y: midY - 60.0,
          z: 0.0,
          height: 40.0,
        );
      }
    }

    // 2. Арматура в 2D (УГО по ГОСТ)
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = _projectTo2d(projector, start);
      final p2 = _projectTo2d(projector, end);

      final vx = p1.dx + (p2.dx - p1.dx) * valve.ratio;
      final vy = p1.dy + (p2.dy - p1.dy) * valve.ratio;
      final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);

      _writeGostValve2d(buffer, center: Offset(vx, vy), angle: angle, type: valve.valveType);
    }

    // 3. Сварные стыки и выноски по ГОСТ (горизонтальная полочка)
    for (final weld in network.weldJoints.values) {
      final seg = network.segments[weld.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = _projectTo2d(projector, start);
      final p2 = _projectTo2d(projector, end);

      final wx = p1.dx + (p2.dx - p1.dx) * weld.ratio;
      final wy = p1.dy + (p2.dy - p1.dy) * weld.ratio;

      // Точка стыка
      _writeCircle(buffer, layer: 'АКСО_СВАРКА', cx: wx, cy: wy, radius: 10.0);

      // Наклонная ножка выноски + горизонтальная полочка
      final leaderEndX = wx + 120.0;
      final leaderEndY = wy + 120.0;
      final shelfEndX = leaderEndX + 180.0;

      _write2dLine(buffer, layer: 'АКСО_СВАРКА_ВЫНОСКИ', x1: wx, y1: wy, x2: leaderEndX, y2: leaderEndY);
      _write2dLine(buffer, layer: 'АКСО_СВАРКА_ВЫНОСКИ', x1: leaderEndX, y1: leaderEndY, x2: shelfEndX, y2: leaderEndY);

      // Текст над полочкой: № шва и тип шва
      _writeText(
        buffer,
        layer: 'АКСО_СВАРКА_ТЕКСТ',
        text: '№${weld.number} ${weld.weldType.shortName}',
        x: leaderEndX + 10.0,
        y: leaderEndY + 15.0,
        z: 0.0,
        height: 40.0,
      );

      // Текст под полочкой: клеймо сварщика
      _writeText(
        buffer,
        layer: 'АКСО_СВАРКА_ТЕКСТ',
        text: 'Кл. ${weld.stamp}',
        x: leaderEndX + 10.0,
        y: leaderEndY - 45.0,
        z: 0.0,
        height: 35.0,
      );
    }

    // 4. Отметки уровней по ГОСТ 21.101 (∇ +2.500)
    for (final node in network.nodes.values) {
      final p = _projectTo2d(projector, node);

      // Треугольный флажок отметки
      const flagSize = 35.0;
      const shelfLen = 160.0;

      // Треугольник
      _write2dLine(buffer, layer: 'АКСО_ОТМЕТКИ', x1: p.dx, y1: p.dy, x2: p.dx - flagSize * 0.7, y2: p.dy + flagSize);
      _write2dLine(buffer, layer: 'АКСО_ОТМЕТКИ', x1: p.dx - flagSize * 0.7, y1: p.dy + flagSize, x2: p.dx + flagSize * 0.7, y2: p.dy + flagSize);
      _write2dLine(buffer, layer: 'АКСО_ОТМЕТКИ', x1: p.dx + flagSize * 0.7, y1: p.dy + flagSize, x2: p.dx, y2: p.dy);

      // Ножка и горизонтальная полка
      _write2dLine(buffer, layer: 'АКСО_ОТМЕТКИ', x1: p.dx, y1: p.dy + flagSize, x2: p.dx, y2: p.dy + flagSize + 15.0);
      _write2dLine(buffer, layer: 'АКСО_ОТМЕТКИ', x1: p.dx, y1: p.dy + flagSize + 15.0, x2: p.dx + shelfLen, y2: p.dy + flagSize + 15.0);

      // Текст отметки
      _writeText(
        buffer,
        layer: 'АКСО_ОТМЕТКИ_ТЕКСТ',
        text: node.elevationString,
        x: p.dx + 15.0,
        y: p.dy + flagSize + 25.0,
        z: 0.0,
        height: 45.0,
      );
    }

    // 5. Переходы в 2D (УГО по ГОСТ - трапеция)
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final center = _projectTo2d(projector, node);

        final connectedNodes = _getConnectedNodes(network, node);
        double angle = 0.0;
        if (connectedNodes.isNotEmpty) {
          final other = connectedNodes.first;
          final pOther = _projectTo2d(projector, other);
          angle = math.atan2(center.dy - pOther.dy, center.dx - pOther.dx);
        }

        final isEcc = fit.fittingType == FittingType.reducerEccentric;
        _writeGostReducer2d(
          buffer,
          center: center,
          angle: angle,
          dn1: fit.dn,
          dn2: fit.dnSecondary ?? fit.dn,
          isEccentric: isEcc,
        );
      }
    }

    // 6. Фланцы и врезки в 2D (УГО по ГОСТ)
    for (final fit in network.fittings.values) {
      final node = network.nodes[fit.nodeId];
      if (node == null) continue;
      final center = _projectTo2d(projector, node);

      if (fit.fittingType == FittingType.flange) {
        final connectedNodes = _getConnectedNodes(network, node);
        double angle = 0.0;
        if (connectedNodes.isNotEmpty) {
          final other = connectedNodes.first;
          final pOther = _projectTo2d(projector, other);
          angle = math.atan2(center.dy - pOther.dy, center.dx - pOther.dx);
        }

        _writeGostFlange2d(
          buffer,
          center: center,
          angle: angle,
          dn: fit.dn,
          isPair: fit.isFlangePair,
        );
      } else if (fit.fittingType == FittingType.directBranch) {
        _writeCircle(buffer, layer: 'АКСО_ВРЕЗКИ', cx: center.dx, cy: center.dy, radius: 12.0);
        _writeText(
          buffer,
          layer: 'АКСО_СВАРКА_ТЕКСТ',
          text: 'Врезка У18 (Ду${fit.dnSecondary ?? fit.dn})',
          x: center.dx + 15.0,
          y: center.dy + 15.0,
          z: 0.0,
          height: 35.0,
        );
      }
    }

    // 7. Строительные оси в 2D
    for (final axis in network.axes.values) {
      final p1 = _projectTo2d(projector, axis.startPoint);
      final p2 = _projectTo2d(projector, axis.endPoint);
      _write2dLine(buffer, layer: 'АКСО_ОСИ', x1: p1.dx, y1: p1.dy, x2: p2.dx, y2: p2.dy);
      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        const circleR = 40.0;
        _writeCircle(buffer, layer: 'АКСО_ОСИ', cx: p1.dx, cy: p1.dy, radius: circleR);
        _writeText(
          buffer,
          layer: 'АКСО_ОСИ_ТЕКСТ',
          text: axis.label,
          x: p1.dx - 15.0,
          y: p1.dy - 15.0,
          z: 0.0,
          height: 35.0,
        );
      }
    }

    buffer.writeln('  0\nENDSEC\n  0\nEOF');
    return buffer.toString();
  }

  /// Формирование текста Сварочного журнала (CSV)
  static String generateWeldJournalCsv(PipingNetwork network) {
    final buffer = StringBuffer();
    buffer.writeln('№ шва;Сегмент;Диаметр DN;Марка стали;Сварочные материалы;Тип шва;Клеймо сварщика;Метод контроля;Дата;Результат');

    final welds = network.weldJoints.values.toList()..sort((a, b) => a.number.compareTo(b.number));
    for (final w in welds) {
      final seg = network.segments[w.segmentId];
      final dn = seg != null ? 'Ду${seg.dn}' : '—';
      buffer.writeln(
        '${w.number};${w.segmentId};$dn;${w.steelGrade};${w.electrodeGrade};${w.weldType.gostCode};${w.stamp};${w.inspectionMethod.displayName};${w.date};${w.notes}',
      );
    }
    return buffer.toString();
  }

  /// Формирование текста Ведомости трубных заготовок / катушек (CSV)
  static String generateSpoolsCsv(PipingNetwork network) {
    final buffer = StringBuffer();
    buffer.writeln('№ катушки;Диаметр DN;Стенка S (мм);Длина реза (мм);Материал');

    final spools = network.spools.values.toList();
    for (final sp in spools) {
      buffer.writeln(
        '${sp.number};Ду${sp.dn};${sp.wallThickness.toStringAsFixed(1)};${sp.cutLengthMm.toStringAsFixed(0)};${sp.material}',
      );
    }
    return buffer.toString();
  }

  /// Формирование Спецификации оборудования, изделий и материалов (СО по ГОСТ 21.110-2013) в формате CSV
  static String generateMtoCsv(PipingNetwork network) {
    final buffer = StringBuffer();
    buffer.writeln('Поз.;Наименование и техническая характеристика;Тип, марка;ГОСТ / ТУ;Материал;Кол-во;Ед. изм.;Примечание');

    int itemNum = 1;

    // 1. Трубы стальные (группировка по DN, толщине стенки и марке стали)
    final pipeMap = <String, double>{};
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;
      final lenM = start.distanceTo(end) / 1000.0;
      final dim = network.pipeCatalog.getDimension(seg.dn);
      final std = dim?.standard ?? 'ГОСТ 8732-78';
      final key = 'Труба стальная ${seg.formattedSize}|$std|${seg.material}';
      pipeMap[key] = (pipeMap[key] ?? 0.0) + lenM;
    }

    for (final entry in pipeMap.entries) {
      final parts = entry.key.split('|');
      final desc = parts[0];
      final std = parts[1];
      final mat = parts[2];
      buffer.writeln(
        '${itemNum++};$desc;—;$std;$mat;${entry.value.toStringAsFixed(2)};м;Строительный метраж',
      );
    }

    // 2. Фасонные детали (отводы, тройники, переходы, фланцы)
    final fittingMap = <String, int>{};
    for (final fit in network.fittings.values) {
      final key = '${fit.displayName}|${fit.standard ?? "ГОСТ"}|${fit.material}';
      fittingMap[key] = (fittingMap[key] ?? 0) + 1;
    }

    for (final entry in fittingMap.entries) {
      final parts = entry.key.split('|');
      final name = parts[0];
      final std = parts[1];
      final mat = parts[2];
      buffer.writeln(
        '${itemNum++};$name;—;$std;$mat;${entry.value};шт.;Фасонные детали',
      );
    }

    // 3. Трубопроводная арматура (задвижки, затворы, краны, фильтры, КИП)
    final valveMap = <String, int>{};
    for (final v in network.valves.values) {
      final key = '${v.name}|${v.valveType.displayName}|Ду${v.dn}';
      valveMap[key] = (valveMap[key] ?? 0) + 1;
    }

    for (final entry in valveMap.entries) {
      final parts = entry.key.split('|');
      final name = parts[0];
      final type = parts[1];
      final dn = parts[2];
      buffer.writeln(
        '${itemNum++};$name;$type;$dn;Чугун / Сталь;${entry.value};шт.;Запорно-регулирующая арматура',
      );
    }

    // 4. Сварные соединения (сводка стыков по типам швов)
    final weldSummary = <String, int>{};
    for (final w in network.weldJoints.values) {
      final key = '${w.weldType.gostCode} (${w.steelGrade})';
      weldSummary[key] = (weldSummary[key] ?? 0) + 1;
    }

    for (final entry in weldSummary.entries) {
      buffer.writeln(
        '${itemNum++};Сварное соединение ${entry.key};—;ГОСТ 16037-80;—;${entry.value};стыков;Монтажная сварка',
      );
    }

    return buffer.toString();
  }

  // --- Вспомогательные DXF примитивы ---

  static List<Node3D> _getConnectedNodes(PipingNetwork network, Node3D targetNode) {
    final connected = network.getConnectedSegments(targetNode.id);
    final result = <Node3D>[];
    for (final seg in connected) {
      final otherId = seg.startNodeId == targetNode.id ? seg.endNodeId : seg.startNodeId;
      final other = network.nodes[otherId];
      if (other != null) {
        result.add(other);
      }
    }
    return result;
  }

  static Offset _projectTo2d(AxonometryProjector projector, Node3D node) {
    // В CAD Y направлен вверх
    double rawX2d = 0.0;
    double rawY2d = 0.0;

    const cos45 = 0.70710678118;
    const sin45 = 0.70710678118;

    if (projector.projectionType == ProjectionType.gostMirrored45) {
      rawX2d = -node.y + (node.x * 0.5 * cos45);
      rawY2d = node.z - (node.x * 0.5 * sin45);
    } else if (projector.projectionType == ProjectionType.iso30) {
      const cos30 = 0.86602540378;
      const sin30 = 0.5;
      rawX2d = (node.y - node.x) * cos30;
      rawY2d = node.z + (node.x + node.y) * sin30;
    } else {
      // Стандартный ГОСТ 45°
      rawX2d = node.y - (node.x * 0.5 * cos45);
      rawY2d = node.z - (node.x * 0.5 * sin45);
    }

    return Offset(rawX2d, rawY2d);
  }

  static void _writeHeader(StringBuffer b) {
    b.writeln('  0\nSECTION\n  2\nHEADER\n  9\n\$ACADVER\n  1\nAC1015\n  9\n\$INSUNITS\n 70\n4\n  0\nENDSEC');
  }

  static void _writeLayers(StringBuffer b, PipingNetwork net) {
    b.writeln('  0\nSECTION\n  2\nTABLES\n  0\nTABLE\n  2\nLAYER\n 70\n10');

    // Базовые слои
    _writeLayerEntry(b, '0', 7);
    _writeLayerEntry(b, 'АКСО_ОТМЕТКИ', 2); // Yellow
    _writeLayerEntry(b, 'АКСО_ОТМЕТКИ_ТЕКСТ', 7);
    _writeLayerEntry(b, 'АКСО_СВАРКА', 1); // Red
    _writeLayerEntry(b, 'АКСО_СВАРКА_ВЫНОСКИ', 1);
    _writeLayerEntry(b, 'АКСО_СВАРКА_ТЕКСТ', 7);
    _writeLayerEntry(b, 'АКСО_АРМАТУРА', 3); // Green
    _writeLayerEntry(b, 'АКСО_ДИАМЕТРЫ', 4); // Cyan
    _writeLayerEntry(b, 'АКСО_УКЛОНЫ', 30); // Orange
    _writeLayerEntry(b, 'АКСО_ПЕРЕХОДЫ', 5); // Blue
    _writeLayerEntry(b, 'АКСО_ПЕРЕХОДЫ_ТЕКСТ', 7);
    _writeLayerEntry(b, 'АКСО_ФЛАНЦЫ', 6); // Magenta
    _writeLayerEntry(b, 'АКСО_ФЛАНЦЫ_ТЕКСТ', 7);
    _writeLayerEntry(b, 'АКСО_ВРЕЗКИ', 1); // Red
    _writeLayerEntry(b, 'АКСО_ОСИ', 8, 'DASHDOT'); // Gray Dash-dot
    _writeLayerEntry(b, 'АКСО_ОСИ_ТЕКСТ', 7);

    // Слои для систем
    for (final sys in net.systems.values) {
      _writeLayerEntry(b, 'АКСО_${sys.code}', sys.dxfAciColor);
    }

    b.writeln('  0\nENDTAB\n  0\nENDSEC');
  }

  static void _writeLayerEntry(StringBuffer b, String name, int aciColor, [String linetype = 'CONTINUOUS']) {
    b.writeln('  0\nLAYER\n  2\n$name\n 70\n0\n 62\n$aciColor\n  6\n$linetype');
  }

  static void _writeBlocks(StringBuffer b) {
    b.writeln('  0\nSECTION\n  2\nBLOCKS\n  0\nENDSEC');
  }

  static void _write3dLine(
    StringBuffer b, {
    required String layer,
    required double x1,
    required double y1,
    required double z1,
    required double x2,
    required double y2,
    required double z2,
  }) {
    b.writeln(
      '  0\nLINE\n  8\n$layer\n 10\n$x1\n 20\n$y1\n 30\n$z1\n 11\n$x2\n 21\n$y2\n 31\n$z2',
    );
  }

  static void _write2dLine(
    StringBuffer b, {
    required String layer,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    b.writeln(
      '  0\nLINE\n  8\n$layer\n 10\n$x1\n 20\n$y1\n 30\n0.0\n 11\n$x2\n 21\n$y2\n 31\n0.0',
    );
  }

  static void _writeCircle(
    StringBuffer b, {
    required String layer,
    required double cx,
    required double cy,
    required double radius,
  }) {
    b.writeln('  0\nCIRCLE\n  8\n$layer\n 10\n$cx\n 20\n$cy\n 30\n0.0\n 40\n$radius');
  }

  static void _writePoint(
    StringBuffer b, {
    required String layer,
    required double x,
    required double y,
    required double z,
  }) {
    b.writeln('  0\nPOINT\n  8\n$layer\n 10\n$x\n 20\n$y\n 30\n$z');
  }

  static void _writeText(
    StringBuffer b, {
    required String layer,
    required String text,
    required double x,
    required double y,
    required double z,
    required double height,
  }) {
    b.writeln(
      '  0\nTEXT\n  8\n$layer\n 10\n$x\n 20\n$y\n 30\n$z\n 40\n$height\n  1\n$text\n 50\n0.0',
    );
  }

  static void _writeGostValve2d(
    StringBuffer b, {
    required Offset center,
    required double angle,
    required ValveType type,
  }) {
    const size = 60.0;
    final halfL = size * 0.9;
    final halfH = size * 0.45;

    // Преобразование локальных точек в глобальные с поворотом
    Offset transform(double lx, double ly) {
      final rx = lx * math.cos(angle) - ly * math.sin(angle);
      final ry = lx * math.sin(angle) + ly * math.cos(angle);
      return Offset(center.dx + rx, center.dy + ry);
    }

    final t1 = transform(-halfL, -halfH);
    final t2 = transform(0, 0);
    final t3 = transform(-halfL, halfH);
    final t4 = transform(halfL, -halfH);
    final t5 = transform(halfL, halfH);

    // Два треугольника
    _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: t1.dx, y1: t1.dy, x2: t2.dx, y2: t2.dy);
    _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: t2.dx, y1: t2.dy, x2: t3.dx, y2: t3.dy);
    _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: t3.dx, y1: t3.dy, x2: t1.dx, y2: t1.dy);

    _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: t2.dx, y1: t2.dy, x2: t4.dx, y2: t4.dy);
    _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: t4.dx, y1: t4.dy, x2: t5.dx, y2: t5.dy);
    _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: t5.dx, y1: t5.dy, x2: t2.dx, y2: t2.dy);

    if (type == ValveType.gateValve) {
      // Шток и маховик
      final stemTop = transform(0, -halfH * 1.6);
      _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: t2.dx, y1: t2.dy, x2: stemTop.dx, y2: stemTop.dy);
      _writeCircle(b, layer: 'АКСО_АРМАТУРА', cx: stemTop.dx, cy: stemTop.dy, radius: halfH * 0.7);
    } else if (type == ValveType.butterflyValve) {
      // Диск поперек
      final d1 = transform(0, -halfH * 1.2);
      final d2 = transform(0, halfH * 1.2);
      _write2dLine(b, layer: 'АКСО_АРМАТУРА', x1: d1.dx, y1: d1.dy, x2: d2.dx, y2: d2.dy);
    }
  }

  static void _writeGostReducer2d(
    StringBuffer b, {
    required Offset center,
    required double angle,
    required int dn1,
    required int dn2,
    required bool isEccentric,
  }) {
    const halfL = 30.0;
    final w1 = math.max(15.0, dn1 * 0.35);
    final w2 = math.max(15.0, dn2 * 0.35);

    Offset transform(double lx, double ly) {
      final rx = lx * math.cos(angle) - ly * math.sin(angle);
      final ry = lx * math.sin(angle) + ly * math.cos(angle);
      return Offset(center.dx + rx, center.dy + ry);
    }

    final Offset pA, pB, pC, pD;
    if (!isEccentric) {
      // Концентрический переход: симметричная трапеция
      pA = transform(-halfL, -w1);
      pB = transform(halfL, -w2);
      pC = transform(halfL, w2);
      pD = transform(-halfL, w1);
    } else {
      // Эксцентрический переход: одна сторона прямая
      pA = transform(-halfL, w1);
      pB = transform(halfL, w1);
      pC = transform(halfL, w1 - w2 * 2);
      pD = transform(-halfL, -w1);
    }

    _write2dLine(b, layer: 'АКСО_ПЕРЕХОДЫ', x1: pA.dx, y1: pA.dy, x2: pB.dx, y2: pB.dy);
    _write2dLine(b, layer: 'АКСО_ПЕРЕХОДЫ', x1: pB.dx, y1: pB.dy, x2: pC.dx, y2: pC.dy);
    _write2dLine(b, layer: 'АКСО_ПЕРЕХОДЫ', x1: pC.dx, y1: pC.dy, x2: pD.dx, y2: pD.dy);
    _write2dLine(b, layer: 'АКСО_ПЕРЕХОДЫ', x1: pD.dx, y1: pD.dy, x2: pA.dx, y2: pA.dy);

    // Подпись размера перехода по ГОСТ
    _writeText(
      b,
      layer: 'АКСО_ПЕРЕХОДЫ_ТЕКСТ',
      text: '$dn1×$dn2',
      x: center.dx - 25.0,
      y: center.dy + math.max(w1, w2) + 20.0,
      z: 0.0,
      height: 40.0,
    );
  }

  static void _writeGostFlange2d(
    StringBuffer b, {
    required Offset center,
    required double angle,
    required int dn,
    required bool isPair,
  }) {
    final h = math.max(18.0, dn * 0.35);

    Offset transform(double lx, double ly) {
      final rx = lx * math.cos(angle) - ly * math.sin(angle);
      final ry = lx * math.sin(angle) + ly * math.cos(angle);
      return Offset(center.dx + rx, center.dy + ry);
    }

    if (isPair) {
      final f1Top = transform(-6.0, -h);
      final f1Bottom = transform(-6.0, h);
      final f2Top = transform(6.0, -h);
      final f2Bottom = transform(6.0, h);

      _write2dLine(b, layer: 'АКСО_ФЛАНЦЫ', x1: f1Top.dx, y1: f1Top.dy, x2: f1Bottom.dx, y2: f1Bottom.dy);
      _write2dLine(b, layer: 'АКСО_ФЛАНЦЫ', x1: f2Top.dx, y1: f2Top.dy, x2: f2Bottom.dx, y2: f2Bottom.dy);
    } else {
      final fTop = transform(0.0, -h);
      final fBottom = transform(0.0, h);
      _write2dLine(b, layer: 'АКСО_ФЛАНЦЫ', x1: fTop.dx, y1: fTop.dy, x2: fBottom.dx, y2: fBottom.dy);
    }

    _writeText(
      b,
      layer: 'АКСО_ФЛАНЦЫ_ТЕКСТ',
      text: isPair ? 'Фл. пара Ду$dn' : 'Фланец Ду$dn',
      x: center.dx - 20.0,
      y: center.dy + h + 15.0,
      z: 0.0,
      height: 35.0,
    );
  }
}
