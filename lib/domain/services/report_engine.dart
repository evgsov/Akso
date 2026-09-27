import '../enums/fitting_type.dart';
import '../enums/inspection_method.dart';
import '../enums/report_type.dart';
import '../enums/valve_type.dart';
import '../enums/weld_type.dart';
import '../models/equipment.dart';
import '../models/fitting.dart';
import '../models/node_3d.dart';
import '../models/pipe_segment.dart';
import '../models/pipe_spool.dart';
import '../models/pipe_support.dart';
import '../models/piping_network.dart';
import '../models/report_template.dart';
import '../models/valve.dart';
import '../models/weld_joint.dart';

/// Ядро вычисления данных отчетов и топологических сопряжений сети
class ReportEngine {
  /// Вычисление строки шаблона с подстановкой значений из контекста
  static String evaluateTemplateString(String template, Map<String, dynamic> context) {
    if (template.isEmpty) return '';

    final regex = RegExp(r'\{([a-zA-Z0-9_]+)\}');
    return template.replaceAllMapped(regex, (match) {
      final key = match.group(1)!;
      final val = context[key];
      if (val == null) return '';
      if (val is double) {
        return val.toString();
      }
      return val.toString();
    });
  }

  /// Топологический анализ примыканий для конкретного сварного стыка
  static Map<String, dynamic> resolveWeldContext(
    WeldJoint weld,
    PipingNetwork network,
    int sequentialIndex,
  ) {
    final context = <String, dynamic>{};

    final seg = network.segments[weld.segmentId];
    final startNode = seg != null ? network.nodes[seg.startNodeId] : null;
    final endNode = seg != null ? network.nodes[seg.endNodeId] : null;

    // 1. Позиция стыка в 3D
    Node3D pos;
    if (startNode != null && endNode != null) {
      pos = weld.calculatePosition(startNode, endNode);
    } else {
      pos = const Node3D(id: 'pos', x: 0, y: 0, z: 0);
    }

    final zMm = pos.z;
    final zSign = zMm >= 0 ? '+' : '';
    final zM = zMm / 1000.0;
    context['z_coord'] = zMm.toInt().toString();
    context['elevation'] = '$zSign${zM.toStringAsFixed(3)}';

    // 2. Общие и геометрические параметры
    context['num'] = sequentialIndex;
    context['weld_num'] = weld.number.toString();
    context['date'] = weld.date.isNotEmpty ? weld.date : DateTime.now().toIso8601String().substring(0, 10);
    context['system'] = seg?.systemId ?? 'В1';
    context['section'] = seg?.systemId ?? '002-ТТ';
    context['weld_type'] = weld.weldType.gostCode;
    context['stamp'] = weld.stamp;
    context['welder'] = 'Иванов И.И.';
    context['brigade_stamp'] = 'А1';
    context['foreman'] = 'Морозов К.С.';
    context['welding_materials'] = weld.electrodeGrade.isNotEmpty ? weld.electrodeGrade : 'УОНИ 13/55';
    context['notes'] = weld.notes.isNotEmpty ? weld.notes : 'Годен';
    context['weld_inspection'] = weld.formattedInspectionMethods;
    context['ndt_method'] = weld.formattedInspectionMethods;
    context['weld_has_vik'] = weld.inspectionMethods.contains(InspectionMethod.vik) ? 'Да' : 'Нет';
    context['weld_has_rk'] = weld.inspectionMethods.contains(InspectionMethod.rk) ? 'Да' : 'Нет';
    context['weld_has_uzk'] = weld.inspectionMethods.contains(InspectionMethod.uzk) ? 'Да' : 'Нет';
    context['weld_has_pvk'] = weld.inspectionMethods.contains(InspectionMethod.pvk) ? 'Да' : 'Нет';
    context['weld_has_mpk'] = weld.inspectionMethods.contains(InspectionMethod.mpk) ? 'Да' : 'Нет';
    context['ndt_vik'] = 'Годен';
    context['ndt_rk'] = 'Годен';
    context['ndt_uzk'] = 'Годен';
    context['report_num'] = 'ПН1415-${context['section']}-${weld.number.toString().padLeft(3, '0')}РС';
    context['report_date'] = context['date'];

    // 3. Элемент №1 (Side 1 - несущая труба / катушка)
    final dn1 = seg?.dn ?? 50;
    final dim1 = network.pipeCatalog.getDimension(dn1);
    final wall1 = dim1?.defaultWallThicknessMm ?? 4.0;
    final std1 = dim1?.standard ?? 'ГОСТ 8732-78';
    final steel1 = seg?.material ?? weld.steelGrade;

    double len1Mm = 0.0;
    if (seg != null && startNode != null && endNode != null) {
      len1Mm = seg.calculateLength(startNode, endNode);
    }
    // Проверим, есть ли катушка
    final matchingSpool = network.spools.values.firstWhere(
      (sp) => sp.segmentId == seg?.id,
      orElse: () => PipeSpool(
        id: 'sp',
        segmentId: seg?.id ?? '',
        number: 'К-$sequentialIndex',
        cutLengthMm: len1Mm,
        dn: dn1,
        wallThickness: wall1,
        material: steel1,
      ),
    );

    context['elem1_name'] = 'Труба';
    context['elem1_dn'] = dn1;
    context['elem1_wall'] = wall1;
    context['elem1_standard'] = std1;
    context['elem1_steel'] = steel1;
    context['elem1_serial'] = '293217.8';
    context['elem1_length'] = matchingSpool.cutLengthMm.toInt();
    context['elem1_manufacturer'] = 'ПАО Северсталь';
    context['elem1_tag'] = matchingSpool.number;

    // 4. Элемент №2 (Side 2 - сопряженный элемент)
    // Определим ближайший узел к сварному стыку
    final distToStart = weld.ratio;
    final distToEnd = 1.0 - weld.ratio;
    final isNearStart = distToStart <= distToEnd;
    final junctionNode = isNearStart ? startNode : endNode;
    context['line_node'] = 'Линия ${context['system']}, Узел ${junctionNode?.id ?? "1"}';

    // 4.1. Проверим штуцер технологического оборудования
    Equipment? connectedEq;
    Nozzle? connectedNoz;
    if (junctionNode != null) {
      for (final eq in network.equipments.values) {
        for (final noz in eq.nozzles) {
          final nozWorldX = eq.x + noz.localX;
          final nozWorldY = eq.y + noz.localY;
          final nozWorldZ = eq.z + noz.localZ;
          final dx = (nozWorldX - junctionNode.x).abs();
          final dy = (nozWorldY - junctionNode.y).abs();
          final dz = (nozWorldZ - junctionNode.z).abs();
          if (dx < 15 && dy < 15 && dz < 15) {
            connectedEq = eq;
            connectedNoz = noz;
            break;
          }
        }
        if (connectedEq != null) break;
      }
    }

    if (connectedEq != null && connectedNoz != null) {
      context['connection_type'] = 'труба-оборудование';
      context['elem2_name'] = 'Штуцер ${connectedNoz.name} аппарата ${connectedEq.name}';
      context['elem2_dn'] = connectedNoz.dn;
      context['elem2_wall'] = wall1;
      context['elem2_standard'] = 'ГОСТ 33259-2015';
      context['elem2_steel'] = '09Г2С';
      context['elem2_serial'] = connectedEq.serialNumber ?? '—';
      context['elem2_length'] = '—';
      context['elem2_manufacturer'] = 'Завод Нефтемаш';
      context['elem2_tag'] = '${connectedEq.name}.${connectedNoz.name}';
      return context;
    }

    // 4.2. Проверим арматуру на этом сегменте
    Valve? connectedValve;
    if (seg != null) {
      for (final v in network.valves.values) {
        if (v.segmentId == seg.id && (v.ratio - weld.ratio).abs() < 0.20) {
          connectedValve = v;
          break;
        }
      }
    }

    if (connectedValve != null) {
      context['connection_type'] = 'труба-арматура';
      context['elem2_name'] = connectedValve.name.isNotEmpty
          ? connectedValve.name
          : '${connectedValve.valveType.displayName} Ду${connectedValve.dn}';
      context['elem2_dn'] = connectedValve.dn;
      context['elem2_wall'] = wall1;
      context['elem2_standard'] = connectedValve.effectiveIsFlanged ? 'ГОСТ 33259-2015' : 'ГОСТ 12815-80';
      context['elem2_steel'] = 'Чугун / Сталь';
      context['elem2_serial'] = connectedValve.serialNumber ?? '16234-24';
      context['elem2_length'] = connectedValve.lengthMm.toInt();
      context['elem2_manufacturer'] = 'ООО БАЗ';
      context['elem2_tag'] = 'А-$sequentialIndex';
      return context;
    }

    // 4.3. Проверим соединительную деталь (Fitting) в узле примыкания
    Fitting? connectedFitting;
    if (junctionNode != null) {
      connectedFitting = network.fittings[junctionNode.id];
    }

    if (connectedFitting != null) {
      context['connection_type'] = 'труба-деталь';
      String fitName = connectedFitting.name ?? connectedFitting.displayName;
      String fitStd = connectedFitting.standard ?? 'ГОСТ 17375-2001';

      switch (connectedFitting.fittingType) {
        case FittingType.elbow90:
        case FittingType.elbow45:
          fitStd = 'ГОСТ 17375-2001';
          break;
        case FittingType.tee:
        case FittingType.directBranch:
        case FittingType.cross:
          fitStd = 'ГОСТ 17376-2001';
          break;
        case FittingType.reducerConcentric:
        case FittingType.reducerEccentric:
          fitStd = 'ГОСТ 17378-2001';
          break;
        case FittingType.flange:
          fitStd = 'ГОСТ 33259-2015';
          break;
        case FittingType.cap:
          fitStd = 'ГОСТ 17379-2001';
          break;
      }

      context['elem2_name'] = fitName;
      context['elem2_dn'] = connectedFitting.dn;
      context['elem2_wall'] = wall1;
      context['elem2_standard'] = fitStd;
      context['elem2_steel'] = connectedFitting.material.isNotEmpty ? connectedFitting.material : steel1;
      context['elem2_serial'] = '16234-24';
      context['elem2_length'] = (connectedFitting.buildingLengthMm ?? connectedFitting.radiusMm * 2).toInt();
      context['elem2_manufacturer'] = 'ООО ТМК';

      String tagPrefix = 'Д';
      if (connectedFitting.fittingType == FittingType.elbow90 || connectedFitting.fittingType == FittingType.elbow45) {
        tagPrefix = 'О';
      } else if (connectedFitting.fittingType == FittingType.tee || connectedFitting.fittingType == FittingType.directBranch) {
        tagPrefix = 'ТР';
      } else if (connectedFitting.fittingType == FittingType.flange) {
        tagPrefix = 'ФЛ';
      } else if (connectedFitting.fittingType == FittingType.reducerConcentric || connectedFitting.fittingType == FittingType.reducerEccentric) {
        tagPrefix = 'ПЕР';
      }
      context['elem2_tag'] = '$tagPrefix-$sequentialIndex';
      return context;
    }

    // 4.4. Проверим смежную трубу / катушку в узле примыкания
    PipeSegment? adjoiningSeg;
    if (junctionNode != null) {
      final connSegs = network.getConnectedSegments(junctionNode.id);
      for (final cs in connSegs) {
        if (cs.id != seg?.id) {
          adjoiningSeg = cs;
          break;
        }
      }
    }

    if (adjoiningSeg != null) {
      context['connection_type'] = 'труба-труба';
      final dim2 = network.pipeCatalog.getDimension(adjoiningSeg.dn);
      final wall2 = dim2?.defaultWallThicknessMm ?? wall1;
      final std2 = dim2?.standard ?? std1;
      final steel2 = adjoiningSeg.material.isNotEmpty ? adjoiningSeg.material : steel1;

      context['elem2_name'] = 'Труба';
      context['elem2_dn'] = adjoiningSeg.dn;
      context['elem2_wall'] = wall2;
      context['elem2_standard'] = std2;
      context['elem2_steel'] = steel2;
      context['elem2_serial'] = '293218.1';
      context['elem2_length'] = 2000;
      context['elem2_manufacturer'] = 'ПАО Северсталь';
      context['elem2_tag'] = 'К-${sequentialIndex + 1}';
      return context;
    }

    // 4.5. По умолчанию (стык двух катушек на одном участке)
    context['connection_type'] = 'труба-труба';
    context['elem2_name'] = 'Труба';
    context['elem2_dn'] = dn1;
    context['elem2_wall'] = wall1;
    context['elem2_standard'] = std1;
    context['elem2_steel'] = steel1;
    context['elem2_serial'] = '293218.1';
    context['elem2_length'] = 2000;
    context['elem2_manufacturer'] = 'ПАО Северсталь';
    context['elem2_tag'] = 'К-${sequentialIndex + 1}';

    return context;
  }

