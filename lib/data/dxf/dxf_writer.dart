import 'dart:math' as math;
import 'dart:ui';
import '../../core/math/axonometry_projector.dart';
import '../../domain/enums/dxf_callout_options.dart';
import '../../domain/enums/fitting_type.dart';
import '../../domain/enums/inspection_method.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/enums/valve_type.dart';
import '../../domain/enums/weld_type.dart';
import '../../domain/models/callout.dart';
import '../../domain/models/equipment.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/pipe_support.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/drawing_sheet.dart';
import '../../domain/models/title_block_data.dart';
import '../../domain/services/element_3d_geometry.dart';
import '../../ui/canvas/painters/callout_painter.dart';

/// Генератор файлов AutoCAD DXF (ASCII R2000 / AC1015)
class DxfWriter {
  static String toAutoCadString(String input) {
    final clean = input.replaceAll('\r\n', ' ').replaceAll('\n', ' ').replaceAll('\r', ' ');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      final code = clean.codeUnitAt(i);
      if (code > 127) {
        buffer.write('\\U+${code.toRadixString(16).padLeft(4, '0').toUpperCase()}');
      } else {
        buffer.write(clean[i]);
      }
    }
    return buffer.toString();
  }
  /// Генерация 3D DXF файла (пространственные трубы, слои по системам, 3D-отметки)
  static String generate3dDxf(
    PipingNetwork network, {
    Map<String, String>? calloutTemplates,
    DxfCalloutType calloutType = DxfCalloutType.monolithicBlock,
    DxfCalloutOrientation calloutOrientation = DxfCalloutOrientation.cameraFacing,
    AxonometryProjector? activeProjector,
    bool exportInlineDiameters = false,
  }) {
    final buffer = StringBuffer();
    final extVec = calloutOrientation.getExtrusionVector(activeProjector);
    final calloutBlocks = _prepareCallouts3d(
      network,
      calloutTemplates ?? defaultCalloutTemplates,
      calloutType: calloutType,
      calloutOrientation: calloutOrientation,
      extrusionVector: extVec,
    );

    _writeHeader(buffer);
    _writeLayers(buffer, network);
    if (calloutType == DxfCalloutType.monolithicBlock) {
      _writeBlocks(buffer, calloutBlocks);
    } else {
      _writeBlocks(buffer, const []);
    }

    buffer.writeln('  0\nSECTION\n  2\nENTITIES');

    // 0. Осевая трасса в 3D (Centerline skeleton)
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;
      _write3dLine(
        buffer,
        layer: 'АКСО_ОСИ_ТРАССЫ',
        x1: start.x,
        y1: start.y,
        z1: start.z,
        x2: end.x,
        y2: end.y,
        z2: end.z,
      );
    }

    // 1. Физические катушки или отрезки труб в 3D
    if (network.spools.isNotEmpty) {
      for (final spool in network.spools.values) {
        if (spool.startPoint == null || spool.endPoint == null) continue;
        final seg = network.segments[spool.segmentId];
        final sys = seg != null ? network.systems[seg.systemId] : null;
        final layerName = sys != null ? 'АКСО_${sys.code}' : 'АКСО_ТРУБЫ';
        _write3dLine(
          buffer,
          layer: layerName,
          x1: spool.startPoint!.x,
          y1: spool.startPoint!.y,
          z1: spool.startPoint!.z,
          x2: spool.endPoint!.x,
          y2: spool.endPoint!.y,
          z2: spool.endPoint!.z,
        );
      }
    } else {
      for (final seg in network.segments.values) {
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final sys = network.systems[seg.systemId];
        final layerName = sys != null ? 'АКСО_${sys.code}' : 'АКСО_ТРУБЫ';

        final segValves = network.valves.values.where((v) => v.segmentId == seg.id).toList();
        final subIntervals = Element3dGeometry.calcPipeDrawableIntervals3d(start, end, segValves);
        for (final (pA, pB) in subIntervals) {
          _write3dLine(
            buffer,
            layer: layerName,
            x1: pA.x,
            y1: pA.y,
            z1: pA.z,
            x2: pB.x,
            y2: pB.y,
            z2: pB.z,
          );
        }
      }
    }

    if (exportInlineDiameters) {
      for (final seg in network.segments.values) {
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

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
    }

    // 2. Сварные стыки в 3D (пространственные кольца усиления шва и засечки)
    for (final weld in network.weldJoints.values) {
      final seg = network.segments[weld.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final weldLines = Element3dGeometry.generateWeld3d(
        weld,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
        style: weld.getEffectiveStyle(network.defaultWeldStyle),
        tickSizeMm: weld.getEffectiveTickSize(network.defaultWeldTickSizeMm, seg.outerDiameterMm),
      );
      for (final l in weldLines) {
        _write3dLine(buffer, layer: l.layer, x1: l.x1, y1: l.y1, z1: l.z1, x2: l.x2, y2: l.y2, z2: l.z2);
      }

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

    // 3. Арматура в 3D (пространственный корпус, шпиндель, штурвал со спицами, фланцы)
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final valveLines = Element3dGeometry.generateValve3d(
        valve,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
      );
      for (final l in valveLines) {
        _write3dLine(buffer, layer: l.layer, x1: l.x1, y1: l.y1, z1: l.z1, x2: l.x2, y2: l.y2, z2: l.z2);
      }

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

    // 3.1. Опоры и подвески в 3D (хомуты, стойки, башмаки)
    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final supportLines = Element3dGeometry.generateSupport3d(
        support,
        start,
        end,
        pipeOuterDiameter: seg.outerDiameterMm,
      );
      for (final l in supportLines) {
        _write3dLine(buffer, layer: l.layer, x1: l.x1, y1: l.y1, z1: l.z1, x2: l.x2, y2: l.y2, z2: l.z2);
      }

      final pos = support.calculatePosition(start, end);
      final label = support.name.isNotEmpty ? support.name : support.type.shortCode;
      _writeText(
        buffer,
        layer: 'АКСО_ОПОРЫ_ТЕКСТ',
        text: label,
        x: pos.x,
        y: pos.y,
        z: pos.z - 60.0,
        height: 50.0,
      );
    }

    // 4. Высотные отметки
    final nodeIdsWithCallouts = network.callouts.values
        .where((c) => c.targetType == CalloutTargetType.node)
        .map((c) => c.targetId)
        .toSet();

    for (final node in network.nodes.values) {
      if (nodeIdsWithCallouts.contains(node.id)) continue;
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

    // 5. Переходы в 3D (3D каркас конуса с образующими)
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) {
        final node = network.nodes[fit.nodeId];
        if (node == null) continue;
        final connectedSegs = network.getConnectedSegments(fit.nodeId);
        if (connectedSegs.length >= 2) {
          final seg1 = connectedSegs[0];
          final seg2 = connectedSegs[1];
          final other1 = network.nodes[seg1.startNodeId == fit.nodeId ? seg1.endNodeId : seg1.startNodeId];
          final other2 = network.nodes[seg2.startNodeId == fit.nodeId ? seg2.endNodeId : seg2.startNodeId];
          if (other1 != null && other2 != null) {
            final lines = Element3dGeometry.generateReducer3d(
              fit,
              node,
              other1,
              other2,
              d1: seg1.outerDiameterMm,
              d2: seg2.outerDiameterMm,
            );
            for (final l in lines) {
              _write3dLine(buffer, layer: l.layer, x1: l.x1, y1: l.y1, z1: l.z1, x2: l.x2, y2: l.y2, z2: l.z2);
            }
          }
        }
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

    // 6. Фланцы, заглушки и врезки в 3D
    for (final fit in network.fittings.values) {
      final node = network.nodes[fit.nodeId];
      if (node == null) continue;
      final connectedSegs = network.getConnectedSegments(fit.nodeId);

      if (fit.fittingType == FittingType.flange) {
        if (connectedSegs.isNotEmpty) {
          final seg = connectedSegs.first;
          final otherNodeId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
          final otherNode = network.nodes[otherNodeId];
          if (otherNode != null) {
            final lines = Element3dGeometry.generateFlange3d(
              fit,
              node,
              otherNode,
              pipeOuterDiameter: seg.outerDiameterMm,
            );
            for (final l in lines) {
              _write3dLine(buffer, layer: l.layer, x1: l.x1, y1: l.y1, z1: l.z1, x2: l.x2, y2: l.y2, z2: l.z2);
            }
          }
        }
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
      } else if (fit.fittingType == FittingType.cap) {
        if (connectedSegs.isNotEmpty) {
          final seg = connectedSegs.first;
          final otherNodeId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
          final otherNode = network.nodes[otherNodeId];
          if (otherNode != null) {
            final lines = Element3dGeometry.generateCap3d(
              fit,
              node,
              otherNode,
              pipeOuterDiameter: seg.outerDiameterMm,
            );
            for (final l in lines) {
              _write3dLine(buffer, layer: l.layer, x1: l.x1, y1: l.y1, z1: l.z1, x2: l.x2, y2: l.y2, z2: l.z2);
            }
          }
        }
        _writePoint(buffer, layer: 'АКСО_ЗАГЛУШКИ', x: node.x, y: node.y, z: node.z);
        _writeText(
          buffer,
          layer: 'АКСО_ЗАГЛУШКИ_ТЕКСТ',
          text: 'Заглушка Ду${fit.dn}',
          x: node.x,
          y: node.y,
          z: node.z + 80.0,
          height: 45.0,
        );
      } else if (fit.fittingType == FittingType.directBranch) {
        if (connectedSegs.length == 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connectedSegs);
          final mainSegs = connectedSegs.where((s) => s.id != branchSeg?.id).toList();
          if (branchSeg != null && mainSegs.isNotEmpty) {
            final otherNodeId = branchSeg.startNodeId == fit.nodeId ? branchSeg.endNodeId : branchSeg.startNodeId;
            final otherNode = network.nodes[otherNodeId];
            if (otherNode != null) {
              final lines = Element3dGeometry.generateDirectBranch3d(
                fit,
                node,
                otherNode,
                mainOuterDiameter: mainSegs[0].outerDiameterMm,
                branchOuterDiameter: branchSeg.outerDiameterMm,
              );
              for (final l in lines) {
                _write3dLine(buffer, layer: l.layer, x1: l.x1, y1: l.y1, z1: l.z1, x2: l.x2, y2: l.y2, z2: l.z2);
              }
            }
          }
        }
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
      } else if (fit.fittingType == FittingType.tee) {
        if (connectedSegs.length >= 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connectedSegs);
          for (int i = 0; i < 3; i++) {
            final seg = connectedSegs[i];
            final otherId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
            final otherNode = network.nodes[otherId];
            if (otherNode == null) continue;

            final isBranch = seg.id == branchSeg?.id;
            final armLenMm = isBranch
                ? fit.effectiveBranchLengthMm
                : (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0
                    ? fit.buildingLengthMm! / 2.0
                    : fit.dn * 1.0);

            final vx = otherNode.x - node.x;
            final vy = otherNode.y - node.y;
            final vz = otherNode.z - node.z;
            final dist3d = math.sqrt(vx * vx + vy * vy + vz * vz);
            final uX = dist3d > 0 ? vx / dist3d : 0.0;
            final uY = dist3d > 0 ? vy / dist3d : 0.0;
            final uZ = dist3d > 0 ? vz / dist3d : 0.0;

            final effectiveArm = math.min(armLenMm, dist3d * 0.45);
            _write3dLine(
              buffer,
              layer: 'АКСО_ТРОЙНИКИ',
              x1: node.x,
              y1: node.y,
              z1: node.z,
              x2: node.x + uX * effectiveArm,
              y2: node.y + uY * effectiveArm,
              z2: node.z + uZ * effectiveArm,
            );
          }
        }
        _writePoint(buffer, layer: 'АКСО_ТРОЙНИКИ', x: node.x, y: node.y, z: node.z);
        final label = fit.name ??
            (fit.dnSecondary != null && fit.dnSecondary != fit.dn
                ? 'Тройник Ду${fit.dn}х${fit.dnSecondary}'
                : 'Тройник Ду${fit.dn}');
        _writeText(
          buffer,
          layer: 'АКСО_ТРОЙНИКИ_ТЕКСТ',
          text: label,
          x: node.x,
          y: node.y,
          z: node.z + 80.0,
          height: 45.0,
        );
      }
    }

    // 7. Строительные и вспомогательные оси в 3D
    for (final axis in network.axes.values) {
      final layer = axis.isBuildingGrid ? 'АКСО_ОСИ' : 'АКСО_ВСПОМОГАТЕЛЬНЫЕ';
      _write3dLine(
        buffer,
        layer: layer,
        x1: axis.startPoint.x,
        y1: axis.startPoint.y,
        z1: axis.startPoint.z,
        x2: axis.endPoint.x,
        y2: axis.endPoint.y,
        z2: axis.endPoint.z,
      );
      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        _writePoint(buffer, layer: layer, x: axis.startPoint.x, y: axis.startPoint.y, z: axis.startPoint.z);
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

    // 8. Линейные размеры в 3D
    for (final dim in network.dimensions.values) {
      _write3dLine(
        buffer,
        layer: 'АКСО_РАЗМЕРЫ',
        x1: dim.startPoint.x,
        y1: dim.startPoint.y,
        z1: dim.startPoint.z,
        x2: dim.endPoint.x,
        y2: dim.endPoint.y,
        z2: dim.endPoint.z,
      );
      final midX = (dim.startPoint.x + dim.endPoint.x) / 2;
      final midY = (dim.startPoint.y + dim.endPoint.y) / 2;
      final midZ = (dim.startPoint.z + dim.endPoint.z) / 2 + 50.0;
      _writeText(
        buffer,
        layer: 'АКСО_РАЗМЕРЫ_ТЕКСТ',
        text: dim.displayText,
        x: midX,
        y: midY,
        z: midZ,
        height: 60.0,
        align: 1,
      );
    }

    // 8b. Технологическое оборудование и штуцеры в 3D
    _writeEquipment3d(buffer, network);

    // 9. Умные выноски (Callouts) в 3D
    _writeCalloutEntities3d(buffer, calloutBlocks, calloutType, extVec);

    buffer.writeln('  0\nENDSEC\n  0\nEOF');
    return buffer.toString();
  }

  /// Генерация плоского 2D DXF чертежа в аксонометрии по ГОСТ 21.602 / СПДС
  /// Готовый к печати плоский чертеж с выносками, полочками, клеймами сварки
  static String generate2dGostAxonometryDxf(
    PipingNetwork network, {
    ProjectionType projection = ProjectionType.gostFrontal45,
    AxonometryProjector? activeProjector,
    Map<String, String>? calloutTemplates,
    bool exportInlineDiameters = false,
  }) {
    final buffer = StringBuffer();
    final projector = activeProjector ?? AxonometryProjector(projectionType: projection, scale: 1.0);
    final calloutBlocks = _prepareCallouts2d(network, projector, calloutTemplates ?? defaultCalloutTemplates);

    _writeHeader(buffer);
    _writeLayers(buffer, network);
    _writeBlocks(buffer, calloutBlocks);

    buffer.writeln('  0\nSECTION\n  2\nENTITIES');

    _write2dModelEntities(
      buffer: buffer,
      network: network,
      projector: projector,
      calloutBlocks: calloutBlocks,
      exportInlineDiameters: exportInlineDiameters,
    );

    buffer.writeln('  0\nENDSEC\n  0\nEOF');
    return buffer.toString();
  }

  /// Генерация 2D DXF с листами (Layouts / Paper Space) по ГОСТ 21.101-2020
  static String generate2dGostAxonometryWithLayoutsDxf({
    required PipingNetwork network,
    required List<DrawingSheet> sheets,
    ProjectionType projection = ProjectionType.gostFrontal45,
    AxonometryProjector? activeProjector,
    Map<String, String>? calloutTemplates,
    bool exportInlineDiameters = false,
  }) {
    final buffer = StringBuffer();
    final projector = activeProjector ?? AxonometryProjector(projectionType: projection, scale: 1.0);
    final calloutBlocks = _prepareCallouts2d(network, projector, calloutTemplates ?? defaultCalloutTemplates);

    // 1. HEADER (AC1015 / AutoCAD R2000 для поддержки вкладок листов Layouts)
    buffer.writeln('  0\nSECTION\n  2\nHEADER\n  9\n\$ACADVER\n  1\nAC1015\n  9\n\$DWGCODEPAGE\n  3\nUTF-8\n  9\n\$HANDSEED\n  5\nFFFF\n  0\nENDSEC');

    // 2. TABLES (слои, стили, типы линий)
    _writeLayers(buffer, network, isLayouts: true);

    // 3. BLOCKS
    _writeBlocks(buffer, calloutBlocks);

    // 4. OBJECTS (Регистрация вкладок листов LAYOUT в словаре ACAD_LAYOUT)
    buffer.writeln('  0\nSECTION\n  2\nOBJECTS');
    buffer.writeln('  0\nDICTIONARY\n  5\nC\n100\nAcDbDictionary\n281\n1\n  3\nACAD_LAYOUT\n350\nD');
    buffer.writeln('  0\nDICTIONARY\n  5\nD\n100\nAcDbDictionary\n281\n1');
    buffer.writeln('  3\nModel\n350\nE');

    for (int i = 0; i < sheets.length; i++) {
      final handle = (0x100 + i).toRadixString(16).toUpperCase();
      buffer.writeln('  3\n${sheets[i].name}\n350\n$handle');
    }

    // Объект LAYOUT для Model space
    buffer.writeln('  0\nLAYOUT\n  5\nE\n100\nAcDbPlotSettings\n100\nAcDbLayout\n  1\nModel\n 70\n1\n 71\n0');

    // Объекты LAYOUT для листов
    for (int i = 0; i < sheets.length; i++) {
      final sh = sheets[i];
      final handle = (0x100 + i).toRadixString(16).toUpperCase();
      buffer.writeln('  0\nLAYOUT\n  5\n$handle\n100\nAcDbPlotSettings\n100\nAcDbLayout\n  1\n${sh.name}\n 70\n1\n 71\n${i + 1}\n 10\n0.0\n 20\n0.0\n 11\n${sh.format.widthMm}\n 21\n${sh.format.heightMm}\n 12\n0.0\n 22\n0.0\n 14\n0.0\n 24\n0.0\n 15\n${sh.format.widthMm}\n 25\n${sh.format.heightMm}');
    }
    buffer.writeln('  0\nENDSEC');

    // 5. ENTITIES
    buffer.writeln('  0\nSECTION\n  2\nENTITIES');

    // 5.1. Все объекты модели (Model Space)
    _write2dModelEntities(
      buffer: buffer,
      network: network,
      projector: projector,
      calloutBlocks: calloutBlocks,
      exportInlineDiameters: exportInlineDiameters,
    );

    // 5.2. Объекты листов (Paper Space): ВЭ, Рамка, Штамп, ТТ, Приложение к акту
    int handleCounter = 0x1000;
    String nextHandle() => (handleCounter++).toRadixString(16).toUpperCase();

    for (int i = 0; i < sheets.length; i++) {
      final sh = sheets[i];
      final layoutName = sh.name;
      final w = sh.format.widthMm;
      final h = sh.format.heightMm;

      // 5.2.1. Объект VIEWPORT
      final vp = sh.viewport;
      final cx = vp.xMm + (vp.widthMm / 2.0);
      final cy = h - (vp.yMm + (vp.heightMm / 2.0));
      final viewHeightModel = vp.viewScale > 0.0001 ? vp.heightMm / vp.viewScale : 1000.0;

      buffer.writeln('  0\nVIEWPORT\n  5\n${nextHandle()}\n100\nAcDbEntity\n 67\n1\n410\n$layoutName\n  8\nАКСО_ЛИСТ_ВЭ\n100\nAcDbViewport\n 10\n${cx.toStringAsFixed(3)}\n 20\n${cy.toStringAsFixed(3)}\n 30\n0.0\n 40\n${vp.widthMm.toStringAsFixed(3)}\n 41\n${vp.heightMm.toStringAsFixed(3)}\n 68\n1\n 69\n${i + 2}\n 12\n${vp.modelCenterX.toStringAsFixed(3)}\n 22\n${vp.modelCenterY.toStringAsFixed(3)}\n 45\n${viewHeightModel.toStringAsFixed(3)}');

      // 5.2.2. Рамка листа (20-5-5-5 мм) на слое АКСО_ЛИСТ_РАМКА
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_РАМКА', 20.0, 5.0, w - 5.0, 5.0);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_РАМКА', w - 5.0, 5.0, w - 5.0, h - 5.0);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_РАМКА', w - 5.0, h - 5.0, 20.0, h - 5.0);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_РАМКА', 20.0, h - 5.0, 20.0, 5.0);

      // 5.2.3. Штамп Форма 3 (185х55 мм) на слое АКСО_ЛИСТ_ШТАМП
      final stampX0 = w - 5.0 - 185.0;
      final stampY0 = 5.0;
      final stampX1 = w - 5.0;
      final stampY1 = 60.0;

      // Внешний контур штампа
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', stampX0, stampY0, stampX1, stampY0);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', stampX1, stampY0, stampX1, stampY1);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', stampX1, stampY1, stampX0, stampY1);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', stampX0, stampY1, stampX0, stampY0);

      // Вертикальные разделители
      final xRole = stampX0 + 17.0;
      final xName = stampX0 + 40.0;
      final xSign = stampX0 + 55.0;
      final xApprovalsEnd = stampX0 + 65.0;
      final xCenterEnd = stampX0 + 135.0;

      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xRole, stampY0, xRole, stampY1);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xName, stampY0, xName, stampY1);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xSign, stampY0, xSign, stampY1);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xApprovalsEnd, stampY0, xApprovalsEnd, stampY1);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xCenterEnd, stampY0, xCenterEnd, stampY1);

      // 8 строк согласований по 5 мм снизу
      for (int r = 1; r <= 8; r++) {
        final yr = stampY0 + (r * 5.0);
        _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', stampX0, yr, xApprovalsEnd, yr);
      }

      // Разделители правого блока
      final yStageValues = stampY0 + 35.0;
      final yStageHeader = stampY0 + 50.0;
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xCenterEnd, yStageHeader, stampX1, yStageHeader);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xCenterEnd, yStageValues, stampX1, yStageValues);

      final xStage = xCenterEnd + 15.0;
      final xSheet = xCenterEnd + 30.0;
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xStage, yStageValues, xStage, stampY1);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xSheet, yStageValues, xSheet, stampY1);

      // Разделители центрального блока
      final yCode = stampY0 + 40.0;
      final yObj = stampY0 + 25.0;
      final yBldg = stampY0 + 15.0;
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xApprovalsEnd, yCode, xCenterEnd, yCode);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xApprovalsEnd, yObj, xCenterEnd, yObj);
      _writeDxfPaperLine(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', xApprovalsEnd, yBldg, xCenterEnd, yBldg);

      // Тексты штампа
      final tb = sh.titleBlockData;
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.documentCode, xApprovalsEnd + 4.0, stampY0 + 44.0, 4.5);
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.projectName, xApprovalsEnd + 2.5, stampY0 + 28.0, 3.0);
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.buildingName, xApprovalsEnd + 2.5, stampY0 + 18.0, 3.0);
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.drawingTitle, xApprovalsEnd + 2.5, stampY0 + 6.0, 3.5);

      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', 'Стадия', xCenterEnd + 2.0, stampY0 + 51.5, 2.0);
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', 'Лист', xStage + 3.0, stampY0 + 51.5, 2.0);
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', 'Листов', xSheet + 4.0, stampY0 + 51.5, 2.0);

      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.stage, xCenterEnd + 4.0, stampY0 + 42.0, 3.5);
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.sheetNumber.toString(), xStage + 5.0, stampY0 + 42.0, 3.5);
      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.totalSheets.toString(), xSheet + 7.0, stampY0 + 42.0, 3.5);

      _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', tb.organization, xCenterEnd + 5.0, stampY0 + 18.0, 3.2);

      // Согласования
      final roles = ['Разраб.', 'Пров.', 'Т.контр.', '', 'ГИП', 'Н.контр.', 'Утв.'];
      for (int r = 0; r < roles.length; r++) {
        final role = roles[r];
        if (role.isEmpty) continue;
        final yRow = stampY1 - ((roles.length - r) * 5.0) + 1.2;
        _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', role, stampX0 + 1.5, yRow, 2.2);

        final app = tb.approvals.firstWhere((a) => a.role == role, orElse: () => const TitleBlockApproval(role: '', name: ''));
        if (app.name.isNotEmpty) {
          _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', app.name, xRole + 1.5, yRow, 2.2);
        }
        if (app.date.isNotEmpty) {
          _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', app.date, xSign + 1.0, yRow, 2.0);
        }
      }

      // 5.2.4. Технические требования (ТТ) на слое АКСО_ЛИСТ_ТТ
      if (sh.technicalRequirements != null && sh.technicalRequirements!.text.isNotEmpty) {
        final lines = sh.technicalRequirements!.text.split('\n');
        double ttY = stampY1 + 5.0;
        for (int l = lines.length - 1; l >= 0; l--) {
          _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ТТ', lines[l], stampX0, ttY, 2.5);
          ttY += 4.0;
        }
        _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ТТ', 'Технические требования:', stampX0, ttY, 2.8);
      }

      // 5.2.5. Приложение к акту (правый верхний угол)
      if (tb.topRightCorner.mode == TopRightCornerMode.actAttachment && tb.topRightCorner.text.isNotEmpty) {
        final lines = tb.topRightCorner.text.split('\n');
        double actY = h - 10.0;
        for (final l in lines) {
          _writeDxfPaperText(buffer, nextHandle(), layoutName, 'АКСО_ЛИСТ_ШТАМП', l, w - 90.0, actY, 2.5);
          actY -= 4.0;
        }
      }
    }

    buffer.writeln('  0\nENDSEC\n  0\nEOF');
    return buffer.toString();
  }

  static void _write2dModelEntities({
    required StringBuffer buffer,
    required PipingNetwork network,
    required AxonometryProjector projector,
    required List<_DxfCalloutBlockDef> calloutBlocks,
    bool exportInlineDiameters = false,
  }) {
    // 0. Осевая трасса в 2D проекции ГОСТ (Centerline skeleton)
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;
      final p1 = _projectTo2d(projector, start);
      final p2 = _projectTo2d(projector, end);
      _write2dLine(buffer, layer: 'АКСО_ОСИ_ТРАССЫ', x1: p1.dx, y1: p1.dy, x2: p2.dx, y2: p2.dy);
    }

    // 1. Физические катушки или отрезки труб в проекции ГОСТ
    if (network.spools.isNotEmpty) {
      for (final spool in network.spools.values) {
        if (spool.startPoint == null || spool.endPoint == null) continue;
        final seg = network.segments[spool.segmentId];
        final sys = seg != null ? network.systems[seg.systemId] : null;
        final layerName = sys != null ? 'АКСО_${sys.code}' : 'АКСО_ТРУБЫ';
        final p1 = _projectTo2d(projector, spool.startPoint!);
        final p2 = _projectTo2d(projector, spool.endPoint!);
        _write2dLine(buffer, layer: layerName, x1: p1.dx, y1: p1.dy, x2: p2.dx, y2: p2.dy);
      }
    } else {
      for (final seg in network.segments.values) {
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start == null || end == null) continue;

        final sys = network.systems[seg.systemId];
        final layerName = sys != null ? 'АКСО_${sys.code}' : 'АКСО_ТРУБЫ';

        final segValves = network.valves.values.where((v) => v.segmentId == seg.id).toList();
        final subIntervals = Element3dGeometry.calcPipeDrawableIntervals3d(start, end, segValves);
        for (final (pA, pB) in subIntervals) {
          final nodeA = Node3D(id: '', x: pA.x, y: pA.y, z: pA.z);
          final nodeB = Node3D(id: '', x: pB.x, y: pB.y, z: pB.z);
          final p1Sub = _projectTo2d(projector, nodeA);
          final p2Sub = _projectTo2d(projector, nodeB);
          _write2dLine(buffer, layer: layerName, x1: p1Sub.dx, y1: p1Sub.dy, x2: p2Sub.dx, y2: p2Sub.dy);
        }
      }
    }

    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;
      final p1 = _projectTo2d(projector, start);
      final p2 = _projectTo2d(projector, end);

      final midX = (p1.dx + p2.dx) / 2;
      final midY = (p1.dy + p2.dy) / 2 + 30.0;

      // Выноска диаметра (горизонтальный текст над трубой)
      if (exportInlineDiameters) {
        _writeText(
          buffer,
          layer: 'АКСО_ДИАМЕТРЫ',
          text: seg.shortCallout,
          x: midX - 30.0,
          y: midY,
          z: 0.0,
          height: 50.0,
        );
      }

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

    // 2b. Опоры и подвески в 2D по ГОСТ
    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = _projectTo2d(projector, start);
      final p2 = _projectTo2d(projector, end);

      final ratio = support.distanceRatio.clamp(0.0, 1.0);
      final center = Offset(
        p1.dx + (p2.dx - p1.dx) * ratio,
        p1.dy + (p2.dy - p1.dy) * ratio,
      );

      final dir = p2 - p1;
      final len = dir.distance;
      final u = len > 0.001 ? dir / len : const Offset(1, 0);

      var n = Offset(-u.dy, u.dx);
      if (n.dy < -0.01 || (n.dy.abs() <= 0.01 && n.dx < 0)) {
        n = -n;
      }

      _writeGostSupport2d(buffer, center: center, u: u, n: n, support: support);
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
    final nodeIdsWithCallouts = network.callouts.values
        .where((c) => c.targetType == CalloutTargetType.node)
        .map((c) => c.targetId)
        .toSet();

    for (final node in network.nodes.values) {
      if (nodeIdsWithCallouts.contains(node.id)) continue;
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

    // 6. Фланцы, заглушки и врезки в 2D (УГО по ГОСТ)
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
      } else if (fit.fittingType == FittingType.cap) {
        final connectedSegs = network.getConnectedSegments(fit.nodeId);
        if (connectedSegs.isNotEmpty) {
          final seg = connectedSegs.first;
          final otherId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
          final otherNode = network.nodes[otherId];
          if (otherNode != null) {
            final pOther = _projectTo2d(projector, otherNode);
            final angle = math.atan2(center.dy - pOther.dy, center.dx - pOther.dx);
            _writeGostCap2d(
              buffer,
              center: center,
              angle: angle,
              dn: fit.dn,
            );
          }
        }
      } else if (fit.fittingType == FittingType.directBranch) {
        final connectedSegs = network.getConnectedSegments(fit.nodeId);
        Offset pJoint = center;
        if (connectedSegs.length == 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connectedSegs);
          final mainSegs = connectedSegs.where((s) => s.id != branchSeg?.id).toList();
          if (branchSeg != null && mainSegs.length == 2) {
            final otherBranch = network.nodes[branchSeg.startNodeId == fit.nodeId ? branchSeg.endNodeId : branchSeg.startNodeId];
            if (otherBranch != null) {
              final pBranch = _projectTo2d(projector, otherBranch);
              var vBranch = pBranch - center;
              if (vBranch.distance > 0.001) vBranch = vBranch / vBranch.distance;

              final rMainMm = (network.pipeCatalog.getDimension(mainSegs[0].dn)?.outerDiameterMm ?? mainSegs[0].dn.toDouble()) / 2.0;
              pJoint = center + vBranch * (rMainMm * projector.scale);
            }
          }
        }

        _writeCircle(buffer, layer: 'АКСО_ВРЕЗКИ', cx: pJoint.dx, cy: pJoint.dy, radius: 14.0);

        final leaderEndX = pJoint.dx + 40.0;
        final leaderEndY = pJoint.dy + 40.0;
        final shelfEndX = leaderEndX + 80.0;

        _write2dLine(buffer, layer: 'АКСО_СВАРКА_ВЫНОСКИ', x1: pJoint.dx, y1: pJoint.dy, x2: leaderEndX, y2: leaderEndY);
        _write2dLine(buffer, layer: 'АКСО_СВАРКА_ВЫНОСКИ', x1: leaderEndX, y1: leaderEndY, x2: shelfEndX, y2: leaderEndY);

        _writeText(
          buffer,
          layer: 'АКСО_СВАРКА_ТЕКСТ',
          text: 'Врезка У18 (Ду${fit.dnSecondary ?? fit.dn})',
          x: leaderEndX + 5.0,
          y: leaderEndY + 8.0,
          z: 0.0,
          height: 30.0,
        );
      } else if (fit.fittingType == FittingType.tee) {
        final connectedSegs = network.getConnectedSegments(fit.nodeId);
        if (connectedSegs.length >= 3) {
          final branchSeg = network.identifyBranchSegment(fit.nodeId, connectedSegs);
          for (int i = 0; i < 3; i++) {
            final seg = connectedSegs[i];
            final otherId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
            final otherNode = network.nodes[otherId];
            if (otherNode == null) continue;

            final isBranch = seg.id == branchSeg?.id;
            final armLenMm = isBranch
                ? fit.effectiveBranchLengthMm
                : (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0
                    ? fit.buildingLengthMm! / 2.0
                    : fit.dn * 1.0);

            final vx = otherNode.x - node.x;
            final vy = otherNode.y - node.y;
            final vz = otherNode.z - node.z;
            final dist3d = math.sqrt(vx * vx + vy * vy + vz * vz);
            final uX = dist3d > 0 ? vx / dist3d : 0.0;
            final uY = dist3d > 0 ? vy / dist3d : 0.0;
            final uZ = dist3d > 0 ? vz / dist3d : 0.0;

            final effectiveArm = math.min(armLenMm, dist3d * 0.45);
            final ptArm3d = Node3D(
              id: '',
              x: node.x + uX * effectiveArm,
              y: node.y + uY * effectiveArm,
              z: node.z + uZ * effectiveArm,
            );
            final pArm2d = _projectTo2d(projector, ptArm3d);
            _write2dLine(
              buffer,
              layer: 'АКСО_ТРОЙНИКИ',
              x1: center.dx,
              y1: center.dy,
              x2: pArm2d.dx,
              y2: pArm2d.dy,
            );
          }
        }
        _writeCircle(buffer, layer: 'АКСО_ТРОЙНИКИ', cx: center.dx, cy: center.dy, radius: 10.0);
        final label = fit.name ??
            (fit.dnSecondary != null && fit.dnSecondary != fit.dn
                ? 'Тройник Ду${fit.dn}х${fit.dnSecondary}'
                : 'Тройник Ду${fit.dn}');
        _writeText(
          buffer,
          layer: 'АКСО_ТРОЙНИКИ_ТЕКСТ',
          text: label,
          x: center.dx + 15.0,
          y: center.dy + 15.0,
          z: 0.0,
          height: 35.0,
        );
      }
    }

    // 7. Строительные и вспомогательные оси в 2D
    for (final axis in network.axes.values) {
      final layer = axis.isBuildingGrid ? 'АКСО_ОСИ' : 'АКСО_ВСПОМОГАТЕЛЬНЫЕ';
      final p1 = _projectTo2d(projector, axis.startPoint);
      final p2 = _projectTo2d(projector, axis.endPoint);
      _write2dLine(buffer, layer: layer, x1: p1.dx, y1: p1.dy, x2: p2.dx, y2: p2.dy);
      if (axis.isBuildingGrid && axis.label.isNotEmpty) {
        const circleR = 40.0;
        _writeCircle(buffer, layer: layer, cx: p1.dx, cy: p1.dy, radius: circleR);
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

    // 8. Линейные размеры по ГОСТ 2.307 в 2D
    for (final dim in network.dimensions.values) {
      final p1 = _projectTo2d(projector, dim.startPoint);
      final p2 = _projectTo2d(projector, dim.endPoint);
      final delta = p2 - p1;
      final dist = delta.distance;
      if (dist < 1.0) continue;

      final u = delta / dist;
      final n = Offset(-u.dy, u.dx);
      final offsetDist = dim.offsetDistance == 0.0 ? 35.0 : dim.offsetDistance;
      final offsetVec = n * offsetDist;

      final d1 = p1 + offsetVec;
      final d2 = p2 + offsetVec;

      final overshoot = (offsetDist >= 0 ? 15.0 : -15.0);
      final ext1End = d1 + n * overshoot;
      final ext2End = d2 + n * overshoot;

      // Выносные линии
      _write2dLine(buffer, layer: 'АКСО_РАЗМЕРЫ', x1: p1.dx, y1: p1.dy, x2: ext1End.dx, y2: ext1End.dy);
      _write2dLine(buffer, layer: 'АКСО_РАЗМЕРЫ', x1: p2.dx, y1: p2.dy, x2: ext2End.dx, y2: ext2End.dy);

      // Размерная линия
      _write2dLine(buffer, layer: 'АКСО_РАЗМЕРЫ', x1: d1.dx, y1: d1.dy, x2: d2.dx, y2: d2.dy);

      // Строительные засечки ГОСТ под углом 45°
      const tickLen = 20.0;
      final tickDir = (u + n) / math.sqrt(2) * tickLen;
      _write2dLine(buffer, layer: 'АКСО_РАЗМЕРЫ', x1: d1.dx - tickDir.dx, y1: d1.dy - tickDir.dy, x2: d1.dx + tickDir.dx, y2: d1.dy + tickDir.dy);
      _write2dLine(buffer, layer: 'АКСО_РАЗМЕРЫ', x1: d2.dx - tickDir.dx, y1: d2.dy - tickDir.dy, x2: d2.dx + tickDir.dx, y2: d2.dy + tickDir.dy);

      // Текст размера
      final mid = (d1 + d2) / 2 + n * 12.0;
      var rotDeg = math.atan2(delta.dy, delta.dx) * 180.0 / math.pi;
      if (rotDeg > 90.0) {
        rotDeg -= 180.0;
      } else if (rotDeg < -90.0) {
        rotDeg += 180.0;
      }

      _writeText(
        buffer,
        layer: 'АКСО_РАЗМЕРЫ_ТЕКСТ',
        text: dim.displayText,
        x: mid.dx,
        y: mid.dy,
        z: 0.0,
        height: 35.0,
        align: 1,
        rotation: rotDeg,
      );
    }

    // 8b. Технологическое оборудование и штуцеры в 2D проекции ГОСТ
    _writeEquipment2d(buffer, network, projector);

    // 9. Умные выноски (Callouts) в 2D проекции (AutoCAD BLOCKS + INSERT + ATTRIB)
    _writeCalloutEntities(buffer, calloutBlocks);
  }

  static void _writeDxfPaperLine(
    StringBuffer b,
    String handle,
    String layoutName,
    String layer,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    b.writeln('  0\nLINE\n  5\n$handle\n100\nAcDbEntity\n 67\n1\n410\n$layoutName\n  8\n$layer\n100\nAcDbLine\n 10\n${x1.toStringAsFixed(3)}\n 20\n${y1.toStringAsFixed(3)}\n 30\n0.0\n 11\n${x2.toStringAsFixed(3)}\n 21\n${y2.toStringAsFixed(3)}\n 31\n0.0');
  }

  static void _writeDxfPaperText(
    StringBuffer b,
    String handle,
    String layoutName,
    String layer,
    String text,
    double x,
    double y,
    double height, {
    int align = 0,
    double rotation = 0.0,
  }) {
    if (text.isEmpty) return;
    b.writeln('  0\nTEXT\n  5\n$handle\n100\nAcDbEntity\n 67\n1\n410\n$layoutName\n  8\n$layer\n100\nAcDbText\n 10\n${x.toStringAsFixed(3)}\n 20\n${y.toStringAsFixed(3)}\n 30\n0.0\n 40\n${height.toStringAsFixed(2)}\n  1\n$text\n 72\n$align\n 11\n${x.toStringAsFixed(3)}\n 21\n${y.toStringAsFixed(3)}\n 31\n0.0${rotation != 0.0 ? '\n 50\n$rotation' : ''}');
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

    // 1. Технологическое оборудование (ГОСТ 21.110-2013 раздел "Оборудование")
    final eqMap = <String, int>{};
    for (final eq in network.equipments.values) {
      final dims = '${eq.length.toInt()}×${eq.width.toInt()}×${eq.height.toInt()} мм';
      final sn = eq.serialNumber != null && eq.serialNumber!.isNotEmpty
          ? ' (зав. № ${eq.serialNumber})'
          : '';
      final key = '${eq.name} ($dims)|${eq.type.displayName}|—|Сталь 09Г2С|Технологическое оборудование$sn';
      eqMap[key] = (eqMap[key] ?? 0) + 1;
    }
    for (final entry in eqMap.entries) {
      final parts = entry.key.split('|');
      final desc = parts[0];
      final type = parts[1];
      final std = parts[2];
      final mat = parts[3];
      final note = parts[4];
      buffer.writeln(
        '${itemNum++};$desc;$type;$std;$mat;${entry.value};шт.;$note',
      );
    }

    // 2. Трубы стальные (группировка по DN, толщине стенки и марке стали)
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

    // 3. Фасонные детали (отводы, тройники, переходы, фланцы)
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

    // 4. Трубопроводная арматура (задвижки, затворы, краны, фильтры, КИП)
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

    // 5. Опоры и подвески трубопроводов (ГОСТ 14911-82 / ОСТ 36-146-88 / ГОСТ 16127-78)
    final supportMap = <String, int>{};
    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      final dn = seg?.dn ?? 50;
      final sizeStr = seg != null ? seg.formattedSize : 'Ду$dn';

      String standard;
      switch (support.type) {
        case PipeSupportType.fixed:
        case PipeSupportType.sliding:
          standard = 'ГОСТ 14911-82';
          break;
        case PipeSupportType.spring:
          standard = 'ГОСТ 16127-78';
          break;
        case PipeSupportType.guide:
          standard = 'ОСТ 36-146-88';
          break;
      }

      final typeMark = support.name.isNotEmpty ? support.name : support.type.shortCode;
      final desc = 'Опора ${support.type.displayName.toLowerCase()} для трубы $sizeStr';
      final key = '$desc|$typeMark|$standard|Сталь 3сп5';
      supportMap[key] = (supportMap[key] ?? 0) + 1;
    }

    for (final entry in supportMap.entries) {
      final parts = entry.key.split('|');
      final desc = parts[0];
      final mark = parts[1];
      final std = parts[2];
      final mat = parts[3];
      buffer.writeln(
        '${itemNum++};$desc;$mark;$std;$mat;${entry.value};шт.;Опоры и подвески',
      );
    }

    // 6. Ответные фланцы и прокладки для фланцевой арматуры
    final counterFlangeMap = <String, int>{};
    int totalGaskets = 0;
    for (final v in network.valves.values) {
      if (v.isFlanged && v.includeCounterFlanges) {
        final seg = network.segments[v.segmentId];
        final isTerminalAtStart = seg != null && network.getConnectedSegments(seg.startNodeId).length <= 1 && v.ratio <= 0.35;
        final isTerminalAtEnd = seg != null && network.getConnectedSegments(seg.endNodeId).length <= 1 && v.ratio >= 0.65;
        final count = (isTerminalAtStart || isTerminalAtEnd) ? 1 : 2;
        final key = 'Фланец ответный Ду${v.dn} Ру${v.flangePressurePn}|${v.counterFlangeType}';
        counterFlangeMap[key] = (counterFlangeMap[key] ?? 0) + count;
        totalGaskets += count;
      }
    }
    for (final entry in counterFlangeMap.entries) {
      final parts = entry.key.split('|');
      buffer.writeln(
        '${itemNum++};${parts[0]};—;${parts[1]};Сталь 20;${entry.value};шт.;Комплект арматуры',
      );
    }
    if (totalGaskets > 0) {
      buffer.writeln(
        '${itemNum++};Прокладка межфланцевая ПОН-Б;—;ГОСТ 15180-86;Паронит ПОН-Б;$totalGaskets;шт.;Комплект арматуры',
      );
    }

    // 6b. Ответные фланцы и прокладки для штуцеров оборудования
    final eqCounterFlangeMap = <String, int>{};
    int totalEqGaskets = 0;
    for (final eq in network.equipments.values) {
      for (final noz in eq.nozzles) {
        if (noz.includeInMto) {
          final key = 'Фланец ответный Ду${noz.dn} Ру16|ГОСТ 33259-2015';
          eqCounterFlangeMap[key] = (eqCounterFlangeMap[key] ?? 0) + 1;
          totalEqGaskets += 1;
        }
      }
    }
    for (final entry in eqCounterFlangeMap.entries) {
      final parts = entry.key.split('|');
      buffer.writeln(
        '${itemNum++};${parts[0]};—;${parts[1]};Сталь 20;${entry.value};шт.;Штуцер оборудования',
      );
    }
    if (totalEqGaskets > 0) {
      buffer.writeln(
        '${itemNum++};Прокладка межфланцевая ПОН-Б;—;ГОСТ 15180-86;Паронит ПОН-Б;$totalEqGaskets;шт.;Штуцер оборудования',
      );
    }

    // 7. Сварные соединения (сводка стыков по типам швов)
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
    return projector.projectRaw(node.x, node.y, node.z);
  }

  static void _writeHeader(StringBuffer b) {
    b.writeln('  0\nSECTION\n  2\nHEADER\n  9\n\$ACADVER\n  1\nAC1009\n  0\nENDSEC');
  }

  static void _writeLayers(StringBuffer b, PipingNetwork net, {bool isLayouts = false}) {
    b.writeln('  0\nSECTION\n  2\nTABLES');

    // Таблица типов линий (LTYPE)
    b.writeln('  0\nTABLE\n  2\nLTYPE\n 70\n2');
    b.writeln('  0\nLTYPE\n  2\nCONTINUOUS\n 70\n0\n  3\nSolid line\n 72\n65\n 73\n0\n 40\n0.0');
    b.writeln('  0\nLTYPE\n  2\nDASHDOT\n 70\n0\n  3\nDash dot\n 72\n65\n 73\n4\n 40\n19.05\n 49\n12.7\n 49\n-3.175\n 49\n0.0\n 49\n-3.175');
    b.writeln('  0\nENDTAB');

    // Таблица стилей текста (STYLE) с поддержкой кириллицы (Arial)
    b.writeln('  0\nTABLE\n  2\nSTYLE\n 70\n1');
    b.writeln('  0\nSTYLE\n  2\nSTANDARD\n 70\n0\n 40\n0.0\n 41\n1.0\n 50\n0.0\n 71\n0\n 42\n2.5\n  3\narial.ttf\n  4\n');
    b.writeln('  0\nENDTAB');

    // Таблица слоев (LAYER)
    final layers = <_LayerDef>[
      const _LayerDef('0', 7),
      const _LayerDef('АКСО_ТРУБЫ', 7),
      const _LayerDef('АКСО_ОТМЕТКИ', 2),
      const _LayerDef('АКСО_ОТМЕТКИ_ТЕКСТ', 7),
      const _LayerDef('АКСО_СВАРКА', 1),
      const _LayerDef('АКСО_СВАРКА_ВЫНОСКИ', 1),
      const _LayerDef('АКСО_СВАРКА_ТЕКСТ', 7),
      const _LayerDef('АКСО_АРМАТУРА', 3),
      const _LayerDef('АКСО_ДИАМЕТРЫ', 4),
      const _LayerDef('АКСО_УКЛОНЫ', 30),
      const _LayerDef('АКСО_ПЕРЕХОДЫ', 5),
      const _LayerDef('АКСО_ПЕРЕХОДЫ_ТЕКСТ', 7),
      const _LayerDef('АКСО_ФЛАНЦЫ', 6),
      const _LayerDef('АКСО_ФЛАНЦЫ_ТЕКСТ', 7),
      const _LayerDef('АКСО_ТРОЙНИКИ', 5),
      const _LayerDef('АКСО_ТРОЙНИКИ_ТЕКСТ', 7),
      const _LayerDef('АКСО_ВРЕЗКИ', 1),
      const _LayerDef('АКСО_ОСИ', 8, 'DASHDOT'),
      const _LayerDef('АКСО_ОСИ_ТРАССЫ', 4, 'DASHDOT'),
      const _LayerDef('АКСО_ОСИ_ТЕКСТ', 7),
      const _LayerDef('АКСО_ВСПОМОГАТЕЛЬНЫЕ', 4, 'DASHDOT'),
      const _LayerDef('АКСО_РАЗМЕРЫ', 3),
      const _LayerDef('АКСО_РАЗМЕРЫ_ТЕКСТ', 7),
      const _LayerDef('АКСО_ВЫНОСКИ', 7),
      const _LayerDef('АКСО_ВЫНОСКИ_ТЕКСТ', 4),
      const _LayerDef('АКСО_3D_АРМАТУРА', 1),
      const _LayerDef('АКСО_3D_СВАРНЫЕ_СТЫКИ', 3),
      const _LayerDef('АКСО_3D_ОПОРЫ', 6),
      const _LayerDef('АКСО_ОПОРЫ_ТЕКСТ', 7),
      const _LayerDef('АКСО_3D_ФЛАНЦЫ', 2),
      const _LayerDef('АКСО_3D_ПЕРЕХОДЫ', 5),
      const _LayerDef('АКСО_3D_ЗАГЛУШКИ', 7),
      const _LayerDef('АКСО_ЗАГЛУШКИ', 7),
      const _LayerDef('АКСО_ЗАГЛУШКИ_ТЕКСТ', 7),
      const _LayerDef('АКСО_ОБОРУДОВАНИЕ', 4),
      const _LayerDef('АКСО_ОБОРУДОВАНИЕ_ТЕКСТ', 7),
      const _LayerDef('АКСО_ЛИСТ_РАМКА', 7),
      const _LayerDef('АКСО_ЛИСТ_ШТАМП', 7),
      const _LayerDef('АКСО_ЛИСТ_ТТ', 7),
      const _LayerDef('АКСО_ЛИСТ_ВЭ', 4),
    ];

    for (final sys in net.systems.values) {
      layers.add(_LayerDef('АКСО_${sys.code}', sys.dxfAciColor));
    }

    final uniqueLayers = <String, _LayerDef>{};
    for (final l in layers) {
      uniqueLayers.putIfAbsent(l.name, () => l);
    }

    b.writeln('  0\nTABLE\n  2\nLAYER\n 70\n${uniqueLayers.length}');
    for (final l in uniqueLayers.values) {
      _writeLayerEntry(b, l.name, l.aciColor, l.linetype, isLayouts);
    }

    b.writeln('  0\nENDTAB\n  0\nENDSEC');
  }

  static void _writeLayerEntry(StringBuffer b, String name, int aciColor, [String linetype = 'CONTINUOUS', bool isLayouts = false]) {
    final layerNameStr = isLayouts ? name : toAutoCadString(name);
    b.writeln('  0\nLAYER\n  2\n$layerNameStr\n 70\n0\n 62\n$aciColor\n  6\n$linetype');
  }

  static void _writeBlocks(StringBuffer b, [List<_DxfCalloutBlockDef> blocks = const []]) {
    b.writeln('  0\nSECTION\n  2\nBLOCKS');
    for (final blk in blocks) {
      final calloutLayer = blk.isElevationMark ? toAutoCadString('АКСО_ОТМЕТКИ') : toAutoCadString('АКСО_ВЫНОСКИ');
      final calloutTextLayer = blk.isElevationMark ? toAutoCadString('АКСО_ОТМЕТКИ_ТЕКСТ') : toAutoCadString('АКСО_ВЫНОСКИ_ТЕКСТ');

      if (blk.isMonolithic) {
        b.writeln(
          '  0\nBLOCK\n  8\n0\n  2\n${blk.blockName}\n 70\n0\n 10\n0.0\n 20\n0.0\n 30\n0.0\n  3\n${blk.blockName}',
        );
        if (blk.isElevationMark) {
          const flagH = 35.0;
          const flagW = 20.0;
          final shelfY = blk.elevationStyle == ElevationMarkStyle.compactFlag
              ? blk.localElbowY + 20.0
              : blk.localElbowY + flagH + 15.0;
          if (!blk.arrowOnNode && (blk.localElbowX.abs() > 2.0 || blk.localElbowY.abs() > 2.0)) {
            b.writeln(
              '  0\nLINE\n  8\n$calloutLayer\n 10\n0.0\n 20\n0.0\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${blk.localElbowY.toStringAsFixed(1)}\n 31\n0.0',
            );
          }
          switch (blk.elevationStyle) {
            case ElevationMarkStyle.gostOutline:
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${blk.localElbowY.toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.localElbowX - flagW).toStringAsFixed(1)}\n 21\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.localElbowX - flagW).toStringAsFixed(1)}\n 20\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.localElbowX + flagW).toStringAsFixed(1)}\n 21\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.localElbowX + flagW).toStringAsFixed(1)}\n 20\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${blk.localElbowY.toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              break;

            case ElevationMarkStyle.gostFilled:
              b.writeln(
                '  0\nSOLID\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${blk.localElbowY.toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.localElbowX - flagW).toStringAsFixed(1)}\n 21\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 31\n0.0\n 12\n${(blk.localElbowX + flagW).toStringAsFixed(1)}\n 22\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 32\n0.0\n 13\n${(blk.localElbowX + flagW).toStringAsFixed(1)}\n 23\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 33\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${(blk.localElbowY + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              break;

            case ElevationMarkStyle.compactFlag:
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${blk.localElbowY.toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.localElbowX - 12.0).toStringAsFixed(1)}\n 20\n${(blk.localElbowY + 12.0).toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.localElbowX + 12.0).toStringAsFixed(1)}\n 21\n${(blk.localElbowY - 12.0).toStringAsFixed(1)}\n 31\n0.0',
              );
              break;

            case ElevationMarkStyle.isoCircle:
              const r = 15.0;
              b.writeln(
                '  0\nCIRCLE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${blk.localElbowY.toStringAsFixed(1)}\n 30\n0.0\n 40\n$r',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.localElbowX - r).toStringAsFixed(1)}\n 20\n${blk.localElbowY.toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.localElbowX + r).toStringAsFixed(1)}\n 21\n${blk.localElbowY.toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${(blk.localElbowY - r).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${(blk.localElbowY + r).toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${(blk.localElbowY + r).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              break;
          }
          // Горизонтальная полочка
          b.writeln(
            '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${shelfY.toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localShelfEndX.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
          );
          // Текст
          b.writeln(
            '  0\nTEXT\n  8\n$calloutTextLayer\n 10\n${blk.localTextX.toStringAsFixed(1)}\n 20\n${blk.localTextY.toStringAsFixed(1)}\n 30\n0.0\n 40\n${blk.textHeight.toStringAsFixed(1)}\n  1\n${toAutoCadString(blk.text)}',
          );
          if (blk.bottomText != null && blk.bottomText!.isNotEmpty) {
            final bottomY = shelfY - blk.textHeight - 15.0;
            b.writeln(
              '  0\nTEXT\n  8\n$calloutTextLayer\n 10\n${blk.localTextX.toStringAsFixed(1)}\n 20\n${bottomY.toStringAsFixed(1)}\n 30\n0.0\n 40\n${blk.textHeight.toStringAsFixed(1)}\n  1\n${toAutoCadString(blk.bottomText!)}',
            );
          }
        } else {
          // 1. Маркер привязки к трубе (кружок в начале ножки)
          b.writeln(
            '  0\nCIRCLE\n  8\n$calloutLayer\n 10\n0.0\n 20\n0.0\n 30\n0.0\n 40\n${blk.circleRadius.toStringAsFixed(1)}',
          );
          // 2. Ножка выноски от точки привязки к излому
          b.writeln(
            '  0\nLINE\n  8\n$calloutLayer\n 10\n0.0\n 20\n0.0\n 30\n0.0\n 11\n${blk.localElbowX.toStringAsFixed(1)}\n 21\n${blk.localElbowY.toStringAsFixed(1)}\n 31\n0.0',
          );
          // 3. Горизонтальная полочка
          b.writeln(
            '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.localElbowX.toStringAsFixed(1)}\n 20\n${blk.localElbowY.toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.localShelfEndX.toStringAsFixed(1)}\n 21\n${blk.localElbowY.toStringAsFixed(1)}\n 31\n0.0',
          );
          // 4. Текст на полочке
          b.writeln(
            '  0\nTEXT\n  8\n$calloutTextLayer\n 10\n${blk.localTextX.toStringAsFixed(1)}\n 20\n${blk.localTextY.toStringAsFixed(1)}\n 30\n0.0\n 40\n${blk.textHeight.toStringAsFixed(1)}\n  1\n${toAutoCadString(blk.text)}',
          );
          if (blk.bottomText != null && blk.bottomText!.isNotEmpty) {
            final bottomY = blk.localElbowY - blk.textHeight - 10.0;
            b.writeln(
              '  0\nTEXT\n  8\n$calloutTextLayer\n 10\n${blk.localTextX.toStringAsFixed(1)}\n 20\n${bottomY.toStringAsFixed(1)}\n 30\n0.0\n 40\n${blk.textHeight.toStringAsFixed(1)}\n  1\n${toAutoCadString(blk.bottomText!)}',
            );
          }
        }
        b.writeln('  0\nENDBLK\n  8\n0');
      } else {
        b.writeln(
          '  0\nBLOCK\n  8\n0\n  2\n${blk.blockName}\n 70\n0\n 10\n0.0\n 20\n0.0\n 30\n0.0\n  3\n${blk.blockName}',
        );
        if (blk.isElevationMark) {
          const flagH = 30.0;
          const flagW = 18.0;
          final shelfY = blk.elevationStyle == ElevationMarkStyle.compactFlag
              ? blk.dy + 18.0
              : blk.dy + flagH + 15.0;
          final distSq = blk.dx * blk.dx + blk.dy * blk.dy;
          if (!blk.arrowOnNode && distSq > 4.0) {
            b.writeln(
              '  0\nLINE\n  8\n$calloutLayer\n 10\n0.0\n 20\n0.0\n 30\n0.0\n 11\n${blk.dx.toStringAsFixed(1)}\n 21\n${blk.dy.toStringAsFixed(1)}\n 31\n0.0',
            );
          }
          switch (blk.elevationStyle) {
            case ElevationMarkStyle.gostOutline:
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${blk.dy.toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.dx - flagW).toStringAsFixed(1)}\n 21\n${(blk.dy + flagH).toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.dx - flagW).toStringAsFixed(1)}\n 20\n${(blk.dy + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.dx + flagW).toStringAsFixed(1)}\n 21\n${(blk.dy + flagH).toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.dx + flagW).toStringAsFixed(1)}\n 20\n${(blk.dy + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.dx.toStringAsFixed(1)}\n 21\n${blk.dy.toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${(blk.dy + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.dx.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              break;

            case ElevationMarkStyle.gostFilled:
              b.writeln(
                '  0\nSOLID\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${blk.dy.toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.dx - flagW).toStringAsFixed(1)}\n 21\n${(blk.dy + flagH).toStringAsFixed(1)}\n 31\n0.0\n 12\n${(blk.dx + flagW).toStringAsFixed(1)}\n 22\n${(blk.dy + flagH).toStringAsFixed(1)}\n 32\n0.0\n 13\n${(blk.dx + flagW).toStringAsFixed(1)}\n 23\n${(blk.dy + flagH).toStringAsFixed(1)}\n 33\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${(blk.dy + flagH).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.dx.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              break;

            case ElevationMarkStyle.compactFlag:
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${blk.dy.toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.dx.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.dx - 10.0).toStringAsFixed(1)}\n 20\n${(blk.dy + 10.0).toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.dx + 10.0).toStringAsFixed(1)}\n 21\n${(blk.dy - 10.0).toStringAsFixed(1)}\n 31\n0.0',
              );
              break;

            case ElevationMarkStyle.isoCircle:
              const r = 12.0;
              b.writeln(
                '  0\nCIRCLE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${blk.dy.toStringAsFixed(1)}\n 30\n0.0\n 40\n$r',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${(blk.dx - r).toStringAsFixed(1)}\n 20\n${blk.dy.toStringAsFixed(1)}\n 30\n0.0\n 11\n${(blk.dx + r).toStringAsFixed(1)}\n 21\n${blk.dy.toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${(blk.dy - r).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.dx.toStringAsFixed(1)}\n 21\n${(blk.dy + r).toStringAsFixed(1)}\n 31\n0.0',
              );
              b.writeln(
                '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${(blk.dy + r).toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.dx.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
              );
              break;
          }
          // Горизонтальная полочка
          b.writeln(
            '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx.toStringAsFixed(1)}\n 20\n${shelfY.toStringAsFixed(1)}\n 30\n0.0\n 11\n${blk.shelfEndX.toStringAsFixed(1)}\n 21\n${shelfY.toStringAsFixed(1)}\n 31\n0.0',
          );
          // ATTDEF текста
          b.writeln(
            '  0\nATTDEF\n  8\n$calloutTextLayer\n 10\n${blk.textX.toStringAsFixed(1)}\n 20\n${blk.textY.toStringAsFixed(1)}\n 30\n${blk.textZ}\n 40\n${blk.textHeight}\n  1\n${toAutoCadString(blk.text)}\n  2\nTEXT\n  3\n${toAutoCadString("Отметка уровня")}\n 70\n0',
          );
          if (blk.bottomText != null && blk.bottomText!.isNotEmpty) {
            final bottomY = shelfY - blk.textHeight - 15.0;
            b.writeln(
              '  0\nATTDEF\n  8\n$calloutTextLayer\n 10\n${blk.textX.toStringAsFixed(1)}\n 20\n${bottomY.toStringAsFixed(1)}\n 30\n${blk.textZ}\n 40\n${blk.textHeight}\n  1\n${toAutoCadString(blk.bottomText!)}\n  2\nBOTTOM_TEXT\n  3\n${toAutoCadString("Пояснение отметки")}\n 70\n0',
            );
          }
        } else {
          // Кружок в точке привязки
          b.writeln(
            '  0\nCIRCLE\n  8\n$calloutLayer\n 10\n0.0\n 20\n0.0\n 30\n0.0\n 40\n${blk.circleRadius}',
          );
          // Наклонная ножка выноски
          b.writeln(
            '  0\nLINE\n  8\n$calloutLayer\n 10\n0.0\n 20\n0.0\n 30\n0.0\n 11\n${blk.dx}\n 21\n${blk.dy}\n 31\n${blk.dz}',
          );
          // Горизонтальная полочка
          b.writeln(
            '  0\nLINE\n  8\n$calloutLayer\n 10\n${blk.dx}\n 20\n${blk.dy}\n 30\n${blk.dz}\n 11\n${blk.shelfEndX}\n 21\n${blk.dy}\n 31\n${blk.dz}',
          );
          // Определение атрибута текста (ATTDEF)
          b.writeln(
            '  0\nATTDEF\n  8\n$calloutTextLayer\n 10\n${blk.textX}\n 20\n${blk.textY}\n 30\n${blk.textZ}\n 40\n${blk.textHeight}\n  1\n${toAutoCadString(blk.text)}\n  2\nTEXT\n  3\n${toAutoCadString("Текст выноски")}\n 70\n0',
          );
          if (blk.bottomText != null && blk.bottomText!.isNotEmpty) {
            final bottomY = blk.textY - blk.textHeight - 20.0;
            b.writeln(
              '  0\nATTDEF\n  8\n$calloutTextLayer\n 10\n${blk.textX}\n 20\n$bottomY\n 30\n${blk.textZ}\n 40\n${blk.textHeight}\n  1\n${toAutoCadString(blk.bottomText!)}\n  2\nBOTTOM_TEXT\n  3\n${toAutoCadString("Текст под полкой")}\n 70\n0',
            );
          }
        }
        b.writeln('  0\nENDBLK\n  8\n0');
      }
    }
    b.writeln('  0\nENDSEC');
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
      '  0\nLINE\n  8\n${toAutoCadString(layer)}\n 10\n$x1\n 20\n$y1\n 30\n$z1\n 11\n$x2\n 21\n$y2\n 31\n$z2',
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
      '  0\nLINE\n  8\n${toAutoCadString(layer)}\n 10\n$x1\n 20\n$y1\n 30\n0.0\n 11\n$x2\n 21\n$y2\n 31\n0.0',
    );
  }

  static void _writeCircle(
    StringBuffer b, {
    required String layer,
    required double cx,
    required double cy,
    double cz = 0.0,
    required double radius,
  }) {
    b.writeln(
      '  0\nCIRCLE\n  8\n${toAutoCadString(layer)}\n 10\n$cx\n 20\n$cy\n 30\n$cz\n 40\n$radius',
    );
  }

  static void _writePoint(
    StringBuffer b, {
    required String layer,
    required double x,
    required double y,
    required double z,
  }) {
    b.writeln('  0\nPOINT\n  8\n${toAutoCadString(layer)}\n 10\n$x\n 20\n$y\n 30\n$z');
  }

  static void _writeText(
    StringBuffer b, {
    required String layer,
    required String text,
    required double x,
    required double y,
    required double z,
    required double height,
    int align = 0, // 0 = left, 1 = center
    double rotation = 0.0,
  }) {
    if (text.isEmpty) return;
    b.writeln(
      '  0\nTEXT\n  8\n${toAutoCadString(layer)}\n 10\n$x\n 20\n$y\n 30\n$z\n 40\n$height\n  1\n${toAutoCadString(text)}\n 72\n$align\n 11\n$x\n 21\n$y\n 31\n$z${rotation != 0.0 ? '\n 50\n$rotation' : ''}',
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

  static void _writeGostSupport2d(
    StringBuffer b, {
    required Offset center,
    required Offset u,
    required Offset n,
    required PipeSupport support,
  }) {
    const layer = 'АКСО_3D_ОПОРЫ';
    const textLayer = 'АКСО_ОПОРЫ_ТЕКСТ';

    // Хомут на трубе
    _write2dLine(
      b,
      layer: layer,
      x1: center.dx - u.dx * 12.0,
      y1: center.dy - u.dy * 12.0,
      x2: center.dx + u.dx * 12.0,
      y2: center.dy + u.dy * 12.0,
    );

    switch (support.type) {
      case PipeSupportType.fixed:
        final baseCenter = center + n * 35.0;
        final baseLeft = baseCenter - u * 20.0;
        final baseRight = baseCenter + u * 20.0;

        // Треугольная стойка
        _write2dLine(b, layer: layer, x1: center.dx, y1: center.dy, x2: baseLeft.dx, y2: baseLeft.dy);
        _write2dLine(b, layer: layer, x1: center.dx, y1: center.dy, x2: baseRight.dx, y2: baseRight.dy);
        // Опорная плита
        final plateLeft = baseCenter - u * 26.0;
        final plateRight = baseCenter + u * 26.0;
        _write2dLine(b, layer: layer, x1: plateLeft.dx, y1: plateLeft.dy, x2: plateRight.dx, y2: plateRight.dy);
        // Штриховка заделки
        for (int i = -2; i <= 2; i++) {
          final pBase = baseCenter + u * (i * 10.0);
          final pEnd = pBase + n * 10.0 + u * 8.0;
          _write2dLine(b, layer: layer, x1: pBase.dx, y1: pBase.dy, x2: pEnd.dx, y2: pEnd.dy);
        }
        break;

      case PipeSupportType.sliding:
        final shoeCenter = center + n * 22.0;
        _write2dLine(b, layer: layer, x1: center.dx, y1: center.dy, x2: shoeCenter.dx, y2: shoeCenter.dy);
        // Верхняя скользящая планка
        final shoeLeft = shoeCenter - u * 18.0;
        final shoeRight = shoeCenter + u * 18.0;
        _write2dLine(b, layer: layer, x1: shoeLeft.dx, y1: shoeLeft.dy, x2: shoeRight.dx, y2: shoeRight.dy);
        // Нижняя опорная плита
        final baseCenter = center + n * 32.0;
        final baseLeft = baseCenter - u * 24.0;
        final baseRight = baseCenter + u * 24.0;
        _write2dLine(b, layer: layer, x1: baseLeft.dx, y1: baseLeft.dy, x2: baseRight.dx, y2: baseRight.dy);
        // Штриховка основания
        for (int i = -2; i <= 2; i++) {
          final pBase = baseCenter + u * (i * 9.0);
          final pEnd = pBase + n * 9.0 + u * 7.0;
          _write2dLine(b, layer: layer, x1: pBase.dx, y1: pBase.dy, x2: pEnd.dx, y2: pEnd.dy);
        }
        break;

      case PipeSupportType.spring:
        final up = -n;
        final springStart = center + up * 15.0;
        final springEnd = center + up * 45.0;
        final anchor = center + up * 55.0;

        _write2dLine(b, layer: layer, x1: center.dx, y1: center.dy, x2: springStart.dx, y2: springStart.dy);
        // Зигзаг пружины
        const coils = 4;
        final segLen = (45.0 - 15.0) / coils;
        var prevPt = springStart;
        for (int i = 0; i < coils; i++) {
          final sign = (i % 2 == 0) ? 1.0 : -1.0;
          final mid = springStart + up * (i * segLen + segLen * 0.5) + u * (sign * 12.0);
          final next = springStart + up * ((i + 1) * segLen);
          _write2dLine(b, layer: layer, x1: prevPt.dx, y1: prevPt.dy, x2: mid.dx, y2: mid.dy);
          _write2dLine(b, layer: layer, x1: mid.dx, y1: mid.dy, x2: next.dx, y2: next.dy);
          prevPt = next;
        }
        _write2dLine(b, layer: layer, x1: springEnd.dx, y1: springEnd.dy, x2: anchor.dx, y2: anchor.dy);
        // Плита подвеса
        final plateLeft = anchor - u * 20.0;
        final plateRight = anchor + u * 20.0;
        _write2dLine(b, layer: layer, x1: plateLeft.dx, y1: plateLeft.dy, x2: plateRight.dx, y2: plateRight.dy);
        break;

      case PipeSupportType.guide:
        final shoeCenter = center + n * 22.0;
        _write2dLine(b, layer: layer, x1: center.dx, y1: center.dy, x2: shoeCenter.dx, y2: shoeCenter.dy);
        final shoeLeft = shoeCenter - u * 18.0;
        final shoeRight = shoeCenter + u * 18.0;
        _write2dLine(b, layer: layer, x1: shoeLeft.dx, y1: shoeLeft.dy, x2: shoeRight.dx, y2: shoeRight.dy);
        // Боковые упоры
        final stopLeft = shoeLeft - n * 14.0;
        final stopRight = shoeRight - n * 14.0;
        _write2dLine(b, layer: layer, x1: shoeLeft.dx, y1: shoeLeft.dy, x2: stopLeft.dx, y2: stopLeft.dy);
        _write2dLine(b, layer: layer, x1: shoeRight.dx, y1: shoeRight.dy, x2: stopRight.dx, y2: stopRight.dy);
        // Основание
        final baseCenter = center + n * 32.0;
        final baseLeft = baseCenter - u * 24.0;
        final baseRight = baseCenter + u * 24.0;
        _write2dLine(b, layer: layer, x1: baseLeft.dx, y1: baseLeft.dy, x2: baseRight.dx, y2: baseRight.dy);
        break;
    }

    // Текстовая маркировка опоры
    final label = support.name.isNotEmpty ? support.name : support.type.shortCode;
    _writeText(
      b,
      layer: textLayer,
      text: label,
      x: center.dx + n.dx * 55.0,
      y: center.dy + n.dy * 55.0,
      z: 0.0,
      height: 35.0,
    );
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

  static void _writeGostCap2d(
    StringBuffer b, {
    required Offset center,
    required double angle,
    required int dn,
  }) {
    final h = math.max(16.0, dn * 0.35);
    final depth = math.max(18.0, dn * 0.4);

    Offset transform(double lx, double ly) {
      final rx = lx * math.cos(angle) - ly * math.sin(angle);
      final ry = lx * math.sin(angle) + ly * math.cos(angle);
      return Offset(center.dx + rx, center.dy + ry);
    }

    // 1. Поперечная риска монтажного сварного стыка основания днища
    final weldTop = transform(0.0, -h);
    final weldBottom = transform(0.0, h);
    _write2dLine(b, layer: 'АКСО_ЗАГЛУШКИ', x1: weldTop.dx, y1: weldTop.dy, x2: weldBottom.dx, y2: weldBottom.dy);

    // 2. Выпуклая дуга днища (эллиптическая образующая купола)
    const steps = 8;
    Offset? prevPt;
    for (int i = 0; i <= steps; i++) {
      final theta = -math.pi / 2 + (math.pi * i / steps);
      final lx = depth * math.cos(theta);
      final ly = h * math.sin(theta);
      final pt = transform(lx, ly);
      if (prevPt != null) {
        _write2dLine(b, layer: 'АКСО_ЗАГЛУШКИ', x1: prevPt.dx, y1: prevPt.dy, x2: pt.dx, y2: pt.dy);
      }
      prevPt = pt;
    }

    // 3. Текстовая аннотация
    _writeText(
      b,
      layer: 'АКСО_ЗАГЛУШКИ_ТЕКСТ',
      text: 'Заглушка Ду$dn',
      x: center.dx - 20.0,
      y: center.dy + h + 15.0,
      z: 0.0,
      height: 35.0,
    );
  }

  // --- Экспорт Callouts (Умные Выноски как аннотационные блоки AutoCAD) ---


  /// Подготовка определений блоков выносок для 3D DXF
  static List<_DxfCalloutBlockDef> _prepareCallouts3d(
    PipingNetwork network,
    Map<String, String> templates, {
    DxfCalloutType calloutType = DxfCalloutType.monolithicBlock,
    DxfCalloutOrientation calloutOrientation = DxfCalloutOrientation.cameraFacing,
    ({double nx, double ny, double nz}) extrusionVector = (nx: 0.0, ny: 0.0, nz: 1.0),
  }) {
    final blocks = <_DxfCalloutBlockDef>[];
    int idx = 0;

    // Собираем выноски: если пользователь еще не создал выноски в проекте,
    // автоматически генерируем 3D-выноски для сегментов, чтобы трубы в 3D не оставались без подписей
    final sourceCallouts = <Callout>[];
    if (network.callouts.isNotEmpty) {
      sourceCallouts.addAll(network.callouts.values);
    } else {
      for (final seg in network.segments.values) {
        sourceCallouts.add(Callout(
          id: 'auto_seg_${seg.id}',
          targetId: seg.id,
          targetType: CalloutTargetType.segment,
          screenOffsetX: 50.0,
          screenOffsetY: -50.0,
        ));
      }
    }

    final double axX, axY;
    if (extrusionVector.nx.abs() < 1 / 64 && extrusionVector.ny.abs() < 1 / 64) {
      axX = 1.0;
      axY = 0.0;
    } else {
      axX = -extrusionVector.ny;
      axY = extrusionVector.nx;
    }

    for (final callout in sourceCallouts) {
      final anchor = CalloutPainter.getTarget3DPoint(network, callout);
      if (anchor == null) continue;

      final text = network.generateCalloutText(callout, templates);
      if (text.isEmpty) continue;
      final bottomText = network.generateCalloutBottomText(callout, templates);

      final userDist = math.sqrt(callout.screenOffsetX * callout.screenOffsetX + callout.screenOffsetY * callout.screenOffsetY);
      final scale = (userDist * 3.5).clamp(200.0, 700.0);
      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left ? false : callout.screenOffsetX >= 0);
      final maxLen = (bottomText != null && bottomText.isNotEmpty) ? math.max(text.length, bottomText.length) : text.length;
      final shelfLen = math.max(140.0, maxLen * 35.0);

      // Локальные координаты выноски в плоскости, повернутой лицом к камере/ракурсу:
      // Локальная ось X направлена горизонтально по экрану (axX, axY, 0)
      // Локальная ось Y направлена вертикально вверх по оси Z (0, 0, 1)
      final isElevation = callout.targetType == CalloutTargetType.node;
      final arrowOnNode = callout.arrowOnNode;
      final effectiveElevStyle = callout.elevationStyle ??
          ElevationMarkStyleExt.fromString(templates['elevation_style']);
      final flagH = isElevation ? 35.0 : 0.0;
      final localElbowX = isElevation && arrowOnNode ? 0.0 : (isRight ? scale * 0.7 : -scale * 0.7);
      final localElbowY = isElevation && arrowOnNode
          ? 0.0
          : (isElevation
              ? math.max(120.0, callout.screenOffsetY.abs() * 3.0).clamp(120.0, 450.0)
              : math.max(180.0, callout.screenOffsetY.abs() * 3.0).clamp(180.0, 500.0));
      final shelfY = isElevation && arrowOnNode
          ? math.max(100.0, callout.screenOffsetY.abs() * 3.0).clamp(100.0, 450.0)
          : (isElevation
              ? (effectiveElevStyle == ElevationMarkStyle.compactFlag ? localElbowY + 20.0 : localElbowY + flagH + 15.0)
              : localElbowY);
      final localShelfEndX = isRight ? localElbowX + shelfLen : localElbowX - shelfLen;
      final localTextX = isRight ? localElbowX + 10.0 : localElbowX - shelfLen + 10.0;
      final localTextY = shelfY + 15.0;

      // Мировые 3D-координаты точки излома (WCS)
      final double elbowX, elbowY, elbowZ;
      if (extrusionVector.nx.abs() < 1 / 64 && extrusionVector.ny.abs() < 1 / 64) {
        // Вид сверху (план XY)
        elbowX = anchor.x + localElbowX;
        elbowY = anchor.y + localElbowY;
        elbowZ = anchor.z;
      } else {
        // Вертикальная плоскость (аксонометрия, изометрия, фасад)
        elbowX = anchor.x + localElbowX * axX;
        elbowY = anchor.y + localElbowX * axY;
        elbowZ = anchor.z + localElbowY;
      }

      idx++;
      blocks.add(_DxfCalloutBlockDef(
        blockName: 'CALLOUT_SHELF_$idx',
        text: text,
        bottomText: bottomText,
        dx: elbowX - anchor.x,
        dy: elbowY - anchor.y,
        dz: elbowZ - anchor.z,
        shelfEndX: elbowX - anchor.x + (isRight ? shelfLen : -shelfLen),
        textX: localTextX,
        textY: localTextY,
        textZ: 0.0,
        localElbowX: localElbowX,
        localElbowY: localElbowY,
        localShelfEndX: localShelfEndX,
        localTextX: localTextX,
        localTextY: localTextY,
        textHeight: 45.0,
        circleRadius: isElevation ? 0.0 : 12.0,
        anchorX: anchor.x,
        anchorY: anchor.y,
        anchorZ: anchor.z,
        elbowX: elbowX,
        elbowY: elbowY,
        elbowZ: elbowZ,
        shelfLen: shelfLen,
        isRight: isRight,
        isMonolithic: calloutType == DxfCalloutType.monolithicBlock,
        isElevationMark: isElevation,
        arrowOnNode: arrowOnNode,
        elevationStyle: effectiveElevStyle,
        nx: extrusionVector.nx,
        ny: extrusionVector.ny,
        nz: extrusionVector.nz,
      ));
    }
    return blocks;
  }

  /// Подготовка определений блоков выносок для 2D аксонометрии / проекции
  static List<_DxfCalloutBlockDef> _prepareCallouts2d(
    PipingNetwork network,
    AxonometryProjector projector,
    Map<String, String> templates,
  ) {
    final blocks = <_DxfCalloutBlockDef>[];
    int idx = 0;
    final effectiveScale = projector.scale > 0.001 ? (1.0 / projector.scale) : 5.0;
    final px2cad = effectiveScale.clamp(1.0, 25.0);

    for (final callout in network.callouts.values) {
      final anchor3D = CalloutPainter.getTarget3DPoint(network, callout);
      if (anchor3D == null) continue;

      final text = network.generateCalloutText(callout, templates);
      if (text.isEmpty) continue;
      final bottomText = network.generateCalloutBottomText(callout, templates);

      final anchorScreen = _projectTo2d(projector, anchor3D);
      final maxLen = (bottomText != null && bottomText.isNotEmpty) ? math.max(text.length, bottomText.length) : text.length;
      final shelfLen = math.max(100.0, maxLen * 35.0);
      final isRight = callout.shelfDirection == ShelfDirection.right
          ? true
          : (callout.shelfDirection == ShelfDirection.left ? false : callout.screenOffsetX >= 0);
      final isElevation = callout.targetType == CalloutTargetType.node;
      final arrowOnNode = callout.arrowOnNode;
      final effectiveElevStyle = callout.elevationStyle ??
          ElevationMarkStyleExt.fromString(templates['elevation_style']);
      final flagH = isElevation ? 30.0 : 0.0;
      final dx = isElevation && arrowOnNode ? 0.0 : callout.screenOffsetX * px2cad;
      final dy = isElevation && arrowOnNode ? 0.0 : -callout.screenOffsetY * px2cad;
      final shelfY = isElevation && arrowOnNode
          ? math.max(60.0, callout.screenOffsetY.abs() * px2cad)
          : (isElevation
              ? (effectiveElevStyle == ElevationMarkStyle.compactFlag ? dy + 18.0 : dy + flagH + 15.0)
              : dy);
      final shelfEndX = isRight ? dx + shelfLen : dx - shelfLen;
      final textX = isRight ? dx + 10.0 : dx - shelfLen + 10.0;
      final textY = shelfY + 15.0;

      idx++;
      blocks.add(_DxfCalloutBlockDef(
        blockName: 'CALLOUT_2D_$idx',
        text: text,
        bottomText: bottomText,
        dx: dx,
        dy: dy,
        dz: 0.0,
        shelfEndX: shelfEndX,
        textX: textX,
        textY: textY,
        textZ: 0.0,
        textHeight: 40.0,
        circleRadius: isElevation ? 0.0 : 8.0,
        anchorX: anchorScreen.dx,
        anchorY: anchorScreen.dy,
        anchorZ: 0.0,
        isElevationMark: isElevation,
        arrowOnNode: arrowOnNode,
        elevationStyle: effectiveElevStyle,
        isRight: isRight,
        shelfLen: shelfLen,
      ));
    }
    return blocks;
  }

  /// Преобразование точки WCS (мировые координаты) в OCS (объектная система координат AutoCAD)
  /// для сущностей с вектором выдавливания 210, 220, 230 по алгоритму Arbitrary Axis Algorithm (AutoCAD)
  static ({double x, double y, double z}) _wcsToOcs(
    double wx,
    double wy,
    double wz,
    ({double nx, double ny, double nz}) normal,
  ) {
    if (normal.nx.abs() < 1 / 64 && normal.ny.abs() < 1 / 64) {
      if (normal.nz < 0) {
        return (x: -wx, y: wy, z: -wz);
      }
      return (x: wx, y: wy, z: wz);
    }

    // Arbitrary Axis Algorithm (спецификация AutoCAD DXF):
    // Wy = (0, 0, 1)
    // Ax = (Wy x N) / |Wy x N| = (-Ny, Nx, 0) / sqrt(Nx^2 + Ny^2)
    final lenAx = math.sqrt(normal.nx * normal.nx + normal.ny * normal.ny);
    final axX = -normal.ny / lenAx;
    final axY = normal.nx / lenAx;
    const axZ = 0.0;

    // Ay = N x Ax = (Ny*0 - Nz*axY, Nz*axX - Nx*0, Nx*axY - Ny*axX)
    final ayX = -normal.nz * axY;
    final ayY = normal.nz * axX;
    final ayZ = normal.nx * axY - normal.ny * axX;

    // Скалярные произведения вектора WCS с базисными векторами OCS (Ax, Ay, Az)
    final ox = wx * axX + wy * axY + wz * axZ;
    final oy = wx * ayX + wy * ayY + wz * ayZ;
    final oz = wx * normal.nx + wy * normal.ny + wz * normal.nz;

    return (x: ox, y: oy, z: oz);
  }

  /// Запись сущностей 3D-выносок в секцию ENTITIES в зависимости от выбранного DxfCalloutType
  static void _writeCalloutEntities3d(
    StringBuffer b,
    List<_DxfCalloutBlockDef> blocks,
    DxfCalloutType calloutType,
    ({double nx, double ny, double nz}) extVec,
  ) {
    for (final blk in blocks) {
      final calloutLayer = blk.isElevationMark ? toAutoCadString('АКСО_ОТМЕТКИ') : toAutoCadString('АКСО_ВЫНОСКИ');
      final calloutTextLayer = blk.isElevationMark ? toAutoCadString('АКСО_ОТМЕТКИ_ТЕКСТ') : toAutoCadString('АКСО_ВЫНОСКИ_ТЕКСТ');

      if (calloutType == DxfCalloutType.monolithicBlock) {
        // Способ 1: Вставка монолитного блока
        // Базовая точка блока (0, 0, 0) в точке привязки на трубе (anchor).
        // Внутри блока: маркер привязки + ножка + полочка + текст!
        // Вектор выдавливания (210, 220, 230) ориентирует весь блок лицом к камере/ракурсу.
        // ВАЖНО: В AutoCAD для INSERT с вектором 210, 220, 230 координаты 10, 20, 30 задаются в OCS!
        final ocsAnchor = _wcsToOcs(blk.anchorX, blk.anchorY, blk.anchorZ, extVec);
        b.writeln(
          '  0\nINSERT\n  8\n$calloutLayer\n  2\n${blk.blockName}\n 10\n${ocsAnchor.x.toStringAsFixed(3)}\n 20\n${ocsAnchor.y.toStringAsFixed(3)}\n 30\n${ocsAnchor.z.toStringAsFixed(3)}\n210\n${extVec.nx.toStringAsFixed(6)}\n220\n${extVec.ny.toStringAsFixed(6)}\n230\n${extVec.nz.toStringAsFixed(6)}',
        );
      } else if (calloutType == DxfCalloutType.mleaderScript) {
        // Способ 3: Нативные МВЫНОСКИ (AcDbMLeader) через скрипт AutoCAD
        // В сам DXF НЕ пишем фиктивные палочки и разрозненный текст, чтобы в чертеже
        // не оставалось дублирующего мусора. Мультивыноски со стрелками и авто-полками
        // создаются через сопровождающий файл скрипта .scr.
        continue;
      } else {
        // Способ 2: Раздельные примитивы (nativeLeader)
        // 1. Маркер точки привязки на трубе (кружок на высоте трубы, если не отметка уровня)
        if (blk.circleRadius > 0.0) {
          _writeCircle(
            b,
            layer: blk.isElevationMark ? 'АКСО_ОТМЕТКИ' : 'АКСО_ВЫНОСКИ',
            cx: blk.anchorX,
            cy: blk.anchorY,
            cz: blk.anchorZ,
            radius: blk.circleRadius,
          );
        }

        // 2. Ножка выноски от трубы к излому
        _write3dLine(
          b,
          layer: blk.isElevationMark ? 'АКСО_ОТМЕТКИ' : 'АКСО_ВЫНОСКИ',
          x1: blk.anchorX,
          y1: blk.anchorY,
          z1: blk.anchorZ,
          x2: blk.elbowX,
          y2: blk.elbowY,
          z2: blk.elbowZ,
        );

        final double axX, axY;
        if (extVec.nx.abs() < 1 / 64 && extVec.ny.abs() < 1 / 64) {
          axX = 1.0;
          axY = 0.0;
        } else {
          axX = -extVec.ny;
          axY = extVec.nx;
        }

        final shelfSigned = blk.isRight ? blk.shelfLen : -blk.shelfLen;
        final shelfEndX = blk.elbowX + shelfSigned * axX;
        final shelfEndY = blk.elbowY + shelfSigned * axY;
        final shelfEndZ = blk.elbowZ;

        // 3. Полочка выноски
        _write3dLine(
          b,
          layer: blk.isElevationMark ? 'АКСО_ОТМЕТКИ' : 'АКСО_ВЫНОСКИ',
          x1: blk.elbowX,
          y1: blk.elbowY,
          z1: blk.elbowZ,
          x2: shelfEndX,
          y2: shelfEndY,
          z2: shelfEndZ,
        );

        if (extVec.nx.abs() < 1 / 64 && extVec.ny.abs() < 1 / 64) {
          // Горизонтальный текст (план сверху XY)
          final textX = blk.isRight ? blk.elbowX + 10.0 : blk.elbowX - blk.shelfLen + 10.0;
          final textY = blk.elbowY + 15.0;
          final textZ = blk.elbowZ;
          _writeText(
            b,
            layer: blk.isElevationMark ? 'АКСО_ОТМЕТКИ_ТЕКСТ' : 'АКСО_ВЫНОСКИ_ТЕКСТ',
            text: blk.text,
            x: textX,
            y: textY,
            z: textZ,
            height: blk.textHeight,
          );
        } else {
          // Вертикальный текст по Z, развернутый лицом к нормали extVec
          final textWorldDist = blk.isRight ? 10.0 : -blk.shelfLen + 10.0;
          final textWorldX = blk.elbowX + textWorldDist * axX;
          final textWorldY = blk.elbowY + textWorldDist * axY;
          final textWorldZ = blk.elbowZ + 15.0;

          final ocsText = _wcsToOcs(textWorldX, textWorldY, textWorldZ, extVec);

          b.writeln(
            '  0\nTEXT\n  8\n$calloutTextLayer\n 10\n${ocsText.x.toStringAsFixed(3)}\n 20\n${ocsText.y.toStringAsFixed(3)}\n 30\n${ocsText.z.toStringAsFixed(3)}\n 40\n${blk.textHeight.toStringAsFixed(1)}\n  1\n${toAutoCadString(blk.text)}\n210\n${extVec.nx.toStringAsFixed(6)}\n220\n${extVec.ny.toStringAsFixed(6)}\n230\n${extVec.nz.toStringAsFixed(6)}',
          );
        }
      }
    }
  }

  static void _writeEquipment3d(StringBuffer b, PipingNetwork net) {
    if (net.equipments.isEmpty) return;

    for (final eq in net.equipments.values) {
      final rad = eq.rotationAngleDeg * math.pi / 180.0;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      Offset rot(double lx, double ly) {
        return Offset(
          eq.x + lx * cosA - ly * sinA,
          eq.y + lx * sinA + ly * cosA,
        );
      }

      switch (eq.type) {
        case EquipmentType.box:
          final halfW = eq.width / 2.0;
          final halfL = eq.length / 2.0;

          final c0 = rot(-halfW, -halfL);
          final c1 = rot(halfW, -halfL);
          final c2 = rot(halfW, halfL);
          final c3 = rot(-halfW, halfL);

          final z1 = eq.z;
          final z2 = eq.z + eq.height;

          // Нижняя грань
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c0.dx, y1: c0.dy, z1: z1, x2: c1.dx, y2: c1.dy, z2: z1);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c1.dx, y1: c1.dy, z1: z1, x2: c2.dx, y2: c2.dy, z2: z1);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c2.dx, y1: c2.dy, z1: z1, x2: c3.dx, y2: c3.dy, z2: z1);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c3.dx, y1: c3.dy, z1: z1, x2: c0.dx, y2: c0.dy, z2: z1);

          // Верхняя грань
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c0.dx, y1: c0.dy, z1: z2, x2: c1.dx, y2: c1.dy, z2: z2);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c1.dx, y1: c1.dy, z1: z2, x2: c2.dx, y2: c2.dy, z2: z2);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c2.dx, y1: c2.dy, z1: z2, x2: c3.dx, y2: c3.dy, z2: z2);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c3.dx, y1: c3.dy, z1: z2, x2: c0.dx, y2: c0.dy, z2: z2);

          // Вертикальные ребра
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c0.dx, y1: c0.dy, z1: z1, x2: c0.dx, y2: c0.dy, z2: z2);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c1.dx, y1: c1.dy, z1: z1, x2: c1.dx, y2: c1.dy, z2: z2);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c2.dx, y1: c2.dy, z1: z1, x2: c2.dx, y2: c2.dy, z2: z2);
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: c3.dx, y1: c3.dy, z1: z1, x2: c3.dx, y2: c3.dy, z2: z2);
          break;

        case EquipmentType.cylinderVertical:
          final radius = eq.width / 2;
          const segments = 16;
          final bottomPts = <Offset>[];
          final topPts = <Offset>[];
          for (int i = 0; i < segments; i++) {
            final angle = (2 * math.pi * i) / segments + rad;
            final vx = eq.x + radius * math.cos(angle);
            final vy = eq.y + radius * math.sin(angle);
            bottomPts.add(Offset(vx, vy));
            topPts.add(Offset(vx, vy));
          }
          final z1 = eq.z;
          final z2 = eq.z + eq.height;
          for (int i = 0; i < segments; i++) {
            final next = (i + 1) % segments;
            _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: bottomPts[i].dx, y1: bottomPts[i].dy, z1: z1, x2: bottomPts[next].dx, y2: bottomPts[next].dy, z2: z1);
            _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: topPts[i].dx, y1: topPts[i].dy, z1: z2, x2: topPts[next].dx, y2: topPts[next].dy, z2: z2);
          }
          for (int i = 0; i < segments; i += segments ~/ 4) {
            _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: bottomPts[i].dx, y1: bottomPts[i].dy, z1: z1, x2: topPts[i].dx, y2: topPts[i].dy, z2: z2);
          }
          break;

        case EquipmentType.cylinderHorizontal:
          final radius = eq.height / 2;
          const segments = 16;
          final halfL = eq.length / 2;
          final centerZ = eq.z + radius;
          final startPts = <({double x, double y, double z})>[];
          final endPts = <({double x, double y, double z})>[];
          for (int i = 0; i < segments; i++) {
            final angle = (2 * math.pi * i) / segments;
            final lx = radius * math.cos(angle);
            final vz = centerZ + radius * math.sin(angle);

            final sx = eq.x + lx * cosA - (-halfL) * sinA;
            final sy = eq.y + lx * sinA + (-halfL) * cosA;
            startPts.add((x: sx, y: sy, z: vz));

            final ex = eq.x + lx * cosA - halfL * sinA;
            final ey = eq.y + lx * sinA + halfL * cosA;
            endPts.add((x: ex, y: ey, z: vz));
          }
          for (int i = 0; i < segments; i++) {
            final next = (i + 1) % segments;
            _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: startPts[i].x, y1: startPts[i].y, z1: startPts[i].z, x2: startPts[next].x, y2: startPts[next].y, z2: startPts[next].z);
            _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: endPts[i].x, y1: endPts[i].y, z1: endPts[i].z, x2: endPts[next].x, y2: endPts[next].y, z2: endPts[next].z);
          }
          for (int i = 0; i < segments; i += segments ~/ 4) {
            _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: startPts[i].x, y1: startPts[i].y, z1: startPts[i].z, x2: endPts[i].x, y2: endPts[i].y, z2: endPts[i].z);
          }
          break;
      }

      // Название оборудования в 3D
      _writeText(
        b,
        layer: 'АКСО_ОБОРУДОВАНИЕ_ТЕКСТ',
        text: eq.name,
        x: eq.x,
        y: eq.y,
        z: eq.z + eq.height + 60.0,
        height: 60.0,
        align: 1,
      );

      // Штуцеры оборудования в 3D
      for (final noz in eq.nozzles) {
        final node = net.nodes[noz.id];
        final double wx, wy, wz;
        if (node != null) {
          wx = node.x;
          wy = node.y;
          wz = node.z;
        } else {
          wx = eq.x + noz.localX * cosA - noz.localY * sinA;
          wy = eq.y + noz.localX * sinA + noz.localY * cosA;
          wz = eq.z + noz.localZ;
        }
        final effDir = net.getNozzleEffectiveDirection(noz);
        final spudLen = net.getNozzleEffectiveSpudLength(noz, defaultSpudMm: 120.0);
        final fx = wx + effDir.x * spudLen;
        final fy = wy + effDir.y * spudLen;
        final fz = wz + effDir.z * spudLen;

        final wireframe = Element3dGeometry.generateNozzleWireframe(
          startX: wx,
          startY: wy,
          startZ: wz,
          dirX: effDir.x,
          dirY: effDir.y,
          dirZ: effDir.z,
          dn: noz.dn,
          spudLengthMm: spudLen,
          includeCounterFlange: noz.includeInMto,
        );

        for (final seg in wireframe) {
          _write3dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: seg.x1, y1: seg.y1, z1: seg.z1, x2: seg.x2, y2: seg.y2, z2: seg.z2);
        }

        // Текст штуцера
        final labelText = noz.name.isNotEmpty ? '${noz.name} Ду${noz.dn}' : 'Ду${noz.dn}';
        _writeText(
          b,
          layer: 'АКСО_ОБОРУДОВАНИЕ_ТЕКСТ',
          text: labelText,
          x: fx,
          y: fy,
          z: fz + 40.0,
          height: 40.0,
          align: 1,
        );
      }
    }
  }

  static void _writeEquipment2d(StringBuffer b, PipingNetwork net, AxonometryProjector proj) {
    if (net.equipments.isEmpty) return;

    for (final eq in net.equipments.values) {
      final rad = eq.rotationAngleDeg * math.pi / 180.0;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      Offset rot(double lx, double ly) {
        return Offset(
          eq.x + lx * cosA - ly * sinA,
          eq.y + lx * sinA + ly * cosA,
        );
      }

      switch (eq.type) {
        case EquipmentType.box:
          final halfW = eq.width / 2.0;
          final halfL = eq.length / 2.0;

          final c0 = rot(-halfW, -halfL);
          final c1 = rot(halfW, -halfL);
          final c2 = rot(halfW, halfL);
          final c3 = rot(-halfW, halfL);

          final z1 = eq.z;
          final z2 = eq.z + eq.height;

          final p0 = proj.projectCoordinates(c0.dx, c0.dy, z1);
          final p1 = proj.projectCoordinates(c1.dx, c1.dy, z1);
          final p2 = proj.projectCoordinates(c2.dx, c2.dy, z1);
          final p3 = proj.projectCoordinates(c3.dx, c3.dy, z1);

          final p4 = proj.projectCoordinates(c0.dx, c0.dy, z2);
          final p5 = proj.projectCoordinates(c1.dx, c1.dy, z2);
          final p6 = proj.projectCoordinates(c2.dx, c2.dy, z2);
          final p7 = proj.projectCoordinates(c3.dx, c3.dy, z2);

          final edges = [
            (p0, p1), (p1, p2), (p2, p3), (p3, p0),
            (p4, p5), (p5, p6), (p6, p7), (p7, p4),
            (p0, p4), (p1, p5), (p2, p6), (p3, p7),
          ];
          for (final edge in edges) {
            _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: edge.$1.dx, y1: edge.$1.dy, x2: edge.$2.dx, y2: edge.$2.dy);
          }
          break;

        case EquipmentType.cylinderVertical:
          final radius = eq.width / 2;
          const segments = 16;
          final bottomPts = <Offset>[];
          final topPts = <Offset>[];
          for (int i = 0; i < segments; i++) {
            final angle = (2 * math.pi * i) / segments + rad;
            final vx = eq.x + radius * math.cos(angle);
            final vy = eq.y + radius * math.sin(angle);
            bottomPts.add(proj.projectCoordinates(vx, vy, eq.z));
            topPts.add(proj.projectCoordinates(vx, vy, eq.z + eq.height));
          }
          for (int i = 0; i < segments; i++) {
            final next = (i + 1) % segments;
            _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: bottomPts[i].dx, y1: bottomPts[i].dy, x2: bottomPts[next].dx, y2: bottomPts[next].dy);
            _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: topPts[i].dx, y1: topPts[i].dy, x2: topPts[next].dx, y2: topPts[next].dy);
          }
          for (int i = 0; i < segments; i += segments ~/ 4) {
            _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: bottomPts[i].dx, y1: bottomPts[i].dy, x2: topPts[i].dx, y2: topPts[i].dy);
          }
          break;

        case EquipmentType.cylinderHorizontal:
          final radius = eq.height / 2;
          const segments = 16;
          final halfL = eq.length / 2;
          final centerZ = eq.z + radius;
          final startPts = <Offset>[];
          final endPts = <Offset>[];
          for (int i = 0; i < segments; i++) {
            final angle = (2 * math.pi * i) / segments;
            final lx = radius * math.cos(angle);
            final vz = centerZ + radius * math.sin(angle);

            final sx = eq.x + lx * cosA - (-halfL) * sinA;
            final sy = eq.y + lx * sinA + (-halfL) * cosA;
            startPts.add(proj.projectCoordinates(sx, sy, vz));

            final ex = eq.x + lx * cosA - halfL * sinA;
            final ey = eq.y + lx * sinA + halfL * cosA;
            endPts.add(proj.projectCoordinates(ex, ey, vz));
          }
          for (int i = 0; i < segments; i++) {
            final next = (i + 1) % segments;
            _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: startPts[i].dx, y1: startPts[i].dy, x2: startPts[next].dx, y2: startPts[next].dy);
            _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: endPts[i].dx, y1: endPts[i].dy, x2: endPts[next].dx, y2: endPts[next].dy);
          }
          for (int i = 0; i < segments; i += segments ~/ 4) {
            _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: startPts[i].dx, y1: startPts[i].dy, x2: endPts[i].dx, y2: endPts[i].dy);
          }
          break;
      }

      // Название оборудования в 2D
      final topCenter = proj.projectCoordinates(eq.x, eq.y, eq.z + eq.height);
      _writeText(
        b,
        layer: 'АКСО_ОБОРУДОВАНИЕ_ТЕКСТ',
        text: eq.name,
        x: topCenter.dx,
        y: topCenter.dy + 30.0,
        z: 0.0,
        height: 35.0,
        align: 1,
      );

      // Штуцеры оборудования в 2D
      for (final noz in eq.nozzles) {
        final node = net.nodes[noz.id];
        final double wx, wy, wz;
        if (node != null) {
          wx = node.x;
          wy = node.y;
          wz = node.z;
        } else {
          wx = eq.x + noz.localX * cosA - noz.localY * sinA;
          wy = eq.y + noz.localX * sinA + noz.localY * cosA;
          wz = eq.z + noz.localZ;
        }
        final effDir = net.getNozzleEffectiveDirection(noz);
        final spudLen = net.getNozzleEffectiveSpudLength(noz, defaultSpudMm: 120.0);
        final fx = wx + effDir.x * spudLen;
        final fy = wy + effDir.y * spudLen;
        final fz = wz + effDir.z * spudLen;

        final wireframe = Element3dGeometry.generateNozzleWireframe(
          startX: wx,
          startY: wy,
          startZ: wz,
          dirX: effDir.x,
          dirY: effDir.y,
          dirZ: effDir.z,
          dn: noz.dn,
          spudLengthMm: spudLen,
          includeCounterFlange: noz.includeInMto,
        );

        for (final seg in wireframe) {
          final p1 = proj.projectCoordinates(seg.x1, seg.y1, seg.z1);
          final p2 = proj.projectCoordinates(seg.x2, seg.y2, seg.z2);
          _write2dLine(b, layer: 'АКСО_ОБОРУДОВАНИЕ', x1: p1.dx, y1: p1.dy, x2: p2.dx, y2: p2.dy);
        }

        final pFlange = proj.projectCoordinates(fx, fy, fz);

        // Текст штуцера
        final labelText = noz.name.isNotEmpty ? '${noz.name} Ду${noz.dn}' : 'Ду${noz.dn}';
        _writeText(
          b,
          layer: 'АКСО_ОБОРУДОВАНИЕ_ТЕКСТ',
          text: labelText,
          x: pFlange.dx + 10.0,
          y: pFlange.dy + 10.0,
          z: 0.0,
          height: 25.0,
          align: 0,
        );
      }
    }
  }

  /// Генерация скрипта команд AutoCAD (.scr) для создания нативных МВЫНОСОК (AcDbMLeader)
  static String generateMleaderScript(
    PipingNetwork network, {
    Map<String, String>? calloutTemplates,
    DxfCalloutOrientation calloutOrientation = DxfCalloutOrientation.cameraFacing,
    AxonometryProjector? activeProjector,
  }) {
    final templates = calloutTemplates ?? defaultCalloutTemplates;
    final buffer = StringBuffer();
    // UTF-8 BOM для гарантированного распознавания кодировки кириллицы в AutoCAD (без зависаний)
    buffer.write('\uFEFF');
    buffer.writeln(';; Akso Piping Network MLEADER Script for AutoCAD');
    buffer.writeln('(setvar "CMDECHO" 0)');
    buffer.writeln('(setvar "OSMODE" 0)');
    buffer.writeln('(command "_.LAYER" "_M" "АКСО_ВЫНОСКИ" "")');

    final extVec = calloutOrientation.getExtrusionVector(activeProjector);
    final blocks = _prepareCallouts3d(
      network,
      templates,
      calloutType: DxfCalloutType.mleaderScript,
      calloutOrientation: calloutOrientation,
      extrusionVector: extVec,
    );

    for (final blk in blocks) {
      final fullText = (blk.bottomText != null && blk.bottomText!.isNotEmpty)
          ? '${blk.text}\\P${blk.bottomText!}'
          : blk.text;
      final cleanText = fullText
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"')
          .replaceAll('\r\n', ' ')
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      buffer.writeln(
        '(command "_.MLEADER" "_non" (list ${blk.anchorX.toStringAsFixed(1)} ${blk.anchorY.toStringAsFixed(1)} ${blk.anchorZ.toStringAsFixed(1)}) "_non" (list ${blk.elbowX.toStringAsFixed(1)} ${blk.elbowY.toStringAsFixed(1)} ${blk.elbowZ.toStringAsFixed(1)}) "$cleanText")',
      );
    }

    buffer.writeln('(setvar "CMDECHO" 1)');
    buffer.writeln('(princ "\\nAkso: All MLEADERs created successfully!\\n")');
    buffer.writeln('(princ)');
    return buffer.toString();
  }

  /// Запись сущностей вставки блоков выносок в секцию ENTITIES (INSERT + ATTRIB + SEQEND)
  static void _writeCalloutEntities(StringBuffer b, List<_DxfCalloutBlockDef> blocks) {
    for (final blk in blocks) {
      final calloutLayer = blk.isElevationMark ? toAutoCadString('АКСО_ОТМЕТКИ') : toAutoCadString('АКСО_ВЫНОСКИ');
      final calloutTextLayer = blk.isElevationMark ? toAutoCadString('АКСО_ОТМЕТКИ_ТЕКСТ') : toAutoCadString('АКСО_ВЫНОСКИ_ТЕКСТ');
      b.writeln(
        '  0\nINSERT\n  8\n$calloutLayer\n  2\n${blk.blockName}\n 10\n${blk.anchorX}\n 20\n${blk.anchorY}\n 30\n${blk.anchorZ}\n 66\n1',
      );
      final worldTextX = blk.anchorX + blk.textX;
      final worldTextY = blk.anchorY + blk.textY;
      final worldTextZ = blk.anchorZ + blk.textZ;
      b.writeln(
        '  0\nATTRIB\n  8\n$calloutTextLayer\n 10\n$worldTextX\n 20\n$worldTextY\n 30\n$worldTextZ\n 40\n${blk.textHeight}\n  1\n${toAutoCadString(blk.text)}\n  2\nTEXT\n 70\n0',
      );
      if (blk.bottomText != null && blk.bottomText!.isNotEmpty) {
        final bottomY = worldTextY - blk.textHeight - 20.0;
        b.writeln(
          '  0\nATTRIB\n  8\n$calloutTextLayer\n 10\n$worldTextX\n 20\n$bottomY\n 30\n$worldTextZ\n 40\n${blk.textHeight}\n  1\n${toAutoCadString(blk.bottomText!)}\n  2\nBOTTOM_TEXT\n 70\n0',
        );
      }
      b.writeln('  0\nSEQEND\n  8\n$calloutLayer');
    }
  }
}

