import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../domain/enums/fitting_type.dart';
import '../../../../domain/enums/inspection_method.dart';
import '../../../../domain/enums/valve_type.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/callout.dart';
import '../../../../domain/models/equipment.dart';
import '../../../../domain/models/pipe_segment.dart';
import '../../../../domain/models/piping_network.dart';
import '../../../canvas/input_controller.dart';

/// Полка выноски в конструкторе шаблонов
enum CalloutShelf { top, bottom }

/// Блок (кирпичик) шаблона выноски — статический текст или интерактивный плейсхолдер
class TemplateBrick {
  final String id;
  final String text;
  final bool isPlaceholder;

  const TemplateBrick({
    required this.id,
    required this.text,
    required this.isPlaceholder,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateBrick &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          isPlaceholder == other.isPlaceholder;

  @override
  int get hashCode => Object.hash(id, text, isPlaceholder);

  @override
  String toString() => 'TemplateBrick(id: $id, text: $text, isPlaceholder: $isPlaceholder)';
}

/// Разбиение строки шаблона на список блоков-кирпичиков (токены)
List<TemplateBrick> parseTemplateToBricks(String template) {
  if (template.isEmpty) return [];

  final bricks = <TemplateBrick>[];
  final regex = RegExp(r'\{[A-Za-z0-9_./:-]+\}');
  int lastEnd = 0;
  int idCounter = 0;

  for (final match in regex.allMatches(template)) {
    if (match.start > lastEnd) {
      final staticText = template.substring(lastEnd, match.start);
      bricks.add(TemplateBrick(
        id: 'txt_${idCounter++}',
        text: staticText,
        isPlaceholder: false,
      ));
    }
    bricks.add(TemplateBrick(
      id: 'ph_${idCounter++}',
      text: match.group(0)!,
      isPlaceholder: true,
    ));
    lastEnd = match.end;
  }

  if (lastEnd < template.length) {
    bricks.add(TemplateBrick(
      id: 'txt_${idCounter++}',
      text: template.substring(lastEnd),
      isPlaceholder: false,
    ));
  }

  return bricks;
}

/// Сборка списка кирпичиков обратно в единую строку шаблона
String bricksToTemplate(List<TemplateBrick> bricks) {
  return bricks.map((b) => b.text).join('');
}

/// Форматирование текста предпросмотра выноски по категории с реалистичными образцами данных по ГОСТ 2.316
String formatPreviewCalloutText(
  String template,
  CalloutTargetType type, {
  PipingNetwork? network,
  String dateFormat = 'DD.MM.YYYY',
  Map<String, String>? templates,
}) {
  if (template.isEmpty) return '';

  final net = network;
  final realSeg = net?.segments.values.firstOrNull;
  final realSpool = net?.spools.values.firstOrNull;
  final realWeld = net?.weldJoints.values.firstOrNull;
  final realValve = net?.valves.values.firstOrNull;
  final realFitting = net?.fittings.values.firstOrNull;
  final realEquipment = net?.equipments.values.firstOrNull;
  final realNozzle = net?.equipments.values.expand((e) => e.nozzles).firstOrNull;
  final realParentEq = realNozzle != null
      ? net?.equipments.values.where((e) => e.nozzles.any((n) => n.id == realNozzle.id)).firstOrNull
      : null;
  final realSupport = net?.supports.values.firstOrNull;
  final realNode = net?.nodes.values.firstOrNull;

  var text = template;

  // 1. Форматирование даты {DATE} и {DATE:FORMAT}
  final dateRegex = RegExp(r'\{DATE(?::([A-Za-z0-9_./-]+))?\}');
  final defaultDateRaw = realWeld?.date.isNotEmpty == true ? realWeld!.date : '2026-09-18';
  final effectiveFormattedDate = formatWeldDate(defaultDateRaw, dateFormat);

  text = text.replaceAllMapped(dateRegex, (match) {
    final inlineFormat = match.group(1);
    if (inlineFormat != null && inlineFormat.isNotEmpty) {
      return formatWeldDate(defaultDateRaw, inlineFormat);
    }
    return effectiveFormattedDate;
  });

  // 2. Специфические плейсхолдеры по категориям объектов
  switch (type) {
    case CalloutTargetType.segment:
      final spoolForSeg = realSeg != null
          ? net?.spools.values.where((s) => s.segmentId == realSeg.id).firstOrNull
          : realSpool;
      final spoolMark = spoolForSeg?.name?.isNotEmpty == true
          ? spoolForSeg!.name!
          : (spoolForSeg?.number.isNotEmpty == true
              ? spoolForSeg!.number
              : (realSeg?.name?.isNotEmpty == true ? realSeg!.name! : 'К-1'));
      final dn = spoolForSeg?.dn ?? realSeg?.dn ?? 80;
      final od = realSeg != null ? realSeg.outerDiameterMm : 89.0;
      final wall = spoolForSeg?.wallThickness ?? realSeg?.wallThicknessMm ?? 4.0;
      final mat = spoolForSeg?.material.isNotEmpty == true
          ? spoolForSeg!.material
          : (realSeg?.material.isNotEmpty == true ? realSeg!.material : 'Сталь 20');
      final sysCode = (realSeg != null && net?.systems[realSeg.systemId] != null)
          ? net!.systems[realSeg.systemId]!.code
          : 'В1';
      final len = spoolForSeg?.cutLengthMm.round() ?? 2400;
      final serial = spoolForSeg?.serialNumber?.isNotEmpty == true
          ? spoolForSeg!.serialNumber!
          : (realSeg?.serialNumber?.isNotEmpty == true ? realSeg!.serialNumber! : '48219');
      final dStr = od.truncateToDouble() == od ? od.toStringAsFixed(0) : od.toStringAsFixed(1);
      final sStr = wall.truncateToDouble() == wall ? wall.toStringAsFixed(0) : wall.toStringAsFixed(1);

      return text
          .replaceAll('{SPOOL}', spoolMark)
          .replaceAll('{NUM}', spoolMark)
          .replaceAll('{ID}', spoolMark)
          .replaceAll('{NAME}', spoolMark)
          .replaceAll('{TAG}', spoolMark)
          .replaceAll('{DN}', '$dn')
          .replaceAll('{WALL}', sStr)
          .replaceAll('{S}', sStr)
          .replaceAll('{D_OUT}', dStr)
          .replaceAll('{OD}', dStr)
          .replaceAll('{OUTER_DIAMETER}', dStr)
          .replaceAll('{MATERIAL}', mat)
          .replaceAll('{STANDARD}', 'ГОСТ 10704-91')
          .replaceAll('{SYSTEM}', sysCode)
          .replaceAll('{CUT_LENGTH}', '$len')
          .replaceAll('{L_CUT}', '$len')
          .replaceAll('{LENGTH}', '$len')
          .replaceAll('{L}', '$len')
          .replaceAll('{SERIAL}', serial)
          .replaceAll('{SERIAL_NUMBER}', serial)
          .replaceAll('{BATCH}', serial)
          .replaceAll('{TECH_ID}', spoolForSeg?.id ?? realSeg?.id ?? 'seg_001');

    case CalloutTargetType.weld:
      final numStr = realWeld != null && realWeld.number > 0 ? '${realWeld.number}' : '1';
      final stamp = realWeld?.stamp.isNotEmpty == true ? realWeld!.stamp : 'СВ-01';
      final typeName = realWeld != null ? realWeld.weldType.shortName : 'С17';
      final steel = realWeld?.steelGrade.isNotEmpty == true ? realWeld!.steelGrade : 'Сталь 20';
      final electrode = realWeld?.electrodeGrade.isNotEmpty == true ? realWeld!.electrodeGrade : 'УОНИ-13/55';
      final method = realWeld != null ? realWeld.inspectionMethod.shortName : 'ВИК+РК';
      final weldSeg = (realWeld?.segmentId != null && net != null) ? net.segments[realWeld!.segmentId] : null;
      final dnStr = '${weldSeg?.dn ?? 80}';
      final wallMm = weldSeg?.wallThicknessMm ?? 4.0;
      final wallStr = wallMm.truncateToDouble() == wallMm ? wallMm.toStringAsFixed(0) : wallMm.toStringAsFixed(1);
      final odMm = weldSeg?.outerDiameterMm ?? 89.0;
      final odStr = odMm.truncateToDouble() == odMm ? odMm.toStringAsFixed(0) : odMm.toStringAsFixed(1);

      return text
          .replaceAll('{NUM}', numStr)
          .replaceAll('{NUMBER}', numStr)
          .replaceAll('{ID}', numStr)
          .replaceAll('{STAMP}', stamp)
          .replaceAll('{TYPE}', typeName)
          .replaceAll('{STEEL}', steel)
          .replaceAll('{MATERIAL}', steel)
          .replaceAll('{ELECTRODE}', electrode)
          .replaceAll('{METHOD}', method)
          .replaceAll('{DN}', dnStr)
          .replaceAll('{WALL}', wallStr)
          .replaceAll('{S}', wallStr)
          .replaceAll('{D_OUT}', odStr)
          .replaceAll('{OD}', odStr)
          .replaceAll('{DIAMETER}', odStr)
          .replaceAll('{WELD_ID}', realWeld?.id ?? 'weld_001')
          .replaceAll('{TECH_ID}', realWeld?.id ?? 'weld_001');

    case CalloutTargetType.valve:
      final name = realValve?.name.isNotEmpty == true ? realValve!.name : 'Задвижка 30с41нж';
      final tag = realValve?.name.isNotEmpty == true ? realValve!.name : 'ЗКЛ-1';
      final dn = realValve?.dn != null && realValve!.dn > 0 ? realValve.dn : 80;
      final typeStr = realValve != null ? realValve.valveType.displayName : 'Задвижка';
      final len = realValve != null ? realValve.lengthMm.round() : 210;
      final serial = realValve?.serialNumber?.isNotEmpty == true ? realValve!.serialNumber! : '48219';

      return text
          .replaceAll('{NAME}', name)
          .replaceAll('{TAG}', tag)
          .replaceAll('{TYPE}', typeStr)
          .replaceAll('{DN}', '$dn')
          .replaceAll('{PN}', 'Ру16')
          .replaceAll('{LENGTH}', '$len')
          .replaceAll('{L}', '$len')
          .replaceAll('{MATERIAL}', 'Сталь 20')
          .replaceAll('{SYSTEM}', 'В1')
          .replaceAll('{SERIAL}', serial)
          .replaceAll('{SERIAL_NUMBER}', serial)
          .replaceAll('{BATCH}', serial)
          .replaceAll('{ID}', name)
          .replaceAll('{TECH_ID}', realValve?.id ?? 'valve_001');

    case CalloutTargetType.fitting:
      final name = realFitting?.name?.isNotEmpty == true
          ? realFitting!.name!
          : (realFitting != null ? realFitting.fittingType.displayName : 'Отвод 90° 89х4');
      final typeStr = realFitting != null ? realFitting.fittingType.displayName : 'Отвод 90°';
      final dn = realFitting?.dn != null && realFitting!.dn > 0 ? realFitting.dn : 80;
      final dn2 = realFitting?.dnSecondary != null && realFitting!.dnSecondary! > 0 ? realFitting.dnSecondary! : dn;
      final standard = realFitting?.standard?.isNotEmpty == true ? realFitting!.standard! : 'ГОСТ 17375-2001';
      final mat = realFitting?.material.isNotEmpty == true ? realFitting!.material : 'Сталь 20';
      final serial = realFitting?.serialNumber?.isNotEmpty == true ? realFitting!.serialNumber! : '48219';

      return text
          .replaceAll('{NAME}', name)
          .replaceAll('{TAG}', 'ОТ-1')
          .replaceAll('{TYPE}', typeStr)
          .replaceAll('{STANDARD}', standard)
          .replaceAll('{MATERIAL}', mat)
          .replaceAll('{SYSTEM}', 'В1')
          .replaceAll('{DN}', '$dn')
          .replaceAll('{DN2}', '$dn2')
          .replaceAll('{SERIAL}', serial)
          .replaceAll('{SERIAL_NUMBER}', serial)
          .replaceAll('{BATCH}', serial)
          .replaceAll('{ID}', name)
          .replaceAll('{TECH_ID}', realFitting?.id ?? 'fit_001');

    case CalloutTargetType.equipment:
      final name = realEquipment?.name.isNotEmpty == true ? realEquipment!.name : 'Емкость Е-1';
      final tag = name.trim().contains(RegExp(r'\s+')) ? name.trim().split(RegExp(r'\s+')).last : name;
      final typeStr = realEquipment != null ? realEquipment.type.displayName : 'Горизонтальный цилиндр';
      final dims = realEquipment != null
          ? '${realEquipment.width.round()}x${realEquipment.length.round()}x${realEquipment.height.round()}'
          : '1200x3000x1500';
      final serial = realEquipment?.serialNumber?.isNotEmpty == true ? realEquipment!.serialNumber! : 'Е-014';

      return text
          .replaceAll('{NAME}', name)
          .replaceAll('{TAG}', tag)
          .replaceAll('{TYPE}', typeStr)
          .replaceAll('{DIMENSIONS}', dims)
          .replaceAll('{SERIAL}', serial)
          .replaceAll('{SERIAL_NUMBER}', serial)
          .replaceAll('{BATCH}', serial)
          .replaceAll('{ID}', tag)
          .replaceAll('{TECH_ID}', realEquipment?.id ?? 'eq_001');

    case CalloutTargetType.nozzle:
      final name = realNozzle?.name.isNotEmpty == true ? realNozzle!.name : 'Ш-1';
      final dn = realNozzle?.dn != null && realNozzle!.dn > 0 ? realNozzle.dn : 80;
      final eqName = realParentEq?.name.isNotEmpty == true ? realParentEq!.name : 'Емкость Е-1';
      final eqTag = eqName.trim().contains(RegExp(r'\s+')) ? eqName.trim().split(RegExp(r'\s+')).last : eqName;
      final face = realNozzle?.face?.name ?? 'top';

      return text
          .replaceAll('{NAME}', name)
          .replaceAll('{TAG}', name)
          .replaceAll('{DN}', '$dn')
          .replaceAll('{EQUIPMENT}', eqName)
          .replaceAll('{EQUIPMENT_TAG}', eqTag)
          .replaceAll('{FACE}', face)
          .replaceAll('{ID}', name)
          .replaceAll('{TECH_ID}', realNozzle?.id ?? 'noz_001');

    case CalloutTargetType.support:
      final name = realSupport?.name.isNotEmpty == true
          ? realSupport!.name
          : (realSupport != null ? realSupport.type.shortCode : 'ОП-1');
      final typeStr = realSupport != null ? realSupport.type.displayName : 'Опора подвижная';
      final code = realSupport != null ? realSupport.type.shortCode : 'ОП';

      return text
          .replaceAll('{NAME}', name)
          .replaceAll('{TAG}', name)
          .replaceAll('{TYPE}', typeStr)
          .replaceAll('{CODE}', code)
          .replaceAll('{ID}', name)
          .replaceAll('{TECH_ID}', realSupport?.id ?? 'sup_001');

    case CalloutTargetType.node:
      final cleanNum = realNode != null
          ? realNode.id.replaceFirst(RegExp(r'^(node_|n_)'), '')
          : '1';
      final zM = realNode?.elevationString ?? '+2.400';
      final zMm = realNode != null ? '${realNode.z.round()}' : '2400';
      final xStr = realNode != null ? '${realNode.x.round()}' : '1200';
      final yStr = realNode != null ? '${realNode.y.round()}' : '800';

      final connectedSegs = realNode != null && net != null ? net.getConnectedSegments(realNode.id) : <PipeSegment>[];
      final primarySeg = connectedSegs.isNotEmpty ? connectedSegs.first : realSeg;
      final pipeDn = primarySeg?.dn ?? 80;
      final pipeOd = primarySeg != null ? primarySeg.outerDiameterMm : 89.0;
      final radiusMeters = (pipeOd / 2.0) / 1000.0;
      final zMeters = (realNode?.z ?? 2400.0) / 1000.0;
      final zTopM = zMeters + radiusMeters;
      final zBotM = zMeters - radiusMeters;

      String formatM(double m) {
        if (m.abs() < 0.0001) return '0.000';
        final sign = m > 0 ? '+' : '';
        return '$sign${m.toStringAsFixed(3)}';
      }

      final zTopStr = formatM(zTopM);
      final zBotStr = formatM(zBotM);
      final sysCode = (primarySeg != null && net?.systems[primarySeg.systemId] != null)
          ? net!.systems[primarySeg.systemId]!.code
          : 'В1';

      return text
          .replaceAll('+{Z_M}', zM)
          .replaceAll('{Z_M}', zM)
          .replaceAll('{Z_MM}', zMm)
          .replaceAll('{Z}', zMm)
          .replaceAll('{TOP}', 'В.Т. $zTopStr')
          .replaceAll('{Z_TOP}', zTopStr)
          .replaceAll('{BOP}', 'Н.Т. $zBotStr')
          .replaceAll('{BOT}', 'Н.Т. $zBotStr')
          .replaceAll('{Z_BOT}', zBotStr)
          .replaceAll('{Z_AXIS}', 'ОСЬ $zM')
          .replaceAll('{DN}', '$pipeDn')
          .replaceAll('{SYSTEM}', sysCode)
          .replaceAll('{NUM}', cleanNum)
          .replaceAll('{NUMBER}', cleanNum)
          .replaceAll('{NAME}', realNode?.customElevation != null ? realNode!.customElevation! : 'Узел $cleanNum')
          .replaceAll('{ID}', cleanNum)
          .replaceAll('{X}', xStr)
          .replaceAll('{Y}', yStr)
          .replaceAll('{TECH_ID}', realNode?.id ?? 'node_001');
  }
}

/// Модальная панель управления умными выносками (Smart Callouts Manager)
/// с поддержкой адаптивного размера, двухполочных выносок по ГОСТ и конструктора шаблонов
class CalloutManagerPanel extends StatefulWidget {
  final PipingInputController controller;

  const CalloutManagerPanel({super.key, required this.controller});

  static Future<void> show(
    BuildContext context, {
    required PipingInputController controller,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CalloutManagerPanel(controller: controller),
    );
  }

  @override
  State<CalloutManagerPanel> createState() => _CalloutManagerPanelState();
}

class _CalloutManagerPanelState extends State<CalloutManagerPanel> {
  CalloutTargetType? _selectedFilterType;
  String _searchQuery = '';
  bool _isMaximized = false;

  // Состояние конструктора шаблонов
  CalloutTargetType _templateType = CalloutTargetType.segment;
  CalloutShelf _activeShelf = CalloutShelf.top;
  final TextEditingController _topTemplateController = TextEditingController();
  final TextEditingController _bottomTemplateController = TextEditingController();
  final FocusNode _topFocusNode = FocusNode();
  final FocusNode _bottomFocusNode = FocusNode();
  String _selectedDateFormat = 'DD.MM.YYYY';

  @override
  void initState() {
    super.initState();
    _selectedDateFormat = widget.controller.currentProject.calloutTemplates['date_format'] ?? 'DD.MM.YYYY';
    _loadTemplateForType(_templateType);
    _topFocusNode.addListener(() {
      if (_topFocusNode.hasFocus && _activeShelf != CalloutShelf.top) {
        setState(() => _activeShelf = CalloutShelf.top);
      }
    });
    _bottomFocusNode.addListener(() {
      if (_bottomFocusNode.hasFocus && _activeShelf != CalloutShelf.bottom) {
        setState(() => _activeShelf = CalloutShelf.bottom);
      }
    });
  }

  @override
  void dispose() {
    _topTemplateController.dispose();
    _bottomTemplateController.dispose();
    _topFocusNode.dispose();
    _bottomFocusNode.dispose();
    super.dispose();
  }

  void _loadTemplateForType(CalloutTargetType type) {
    final templates = widget.controller.currentProject.calloutTemplates;
    final top = templates[type.name] ?? type.defaultTemplate;
    final bottom = templates['${type.name}_bottom'] ?? (type.defaultBottomTemplate ?? '');
    _topTemplateController.text = top;
    _bottomTemplateController.text = bottom;
    _selectedDateFormat = templates['date_format'] ?? 'DD.MM.YYYY';
  }

  void _saveCurrentTemplate() {
    widget.controller.updateCalloutTemplate(_templateType.name, _topTemplateController.text);
    widget.controller.updateCalloutTemplate('${_templateType.name}_bottom', _bottomTemplateController.text);
    widget.controller.updateCalloutTemplate('date_format', _selectedDateFormat);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Шаблон для ${_templateType.displayName} успешно сохранен'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetTemplateToDefault() {
    _topTemplateController.text = _templateType.defaultTemplate;
    _bottomTemplateController.text = _templateType.defaultBottomTemplate ?? '';
    _saveCurrentTemplate();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = _isMaximized ? screenSize.width * 0.98 : math.min(1150.0, screenSize.width * 0.92);
    final dialogHeight = _isMaximized ? screenSize.height * 0.96 : math.min(780.0, screenSize.height * 0.88);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final network = widget.controller.network;
        final allCallouts = network.callouts.values.toList();

        final filteredCallouts = allCallouts.where((c) {
          if (_selectedFilterType != null && c.targetType != _selectedFilterType) {
            return false;
          }
          if (_searchQuery.trim().isNotEmpty) {
            final query = _searchQuery.trim().toLowerCase();
            final topText = widget.controller.getCalloutText(c).toLowerCase();
            final bottomText = (widget.controller.getCalloutBottomText(c) ?? '').toLowerCase();
            final targetId = c.targetId.toLowerCase();
            if (!topText.contains(query) && !bottomText.contains(query) && !targetId.contains(query)) {
              return false;
            }
          }
          return true;
        }).toList();

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: dialogWidth,
            height: dialogHeight,
            padding: const EdgeInsets.all(20),
            child: DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, allCallouts.length),
                  const SizedBox(height: 12),
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Colors.indigo,
                    indicatorColor: Colors.indigo,
                    tabs: [
                      Tab(
                        icon: Icon(Icons.table_chart_outlined, size: 18),
                        text: 'Выноски в проекте',
                      ),
                      Tab(
                        icon: Icon(Icons.tune_outlined, size: 18),
                        text: 'Конструктор шаблонов (ГОСТ / AutoCAD)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Вкладка 1: Таблица выносок
                        Column(
                          children: [
                            _buildToolbar(context),
                            const SizedBox(height: 12),
                            Expanded(
                              child: filteredCallouts.isEmpty
                                  ? _buildEmptyState(allCallouts.isEmpty)
                                  : _buildCalloutsTable(filteredCallouts),
                            ),
                          ],
                        ),
                        // Вкладка 2: Конструктор шаблонов
                        _buildTemplateBuilderTab(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int totalCount) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.label_important_outline, color: Colors.indigo),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Менеджер выносок и аннотаций',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Всего выносок в проекте: $totalCount',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: Icon(_isMaximized ? Icons.fullscreen_exit : Icons.fullscreen),
          tooltip: _isMaximized ? 'Восстановить размер' : 'Развернуть на весь экран',
          onPressed: () {
            setState(() {
              _isMaximized = !_isMaximized;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Закрыть',
        ),
      ],
    );
  }

  Widget _buildGenerateAllButton(BuildContext context) {
    return Tooltip(
      message: 'Сгенерировать все недостающие выноски проекта',
      child: FilledButton.icon(
        onPressed: () {
          final added = widget.controller.generateMissingCallouts();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added > 0
                    ? 'Создано $added новых выносок'
                    : 'Все объекты уже имеют выноски',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('Сгенерировать недостающие'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.indigo,
        ),
      ),
    );
  }

  Widget _buildWeldsButton(BuildContext context) {
    return Tooltip(
      message: 'Сгенерировать технологические стыки на элементах и выноски для них',
      child: FilledButton.tonalIcon(
        onPressed: () {
          final res = widget.controller.generateWeldsAndCallouts();
          final welds = res['welds'] ?? 0;
          final callouts = res['callouts'] ?? 0;
          String msg;
          if (welds > 0 && callouts > 0) {
            msg = 'Сгенерировано стыков: $welds, выносок: $callouts';
          } else if (callouts > 0) {
            msg = 'Создано $callouts выносок для стыков';
          } else if (welds > 0) {
            msg = 'Сгенерировано $welds сварных стыков';
          } else {
            msg = 'Все стыки и их выноски уже созданы';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
          );
        },
        icon: const Icon(Icons.adjust, size: 18),
        label: const Text('Стыки'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildElementsButton(BuildContext context) {
    return Tooltip(
      message: 'Сгенерировать выноски для арматуры, деталей и оборудования',
      child: FilledButton.tonalIcon(
        onPressed: () {
          final added = widget.controller.generateElementCallouts();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added > 0
                    ? 'Создано $added выносок для элементов'
                    : 'Все элементы уже имеют выноски',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.category_outlined, size: 18),
        label: const Text('Элементы'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildElevationsButton(BuildContext context) {
    return Tooltip(
      message: 'Сгенерировать отметки уровня по ГОСТ 21.101 для стояков и свободных концов',
      child: FilledButton.tonalIcon(
        onPressed: () {
          final added = widget.controller.generateElevationCallouts();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added > 0
                    ? 'Создано $added отметок уровня'
                    : 'Все ключевые узлы уже имеют отметки',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.height, size: 18),
        label: const Text('Отметки'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return DropdownButton<CalloutTargetType?>(
      value: _selectedFilterType,
      hint: const Text('Все типы'),
      underline: const SizedBox(),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Все типы'),
        ),
        ...CalloutTargetType.values.map(
          (type) => DropdownMenuItem(
            value: type,
            child: Text(type.displayName),
          ),
        ),
      ],
      onChanged: (val) {
        setState(() {
          _selectedFilterType = val;
        });
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Поиск по тексту или ID объекта...',
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
        });
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1180;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildGenerateAllButton(context),
                  _buildWeldsButton(context),
                  _buildElementsButton(context),
                  _buildElevationsButton(context),
                  _buildFilterDropdown(),
                ],
              ),
              const SizedBox(height: 8),
              _buildSearchField(),
            ],
          );
        }
        return Row(
          children: [
            _buildGenerateAllButton(context),
            const SizedBox(width: 8),
            _buildWeldsButton(context),
            const SizedBox(width: 8),
            _buildElementsButton(context),
            const SizedBox(width: 8),
            _buildElevationsButton(context),
            const SizedBox(width: 12),
            _buildFilterDropdown(),
            const SizedBox(width: 12),
            Expanded(child: _buildSearchField()),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(bool isCompletelyEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isCompletelyEmpty ? Icons.post_add_outlined : Icons.filter_alt_off_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            isCompletelyEmpty
                ? 'В проекте пока нет выносок'
                : 'Нет выносок, соответствующих фильтру',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            isCompletelyEmpty
                ? 'Нажмите «Сгенерировать недостающие», чтобы создать выноски по умолчанию для труб, арматуры и стыков'
                : 'Попробуйте сбросить фильтры или строку поиска',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCalloutsTable(List<Callout> callouts) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Тип', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Объект', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Режим', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Текст над/под полкой', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Смещение', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Действия', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: callouts.map((callout) {
                return _buildDataRow(callout);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(Callout callout) {
    final targetDescription = _getTargetDescription(callout);
    final topText = widget.controller.getCalloutText(callout);
    final bottomText = widget.controller.getCalloutBottomText(callout);

    return DataRow(
      key: ValueKey(callout.id),
      cells: [
        // 1. Тип
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getTypeColor(callout.targetType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _getTypeColor(callout.targetType).withValues(alpha: 0.4)),
            ),
            child: Text(
              callout.targetType.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _getTypeColor(callout.targetType),
              ),
            ),
          ),
        ),
        // 2. Объект
        DataCell(
          SizedBox(
            width: 150,
            child: Text(
              targetDescription,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        // 3. Режим (по шаблону / свой)
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                callout.isCustom ? 'Свой' : 'Шаблон',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: callout.isCustom ? Colors.orange.shade800 : Colors.indigo.shade700,
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: callout.isCustom,
                activeThumbColor: Colors.orange,
                onChanged: (isCustom) {
                  widget.controller.toggleCalloutMode(callout.id, isCustom);
                },
              ),
            ],
          ),
        ),
        // 4. Текст выноски (двухполочный)
        DataCell(
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Text('Над: ', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        topText,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (bottomText != null && bottomText.isNotEmpty)
                  Row(
                    children: [
                      const Text('Под: ', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          bottomText,
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        // 5. Смещение
        DataCell(
          Text(
            '${callout.screenOffsetX.round()}, ${callout.screenOffsetY.round()}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        // 6. Действия
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (callout.isCustom)
                IconButton(
                  icon: const Icon(Icons.edit_note, size: 20, color: Colors.indigo),
                  tooltip: 'Редактировать текст над и под полкой',
                  onPressed: () => _showEditCalloutDialog(context, callout),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                tooltip: 'Удалить выноску',
                onPressed: () {
                  widget.controller.removeCallout(callout.id);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showEditCalloutDialog(BuildContext context, Callout callout) {
    final topCtrl = TextEditingController(text: callout.customText ?? widget.controller.getCalloutText(callout));
    final bottomCtrl = TextEditingController(text: callout.customBottomText ?? widget.controller.getCalloutBottomText(callout) ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Редактирование выноски (${callout.targetType.displayName})'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: topCtrl,
                decoration: const InputDecoration(
                  labelText: 'Текст над полкой (основной)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: bottomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Текст под полкой (дополнительный)',
                  hintText: 'Оставьте пустым, если не требуется',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              widget.controller.updateCalloutCustomText(callout.id, topCtrl.text);
              widget.controller.updateCalloutCustomBottomText(
                callout.id,
                bottomCtrl.text.trim().isEmpty ? null : bottomCtrl.text,
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateBuilderTab(BuildContext context) {
    final availablePlaceholders = _getPlaceholdersForType(_templateType);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Выбор типа объекта и глобального формата даты
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Категория:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<CalloutTargetType>(
                    value: _templateType,
                    items: CalloutTargetType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName),
                      );
                    }).toList(),
                    onChanged: (newType) {
                      if (newType != null) {
                        setState(() {
                          _templateType = newType;
                          _loadTemplateForType(newType);
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  const Text('Формат даты швов:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedDateFormat,
                    items: const [
                      DropdownMenuItem(value: 'DD.MM.YYYY', child: Text('ДД.ММ.ГГГГ (18.09.2026)')),
                      DropdownMenuItem(value: 'DD.MM.YY', child: Text('ДД.ММ.ГГ (18.09.26)')),
                      DropdownMenuItem(value: 'YYYY-MM-DD', child: Text('ГГГГ-ММ-ДД (2026-09-18)')),
                      DropdownMenuItem(value: 'DD/MM/YYYY', child: Text('ДД/ММ/ГГГГ (18/09/2026)')),
                    ],
                    onChanged: (newFormat) {
                      if (newFormat != null) {
                        setState(() {
                          _selectedDateFormat = newFormat;
                          widget.controller.updateCalloutTemplate('date_format', newFormat);
                        });
                      }
                    },
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Сбросить к ГОСТ'),
                    onPressed: _resetTemplateToDefault,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Сохранить'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                    onPressed: _saveCurrentTemplate,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Интерактивные полки (с кирпичиками и прямым вводом) + Предпросмотр
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Левая колонка: полка над полкой и полка под полкой
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildShelfCard(
                      CalloutShelf.top,
                      'Над полкой (основной текст)',
                      _topTemplateController,
                      _topFocusNode,
                    ),
                    const SizedBox(height: 12),
                    _buildShelfCard(
                      CalloutShelf.bottom,
                      'Под полкой (дополнительный текст)',
                      _bottomTemplateController,
                      _bottomFocusNode,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Правая колонка: Интерактивный предпросмотр выноски
              Expanded(
                flex: 2,
                child: Container(
                  height: 230,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 8,
                        left: 12,
                        child: Row(
                          children: [
                            Text(
                              'ПРЕДПРОСМОТР (${_templateType.displayName.toUpperCase()})',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(width: 8),
                            if (_templateType == CalloutTargetType.weld ||
                                _topTemplateController.text.contains('{DATE') ||
                                _bottomTemplateController.text.contains('{DATE'))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _selectedDateFormat,
                                  style: TextStyle(fontSize: 9, color: Colors.indigo.shade700, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Center(
                        child: _buildCalloutPreview(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Доступные плейсхолдеры (чипы) с таргетингом в активную полку
          Card(
            color: Colors.blue.shade50.withValues(alpha: 0.5),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.touch_app_outlined, size: 18, color: Colors.indigo),
                      const SizedBox(width: 8),
                      const Text(
                        'Кликните на чип для вставки в строку:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _activeShelf == CalloutShelf.top ? Colors.indigo.shade100 : Colors.teal.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _activeShelf == CalloutShelf.top ? Colors.indigo : Colors.teal,
                          ),
                        ),
                        child: Text(
                          _activeShelf == CalloutShelf.top ? 'НАД ПОЛКОЙ' : 'ПОД ПОЛКОЙ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: _activeShelf == CalloutShelf.top ? Colors.indigo.shade900 : Colors.teal.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.swap_vert, size: 16),
                        label: Text(
                          _activeShelf == CalloutShelf.top ? 'Переключить на "Под полкой"' : 'Переключить на "Над полкой"',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () {
                          setState(() {
                            _activeShelf = _activeShelf == CalloutShelf.top ? CalloutShelf.bottom : CalloutShelf.top;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: availablePlaceholders.entries.map((entry) {
                      return ActionChip(
                        label: Text('${entry.key} — ${entry.value}'),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.indigo.shade200),
                        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        onPressed: () {
                          _insertChip(entry.key);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfCard(
    CalloutShelf shelf,
    String title,
    TextEditingController controller,
    FocusNode focusNode,
  ) {
    final isActive = _activeShelf == shelf;
    final bricks = parseTemplateToBricks(controller.text);

    return InkWell(
      onTap: () {
        if (_activeShelf != shelf) {
          setState(() => _activeShelf = shelf);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? Colors.indigo.shade50.withValues(alpha: 0.35) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.indigo : Colors.grey.shade300,
            width: isActive ? 2.0 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок полки + бейдж активности
            Row(
              children: [
                Icon(
                  shelf == CalloutShelf.top ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isActive ? Colors.indigo : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isActive ? Colors.indigo.shade900 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Активно для вставки',
                          style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Лента блоков-кирпичиков (Reorderable)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: bricks.isEmpty
                  ? Center(
                      child: Text(
                        '(Полка пуста. Кликните на чип в палитре или введите текст ниже)',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      itemCount: bricks.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final item = bricks.removeAt(oldIndex);
                          bricks.insert(newIndex, item);
                          controller.text = bricksToTemplate(bricks);
                          controller.selection = TextSelection.collapsed(offset: controller.text.length);
                        });
                      },
                      itemBuilder: (context, index) {
                        final brick = bricks[index];
                        return ReorderableDragStartListener(
                          key: ValueKey(brick.id),
                          index: index,
                          child: _buildBrickWidget(brick, index, bricks, controller),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),

            // Прямой ввод текста
            TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                hintText: shelf == CalloutShelf.top ? 'напр: {NAME} Ду{DN} L={L}' : 'напр: {SYSTEM} или пусто',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.edit_note, size: 16),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: 'Очистить строку',
                        onPressed: () {
                          controller.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrickWidget(
    TemplateBrick brick,
    int index,
    List<TemplateBrick> bricks,
    TextEditingController controller,
  ) {
    final isPh = brick.isPlaceholder;
    final bg = isPh ? Colors.indigo.shade50 : const Color(0xFFF1F5F9);
    final border = isPh ? Colors.indigo.shade200 : const Color(0xFFCBD5E1);
    final textStyle = TextStyle(
      fontSize: 11,
      fontFamily: 'monospace',
      fontWeight: isPh ? FontWeight.bold : FontWeight.w500,
      color: isPh ? Colors.indigo.shade900 : const Color(0xFF334155),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.drag_indicator,
            size: 13,
            color: isPh ? Colors.indigo.shade300 : Colors.grey.shade400,
          ),
          const SizedBox(width: 3),
          Text(
            brick.text.trim().isEmpty ? '␣' : brick.text,
            style: textStyle,
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              setState(() {
                bricks.removeAt(index);
                controller.text = bricksToTemplate(bricks);
                controller.selection = TextSelection.collapsed(offset: controller.text.length);
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 13,
                color: isPh ? Colors.indigo.shade400 : Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _insertChip(String placeholder) {
    final controller = _activeShelf == CalloutShelf.top ? _topTemplateController : _bottomTemplateController;
    final text = controller.text;
    final selection = controller.selection;
    if (selection.start >= 0 && selection.end >= 0 && selection.start <= text.length && selection.end <= text.length) {
      final newText = text.replaceRange(selection.start, selection.end, placeholder);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + placeholder.length),
      );
    } else {
      final prefix = (text.isNotEmpty && !text.endsWith(' ') && !placeholder.startsWith(' ')) ? ' ' : '';
      controller.text = text + prefix + placeholder;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }
    setState(() {});
  }

  Widget _buildCalloutPreview() {
    final previewTop = formatPreviewCalloutText(
      _topTemplateController.text,
      _templateType,
      network: widget.controller.network,
      dateFormat: _selectedDateFormat,
      templates: widget.controller.currentProject.calloutTemplates,
    );
    final previewBottom = formatPreviewCalloutText(
      _bottomTemplateController.text,
      _templateType,
      network: widget.controller.network,
      dateFormat: _selectedDateFormat,
      templates: widget.controller.currentProject.calloutTemplates,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Точка на объекте
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            shape: BoxShape.circle,
          ),
        ),
        // Линия-ножка
        Container(
          width: 30,
          height: 1.5,
          color: const Color(0xFF1E293B),
        ),
        // Полочка с текстом
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              previewTop.isNotEmpty ? previewTop : 'Текст над полкой',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1E293B),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              height: 1.5,
              width: math.max(140.0, math.max(previewTop.length, previewBottom.length) * 8.5),
              color: const Color(0xFF1E293B),
            ),
            if (previewBottom.isNotEmpty)
              Text(
                previewBottom,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF475569),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Map<String, String> _getPlaceholdersForType(CalloutTargetType type) {
    switch (type) {
      case CalloutTargetType.segment:
        return {
          '{SPOOL}': 'Марка катушки из ведомости (напр. К-1)',
          '{NUM}': 'Номер катушки или трубы (К-1)',
          '{DN}': 'Диаметр условный (напр. 80)',
          '{WALL}': 'Толщина стенки (напр. 4.0)',
          '{D_OUT}': 'Наружный диаметр (напр. 89)',
          '{CUT_LENGTH}': 'Длина заготовки реза (мм)',
          '{MATERIAL}': 'Марка стали (напр. Сталь 20)',
          '{NAME}': 'Маркировка / наименование (напр. К-1)',
          '{SERIAL}': 'Зав. № / партия (актуально Ду≥500)',
          '{SYSTEM}': 'Код системы (напр. В1)',
          '{ID}': 'Марка катушки / трубы',
        };
      case CalloutTargetType.valve:
        return {
          '{NAME}': 'Наименование арматуры',
          '{TAG}': 'Позиция арматуры',
          '{SERIAL}': 'Заводской номер арматуры',
          '{DN}': 'Диаметр условный',
          '{TYPE}': 'Тип арматуры (задвижка/кран/клапан)',
          '{LENGTH}': 'Строительная длина (мм)',
          '{ID}': 'Наименование / позиция',
        };
      case CalloutTargetType.weld:
        return {
          '{NUM}': 'Номер шва в журнале (напр. 1)',
          '{DATE}': 'Дата выполнения шва (напр. 18.09.2024)',
          '{STAMP}': 'Клеймо сварщика (напр. СВ-01)',
          '{TYPE}': 'Тип сварного шва (С17/У18)',
          '{STEEL}': 'Марка стали стыкуемых труб',
          '{ELECTRODE}': 'Марка электрода',
          '{METHOD}': 'Метод контроля (ВИК/РК/УЗК)',
          '{ID}': 'Номер шва (напр. 1)',
        };
      case CalloutTargetType.fitting:
        return {
          '{NAME}': 'Наименование детали',
          '{TAG}': 'Марка детали',
          '{SERIAL}': 'Зав. № / партия детали',
          '{TYPE}': 'Тип фитинга (отвод/тройник/переход)',
          '{STANDARD}': 'Стандарт ГОСТ',
          '{MATERIAL}': 'Материал детали',
          '{DN}': 'Основной диаметр',
          '{DN2}': 'Вторичный диаметр (для переходов)',
          '{ID}': 'Наименование детали',
        };
      case CalloutTargetType.equipment:
        return {
          '{TAG}': 'Короткая позиция/тег (напр. Е-1, Н-1)',
          '{NAME}': 'Полное наименование оборудования',
          '{TYPE}': 'Тип (насос/бак/емкость)',
          '{DIMENSIONS}': 'Габариты ШхДхВ (мм)',
          '{SERIAL}': 'Заводской номер оборудования',
          '{ID}': 'Позиция аппарата (Е-1)',
        };
      case CalloutTargetType.nozzle:
        return {
          '{NAME}': 'Обозначение штуцера (напр. Ш-1, А1)',
          '{DN}': 'Диаметр условный (напр. 80)',
          '{EQUIPMENT}': 'Наименование аппарата (Емкость Е-1)',
          '{EQUIPMENT_TAG}': 'Позиция аппарата (Е-1)',
          '{FACE}': 'Грань оборудования',
          '{ID}': 'Обозначение штуцера',
        };
      case CalloutTargetType.support:
        return {
          '{NAME}': 'Наименование / марка опоры (напр. ОП-1)',
          '{TYPE}': 'Тип опоры (скользящая/неподвижная)',
          '{CODE}': 'Код типа (ОП/НО/ПП)',
          '{ID}': 'Марка опоры',
        };
      case CalloutTargetType.node:
        return {
          '{Z_M}': 'Отметка в метрах по ГОСТ (напр. +2.400)',
          '{TOP}': 'Верх трубы (напр. В.Т. +2.445)',
          '{BOP}': 'Низ трубы (напр. Н.Т. +2.355)',
          '{Z_AXIS}': 'Ось трубы (напр. ОСЬ +2.400)',
          '{Z}': 'Высота Z в мм (напр. 2400)',
          '{DN}': 'Диаметр примыкающей трубы',
          '{SYSTEM}': 'Код системы (напр. В1)',
          '{NUM}': 'Номер узла',
          '{ID}': 'Номер узла',
          '{X}': 'Координата X (мм)',
          '{Y}': 'Координата Y (мм)',
        };
    }
  }

  String _getTargetDescription(Callout callout) {
    final net = widget.controller.network;
    switch (callout.targetType) {
      case CalloutTargetType.segment:
        final s = net.segments[callout.targetId];
        final spool = net.spools.values.where((sp) => sp.segmentId == callout.targetId).firstOrNull;
        final mark = spool?.number ?? s?.id ?? callout.targetId;
        return s != null ? '$mark (DN${s.dn})' : callout.targetId;
      case CalloutTargetType.valve:
        final v = net.valves[callout.targetId];
        return v != null ? '${v.name} Ду${v.dn}' : callout.targetId;
      case CalloutTargetType.weld:
        final w = net.weldJoints[callout.targetId];
        return w != null ? 'Стык №${w.number > 0 ? w.number : w.id}' : callout.targetId;
      case CalloutTargetType.equipment:
        final eq = net.equipments[callout.targetId];
        return eq != null ? eq.name : callout.targetId;
      case CalloutTargetType.nozzle:
        for (final eq in net.equipments.values) {
          for (final n in eq.nozzles) {
            if (n.id == callout.targetId) {
              return '${n.name} Ду${n.dn} (${eq.name})';
            }
          }
        }
        return 'Штуцер ${callout.targetId}';
      case CalloutTargetType.fitting:
        final f = net.fittings[callout.targetId] ??
            net.fittings.values.where((fit) => fit.id == callout.targetId).firstOrNull;
        return f != null ? (f.name ?? f.fittingType.displayName) : callout.targetId;
      case CalloutTargetType.support:
        final sup = net.supports[callout.targetId];
        return sup != null ? (sup.name.isNotEmpty ? sup.name : sup.type.displayName) : callout.targetId;
      case CalloutTargetType.node:
        return 'Узел ${callout.targetId}';
    }
  }

  Color _getTypeColor(CalloutTargetType type) {
    switch (type) {
      case CalloutTargetType.segment:
        return Colors.blue.shade700;
      case CalloutTargetType.valve:
        return Colors.amber.shade900;
      case CalloutTargetType.weld:
        return Colors.deepPurple.shade700;
      case CalloutTargetType.fitting:
        return Colors.indigo.shade700;
      case CalloutTargetType.equipment:
        return Colors.teal.shade700;
      case CalloutTargetType.nozzle:
        return Colors.cyan.shade800;
      case CalloutTargetType.support:
        return Colors.orange.shade800;
      case CalloutTargetType.node:
        return Colors.blueGrey.shade700;
    }
  }
}