  /// Генерация двумерного массива данных (строки и столбцы) по шаблону и сети
  static List<List<dynamic>> generateTableData(
    ReportTemplate template,
    PipingNetwork network,
  ) {
    switch (template.type) {
      case ReportType.weldJournal:
        return _generateWeldJournalRows(template, network);
      case ReportType.materialsSpecification:
        return _generateMtoRows(template, network);
      case ReportType.spoolsList:
        return _generateSpoolsRows(template, network);
    }
  }

  static List<List<dynamic>> _generateWeldJournalRows(
    ReportTemplate template,
    PipingNetwork network,
  ) {
    final rows = <List<dynamic>>[];
    final welds = network.weldJoints.values.toList()..sort((a, b) => a.number.compareTo(b.number));

    int idx = 1;
    for (final weld in welds) {
      final ctx = resolveWeldContext(weld, network, idx++);
      final row = <dynamic>[];

      for (final col in template.columns) {
        final valStr = evaluateTemplateString(col.template, ctx);
        if (col.isNumeric) {
          final intVal = int.tryParse(valStr);
          if (intVal != null) {
            row.add(intVal);
            continue;
          }
          final dVal = double.tryParse(valStr.replaceAll(',', '.'));
          if (dVal != null) {
            row.add(dVal);
            continue;
          }
        }
        row.add(valStr);
      }
      rows.add(row);
    }

    return rows;
  }