/// Вспомогательный класс описания геометрии блока выноски AutoCAD
class _DxfCalloutBlockDef {
  final String blockName;
  final String text;
  final String? bottomText;
  final double dx;
  final double dy;
  final double dz;
  final double shelfEndX;
  final double textX;
  final double textY;
  final double textZ;
  final double localElbowX;
  final double localElbowY;
  final double localShelfEndX;
  final double localTextX;
  final double localTextY;
  final double textHeight;
  final double circleRadius;
  final double anchorX;
  final double anchorY;
  final double anchorZ;
  final double elbowX;
  final double elbowY;
  final double elbowZ;
  final double shelfLen;
  final bool isRight;
  final bool isMonolithic;
  final bool isElevationMark;
  final bool arrowOnNode;
  final ElevationMarkStyle elevationStyle;
  final double nx;
  final double ny;
  final double nz;

  const _DxfCalloutBlockDef({
    required this.blockName,
    required this.text,
    this.bottomText,
    required this.dx,
    required this.dy,
    required this.dz,
    required this.shelfEndX,
    required this.textX,
    required this.textY,
    required this.textZ,
    this.localElbowX = 0.0,
    this.localElbowY = 0.0,
    this.localShelfEndX = 0.0,
    this.localTextX = 0.0,
    this.localTextY = 0.0,
    required this.textHeight,
    required this.circleRadius,
    required this.anchorX,
    required this.anchorY,
    required this.anchorZ,
    this.elbowX = 0.0,
    this.elbowY = 0.0,
    this.elbowZ = 0.0,
    this.shelfLen = 140.0,
    this.isRight = true,
    this.isMonolithic = false,
    this.isElevationMark = false,
    this.arrowOnNode = true,
    this.elevationStyle = ElevationMarkStyle.gostOutline,
    this.nx = 0.0,
    this.ny = 0.0,
    this.nz = 1.0,
  });
}

class _LayerDef {
  final String name;
  final int aciColor;
  final String linetype;

  const _LayerDef(this.name, this.aciColor, [this.linetype = 'CONTINUOUS']);
}