  static List<List<dynamic>> _generateMtoRows(
    ReportTemplate template,
    PipingNetwork network,
  ) {
    final rows = <List<dynamic>>[];
    int itemNum = 1;

    // 1. Оборудование
    final eqMap = <String, int>{};
    final eqData = <String, Equipment>{};
    for (final eq in network.equipments.values) {
      final dims = '${eq.length.toInt()}×${eq.width.toInt()}×${eq.height.toInt()} мм';
      final key = '${eq.name} ($dims)|${eq.type.displayName}|—|Сталь 09Г2С|Технологическое оборудование';
      eqMap[key] = (eqMap[key] ?? 0) + 1;
      eqData[key] = eq;
    }
    for (final entry in eqMap.entries) {
      final parts = entry.key.split('|');
      final eq = eqData[entry.key]!;
      final ctx = {
        'pos': itemNum++,
        'category': 'Оборудование',
        'name': parts[0],
        'type_mark': parts[1],
        'standard': parts[2],
        'material': parts[3],
        'qty': entry.value,
        'unit': 'шт.',
        'mass_kg': 250.0,
        'notes': parts[4] + (eq.serialNumber != null ? ' (зав. № ${eq.serialNumber})' : ''),
        'dn': '—',
        'wall': '—',
      };
      rows.add(_evaluateRow(template.columns, ctx));
    }

    // 2. Трубы
    final pipeMap = <String, double>{};
    final pipeInfo = <String, ({int dn, double wall, String std, String mat})>{};
    for (final seg in network.segments.values) {
      final start = network.nodes[seg.startNodeId];
      final end = network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;
      final lenM = start.distanceTo(end) / 1000.0 * 1.03; // запас 3%
      final dim = network.pipeCatalog.getDimension(seg.dn);
      final std = dim?.standard ?? 'ГОСТ 8732-78';
      final wall = dim?.defaultWallThicknessMm ?? 4.0;
      final key = 'Труба стальная ${seg.formattedSize}|$std|${seg.material}';
      pipeMap[key] = (pipeMap[key] ?? 0.0) + lenM;
      pipeInfo[key] = (dn: seg.dn, wall: wall, std: std, mat: seg.material);
    }
    for (final entry in pipeMap.entries) {
      final parts = entry.key.split('|');
      final info = pipeInfo[entry.key]!;
      final ctx = {
        'pos': itemNum++,
        'category': 'Трубы',
        'name': parts[0],
        'type_mark': '—',
        'standard': parts[1],
        'material': parts[2],
        'qty': double.parse(entry.value.toStringAsFixed(2)),
        'unit': 'м',
        'mass_kg': 12.5,
        'notes': 'Строительный метраж с запасом 3%',
        'dn': info.dn,
        'wall': info.wall,
      };
      rows.add(_evaluateRow(template.columns, ctx));
    }

    // 3. Фасонные детали
    final fittingMap = <String, int>{};
    final fittingData = <String, Fitting>{};
    for (final fit in network.fittings.values) {
      if (fit.fittingType == FittingType.directBranch) continue;
      final key = '${fit.displayName}|${fit.standard ?? "ГОСТ"}|${fit.material}';
      fittingMap[key] = (fittingMap[key] ?? 0) + 1;
      fittingData[key] = fit;
    }
    // Добавляем ответные фланцы от фланцевой арматуры в общую спецификацию фланцев
    for (final v in network.valves.values) {
      if (v.effectiveIsFlanged && v.includeCounterFlanges) {
        final flName = 'Фланец ${v.isFlatCounterFlange ? 'плоский (тип 01)' : 'воротниковый (тип 11)'} Ду${v.dn} Ру${v.flangePressurePn}';
        final key = '$flName|${v.counterFlangeType}|${v.counterFlangeMaterial}';
        fittingMap[key] = (fittingMap[key] ?? 0) + 2;
        fittingData.putIfAbsent(
          key,
          () => Fitting(
            id: 'valve_flange_${v.id}',
            nodeId: '',
            fittingType: FittingType.flange,
            dn: v.dn,
            radiusMm: 0,
            material: v.counterFlangeMaterial,
            standard: v.counterFlangeType,
            pressurePn: v.flangePressurePn,
            name: flName,
          ),
        );
      }
    }
    for (final entry in fittingMap.entries) {
      final parts = entry.key.split('|');
      final fit = fittingData[entry.key]!;
      final fitMark = (fit.mark != null && fit.mark!.isNotEmpty) ? fit.mark! : fit.fittingType.displayName;
      final ctx = {
        'pos': itemNum++,
        'category': 'Фасонные детали',
        'name': parts[0],
        'type_mark': fitMark,
        'mark': fit.mark ?? '—',
        'standard': parts[1],
        'material': parts[2],
        'qty': entry.value,
        'unit': 'шт.',
        'mass_kg': 4.5,
        'notes': 'Фасонные детали',
        'dn': fit.dn,
        'wall': 4.0,
      };
      rows.add(_evaluateRow(template.columns, ctx));
    }

    // 4. Арматура
    final valveMap = <String, int>{};
    final valveData = <String, Valve>{};
    for (final v in network.valves.values) {
      final name = v.name.isNotEmpty ? v.name : v.valveType.displayName;
      final key = '$name|${v.valveType.displayName}|Ду${v.dn}|${v.mark ?? ""}';
      valveMap[key] = (valveMap[key] ?? 0) + 1;
      valveData[key] = v;
    }
    for (final entry in valveMap.entries) {
      final parts = entry.key.split('|');
      final v = valveData[entry.key]!;
      final valveMark = (v.mark != null && v.mark!.isNotEmpty) ? v.mark! : parts[1];
      final ctx = {
        'pos': itemNum++,
        'category': 'Арматура',
        'name': parts[0],
        'type_mark': valveMark,
        'mark': v.mark ?? '—',
        'standard': v.effectiveIsFlanged ? 'ГОСТ 33259-2015' : 'ГОСТ 12815-80',
        'material': 'Чугун / Сталь',
        'qty': entry.value,
        'unit': 'шт.',
        'mass_kg': 18.0,
        'notes': 'Запорно-регулирующая арматура',
        'dn': v.dn,
        'wall': '—',
      };
      rows.add(_evaluateRow(template.columns, ctx));
    }

    // 5. Опоры и подвески
    final supportMap = <String, int>{};
    final supportData = <String, PipeSupport>{};
    for (final sup in network.supports.values) {
      final key = '${sup.type.displayName}|${sup.name}|${sup.mark ?? sup.type.shortCode}';
      supportMap[key] = (supportMap[key] ?? 0) + 1;
      supportData[key] = sup;
    }
    for (final entry in supportMap.entries) {
      final sup = supportData[entry.key]!;
      final markStr = sup.mark ?? sup.type.shortCode;
      final ctx = {
        'pos': itemNum++,
        'category': 'Опоры и подвески',
        'name': 'Опора трубопровода ${sup.type.displayName.toLowerCase()}',
        'type_mark': markStr,
        'mark': markStr,
        'standard': 'ГОСТ 14911-82',
        'material': 'Сталь 3сп5',
        'qty': entry.value,
        'unit': 'шт.',
        'mass_kg': 5.0,
        'notes': sup.name.isNotEmpty ? sup.name : 'Подвижные и неподвижные опоры',
        'dn': '—',
        'wall': '—',
      };
      rows.add(_evaluateRow(template.columns, ctx));
    }

    return rows;
  }

  static List<List<dynamic>> _generateSpoolsRows(
    ReportTemplate template,
    PipingNetwork network,
  ) {
    final rows = <List<dynamic>>[];
    final spools = network.spools.values.toList();

    // Группировка одинаковых катушек по марке sp.number
    final groupedSpools = <String, List<PipeSpool>>{};
    for (final sp in spools) {
      groupedSpools.putIfAbsent(sp.number, () => []).add(sp);
    }

    int idx = 1;
    for (final entry in groupedSpools.entries) {
      final group = entry.value;
      final sp = group.first;
      final count = group.length;
      final totalCutLength = (sp.cutLengthMm * count).round();

      final seg = network.segments[sp.segmentId];
      final startNode = seg != null ? network.nodes[seg.startNodeId] : null;
      final endNode = seg != null ? network.nodes[seg.endNodeId] : null;
      final theoLen = (startNode != null && endNode != null)
          ? seg!.calculateLength(startNode, endNode).round()
          : sp.cutLengthMm.round();

      // Определение примыканий
      String startElem = 'Труба';
      String endElem = 'Труба';
      if (startNode != null) {
        final fit = network.fittings[startNode.id];
        if (fit != null) startElem = fit.displayName;
      }
      if (endNode != null) {
        final fit = network.fittings[endNode.id];
        if (fit != null) endElem = fit.displayName;
      }

      final ctx = {
        'pos': idx++,
        'spool_num': sp.number,
        'qty': count,
        'system': seg?.systemId ?? 'В1',
        'dn': sp.dn,
        'wall': sp.wallThickness,
        'cut_length': sp.cutLengthMm.round(),
        'total_cut_length': totalCutLength,
        'theoretical_length': theoLen,
        'start_element': startElem,
        'end_element': endElem,
        'material': sp.material,
        'standard': 'ГОСТ 8732-78',
        'notes': count > 1 ? 'Длина реза (повторяемость: $count шт.)' : 'Длина реза',
      };
      rows.add(_evaluateRow(template.columns, ctx));
    }

    return rows;
  }

  static List<dynamic> _evaluateRow(List<ReportColumn> columns, Map<String, dynamic> ctx) {
    final row = <dynamic>[];
    for (final col in columns) {
      final valStr = evaluateTemplateString(col.template, ctx);
      if (col.isNumeric) {
        final intVal = int.tryParse(valStr);
        if (intVal != null) {
          row.add(intVal);
          continue;
        }
        final dVal = double.tryParse(valStr.replaceAll(',', '.'));
        if (dVal != null) {
          row.add(dVal);
          continue;
        }
      }
      row.add(valStr);
    }
    return row;
  }

  /// Генерация демонстрационных данных для предварительного просмотра шаблона
  static List<List<dynamic>> generateSampleData(ReportTemplate template) {
    final sampleContexts = <Map<String, dynamic>>[
      {
        'num': 1,
        'pos': 1,
        'item_pos': 1,
        'item_name': 'Труба стальная электросварная 325х8.0',
        'item_code': 'ТР-325-8',
        'item_standard': 'ГОСТ 10704-91',
        'item_unit': 'м',
        'item_qty': 12.5,
        'mass_kg': 62.5,
        'category': 'Трубы',
        'name': 'Труба 325х8.0',
        'type_mark': 'Сталь 20',
        'standard': 'ГОСТ 10704-91',
        'material': 'Сталь 20',
        'qty': 12.5,
        'unit': 'м',
        'dn': 300,
        'wall': 8.0,
        'weld_num': '001РС',
        'date': '2026-09-20',
        'system': 'В1',
        'section': '002-ТТ',
        'line_node': 'Линия 1, Узел 1',
        'weld_type': 'С17',
        'stamp': 'ИВ-01',
        'welder': 'Иванов И.И.',
        'brigade_stamp': 'А1',
        'foreman': 'Морозов К.С.',
        'welding_materials': 'УОНИ 13/55',
        'connection_type': 'труба-деталь',
        'ndt_method': 'ВИК, РК',
        'ndt_vik': 'Годен',
        'ndt_rk': 'Годен',
        'ndt_uzk': 'Годен',
        'report_num': 'ПН1415-002-001РС',
        'report_date': '2026-09-21',
        'z_coord': '1250',
        'elevation': '+1.250',
        'elem1_name': 'Труба',
        'elem1_dn': 300,
        'elem1_wall': 8.0,
        'elem1_standard': 'ГОСТ 10704-91',
        'elem1_steel': 'Сталь 20',
        'elem1_serial': 'П-1044',
        'elem1_heat': '7412',
        'elem2_name': 'Отвод 90°',
        'elem2_dn': 300,
        'elem2_wall': 8.0,
        'elem2_standard': 'ГОСТ 17375-2001',
        'elem2_steel': 'Сталь 20',
        'elem2_serial': 'ОТ-55',
        'elem2_heat': '9821',
        'spool_num': 'К-1',
        'cut_length': 1250,
        'theoretical_length': 1400,
        'start_element': 'Отвод 90°',
        'end_element': 'Тройник',
        'notes': 'Годен',
      },
      {
        'num': 2,
        'pos': 2,
        'item_pos': 2,
        'item_name': 'Отвод 90° 325х8.0',
        'item_code': 'ОТ-90-325-8',
        'item_standard': 'ГОСТ 17375-2001',
        'item_unit': 'шт.',
        'item_qty': 2,
        'mass_kg': 42.0,
        'category': 'Фасонные детали',
        'name': 'Отвод 90°',
        'type_mark': 'Крутоизогнутый',
        'standard': 'ГОСТ 17375-2001',
        'material': '09Г2С',
        'qty': 2,
        'unit': 'шт.',
        'dn': 300,
        'wall': 8.0,
        'weld_num': '002РС',
        'date': '2026-09-21',
        'system': 'В1',
        'section': '002-ТТ',
        'line_node': 'Линия 1, Узел 2',
        'weld_type': 'С17',
        'stamp': 'ПЕ-02',
        'welder': 'Петров П.П.',
        'brigade_stamp': 'А1',
        'foreman': 'Морозов К.С.',
        'welding_materials': 'LB-52U',
        'connection_type': 'деталь-деталь',
        'ndt_method': 'ВИК, РК',
        'ndt_vik': 'Годен',
        'ndt_rk': 'Годен',
        'ndt_uzk': 'Годен',
        'report_num': 'ПН1415-002-002РС',
        'report_date': '2026-09-22',
        'z_coord': '2400',
        'elevation': '+2.400',
        'elem1_name': 'Отвод 90°',
        'elem1_dn': 300,
        'elem1_wall': 8.0,
        'elem1_standard': 'ГОСТ 17375-2001',
        'elem1_steel': '09Г2С',
        'elem1_serial': 'ОТ-56',
        'elem1_heat': '9821',
        'elem2_name': 'Тройник',
        'elem2_dn': 300,
        'elem2_wall': 8.0,
        'elem2_standard': 'ГОСТ 17376-2001',
        'elem2_steel': '09Г2С',
        'elem2_serial': 'ТР-12',
        'elem2_heat': '3301',
        'spool_num': 'К-2',
        'cut_length': 840,
        'theoretical_length': 950,
        'start_element': 'Тройник',
        'end_element': 'Задвижка',
        'notes': 'Годен',
      },
    ];

    return sampleContexts.map((ctx) => _evaluateRow(template.columns, ctx)).toList();
  }
}
