import 'dart:math' as math;
import '../enums/fitting_type.dart';
import '../enums/projection_type.dart';
import '../enums/sheet_format_type.dart';
import '../enums/viewport_layout_preset.dart';
import 'callout.dart';
import 'drawing_legend.dart';
import 'sheet_view_preset.dart';
import 'fitting.dart';
import 'linear_dimension.dart';
import 'pipe_segment.dart';
import 'pipe_spool.dart';
import 'pipe_support.dart';
import 'piping_network.dart';
import 'sheet_callout_preset.dart';
import 'sheet_format.dart';
import 'title_block_data.dart';
import 'valve.dart';
import 'weld_joint.dart';

/// Видовой экран модели на листе
class SheetViewport {
  /// Координата X левого верхнего угла видового экрана на листе (в мм бумаги)
  final double xMm;

  /// Координата Y левого верхнего угла видового экрана на листе (в мм бумаги)
  final double yMm;

  /// Ширина видового экрана на листе (в мм бумаги)
  final double widthMm;

  /// Высота видового экрана на листе (в мм бумаги)
  final double heightMm;

  /// Центр проецируемой модели, отображаемый в центре видового экрана (мм модели)
  final double modelCenterX;
  final double modelCenterY;
  final double modelCenterZ;

  /// Масштаб видового экрана (например, 0.02 для 1:50, 0.01 для 1:100)
  final double viewScale;

  /// Флаг автоматического вписывания модели в границы видового экрана
  final bool autoFit;

  /// Фильтр отображаемых систем (null = отображать все системы сети)
  final Set<String>? visibleSystemIds;

  /// Приглушенный полупрозрачный показ неактивных систем (для контекста привязки)
  final bool ghostInactiveSystems;

  /// Тип аксонометрической проекции / ракурс видового экрана
  final ProjectionType projectionType;

  /// Углы вращения для 3D-орбиты (в радианах)
  final double orbitAzimuth;
  final double orbitElevation;

  const SheetViewport({
    this.xMm = 25.0,
    this.yMm = 10.0,
    this.widthMm = 380.0,
    this.heightMm = 220.0,
    this.modelCenterX = 0.0,
    this.modelCenterY = 0.0,
    this.modelCenterZ = 0.0,
    this.viewScale = 0.02,
    this.autoFit = true,
    this.visibleSystemIds,
    this.ghostInactiveSystems = false,
    this.projectionType = ProjectionType.gostFrontal45,
    this.orbitAzimuth = -math.pi / 4,
    this.orbitElevation = math.pi / 6,
  });

  Map<String, dynamic> toJson() => {
        'xMm': xMm,
        'yMm': yMm,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'modelCenterX': modelCenterX,
        'modelCenterY': modelCenterY,
        'modelCenterZ': modelCenterZ,
        'viewScale': viewScale,
        'autoFit': autoFit,
        if (visibleSystemIds != null) 'visibleSystemIds': visibleSystemIds!.toList(),
        'ghostInactiveSystems': ghostInactiveSystems,
        'projectionType': projectionType.name,
        'orbitAzimuth': orbitAzimuth,
        'orbitElevation': orbitElevation,
      };

  factory SheetViewport.fromJson(Map<String, dynamic> json) => SheetViewport(
        xMm: (json['xMm'] as num?)?.toDouble() ?? 25.0,
        yMm: (json['yMm'] as num?)?.toDouble() ?? 10.0,
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 380.0,
        heightMm: (json['heightMm'] as num?)?.toDouble() ?? 220.0,
        modelCenterX: (json['modelCenterX'] as num?)?.toDouble() ?? 0.0,
        modelCenterY: (json['modelCenterY'] as num?)?.toDouble() ?? 0.0,
        modelCenterZ: (json['modelCenterZ'] as num?)?.toDouble() ?? 0.0,
        viewScale: (json['viewScale'] as num?)?.toDouble() ?? 0.02,
        autoFit: json['autoFit'] as bool? ?? true,
        visibleSystemIds: json['visibleSystemIds'] is List
            ? (json['visibleSystemIds'] as List).map((e) => e.toString()).toSet()
            : null,
        ghostInactiveSystems: json['ghostInactiveSystems'] as bool? ?? false,
        projectionType: ProjectionType.values.firstWhere(
          (e) => e.name == json['projectionType'],
          orElse: () => ProjectionType.gostFrontal45,
        ),
        orbitAzimuth: (json['orbitAzimuth'] as num?)?.toDouble() ?? (-math.pi / 4),
        orbitElevation: (json['orbitElevation'] as num?)?.toDouble() ?? (math.pi / 6),
      );

  SheetViewport copyWith({
    double? xMm,
    double? yMm,
    double? widthMm,
    double? heightMm,
    double? modelCenterX,
    double? modelCenterY,
    double? modelCenterZ,
    double? viewScale,
    bool? autoFit,
    Set<String>? visibleSystemIds,
    bool? ghostInactiveSystems,
    ProjectionType? projectionType,
    double? orbitAzimuth,
    double? orbitElevation,
  }) {
    return SheetViewport(
      xMm: xMm ?? this.xMm,
      yMm: yMm ?? this.yMm,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      modelCenterX: modelCenterX ?? this.modelCenterX,
      modelCenterY: modelCenterY ?? this.modelCenterY,
      modelCenterZ: modelCenterZ ?? this.modelCenterZ,
      viewScale: viewScale ?? this.viewScale,
      autoFit: autoFit ?? this.autoFit,
      visibleSystemIds: visibleSystemIds ?? this.visibleSystemIds,
      ghostInactiveSystems: ghostInactiveSystems ?? this.ghostInactiveSystems,
      projectionType: projectionType ?? this.projectionType,
      orbitAzimuth: orbitAzimuth ?? this.orbitAzimuth,
      orbitElevation: orbitElevation ?? this.orbitElevation,
    );
  }

  /// Масштаб видового экрана (алиас для viewScale)
  double get scale => viewScale;

  /// Координата X центра модели (алиас для modelCenterX)
  double get centerX => modelCenterX;

  /// Координата Y центра модели (алиас для modelCenterY)
  double get centerY => modelCenterY;

  /// Координата Z центра модели (алиас для modelCenterZ)
  double get centerZ => modelCenterZ;
}

/// Настройки видового экрана для обратной совместимости и быстрого создания в тестах/сервисах
class ViewportSettings extends SheetViewport {
  const ViewportSettings({
    double scale = 0.02,
    double centerX = 0.0,
    double centerY = 0.0,
    double centerZ = 0.0,
    super.xMm,
    super.yMm,
    super.widthMm,
    super.heightMm,
    super.autoFit,
    super.visibleSystemIds,
    super.ghostInactiveSystems,
    super.projectionType,
    super.orbitAzimuth,
    super.orbitElevation,
  }) : super(
          viewScale: scale,
          modelCenterX: centerX,
          modelCenterY: centerY,
          modelCenterZ: centerZ,
        );
}

/// Тип встроенной таблицы на листе
enum SheetTableType {
  /// Спецификация оборудования и материалов (СО)
  materialsSpecification,

  /// Таблица/реестр сварных стыков
  weldJointsTable,
}

/// Встроенная таблица, размещенная на листе
class SheetTableItem {
  final String id;
  final SheetTableType type;
  final double xMm;
  final double yMm;
  final double widthMm;
  final double heightMm;
  final String? templateId;
  final bool filterBySheetSystems;

  const SheetTableItem({
    required this.id,
    required this.type,
    this.xMm = 25.0,
    this.yMm = 10.0,
    this.widthMm = 185.0,
    this.heightMm = 60.0,
    this.templateId,
    this.filterBySheetSystems = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'xMm': xMm,
        'yMm': yMm,
        'widthMm': widthMm,
        'heightMm': heightMm,
        if (templateId != null) 'templateId': templateId,
        'filterBySheetSystems': filterBySheetSystems,
      };

  factory SheetTableItem.fromJson(Map<String, dynamic> json) => SheetTableItem(
        id: json['id'] as String,
        type: SheetTableType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => SheetTableType.materialsSpecification,
        ),
        xMm: (json['xMm'] as num?)?.toDouble() ?? 25.0,
        yMm: (json['yMm'] as num?)?.toDouble() ?? 10.0,
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 185.0,
        heightMm: (json['heightMm'] as num?)?.toDouble() ?? 60.0,
        templateId: json['templateId'] as String?,
        filterBySheetSystems: json['filterBySheetSystems'] as bool? ?? true,
      );
}

/// Блок технических требований (ТТ) / примечаний над штампом
class TechnicalRequirements {
  final String text;
  final double xMm;
  final double yMm;
  final double widthMm;
  final double heightMm;
  final bool hasBorder;
  final String title;

  const TechnicalRequirements({
    required this.text,
    this.xMm = 230.0,
    this.yMm = 180.0,
    this.widthMm = 185.0,
    this.heightMm = 55.0,
    this.hasBorder = false,
    this.title = 'Примечание:',
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'xMm': xMm,
        'yMm': yMm,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'hasBorder': hasBorder,
        'title': title,
      };

  factory TechnicalRequirements.fromJson(Map<String, dynamic> json) => TechnicalRequirements(
        text: json['text'] as String? ?? '',
        xMm: (json['xMm'] as num?)?.toDouble() ?? 230.0,
        yMm: (json['yMm'] as num?)?.toDouble() ?? 180.0,
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 185.0,
        heightMm: (json['heightMm'] as num?)?.toDouble() ?? 55.0,
        hasBorder: json['hasBorder'] as bool? ?? false,
        title: json['title'] as String? ?? 'Примечание:',
      );

  TechnicalRequirements copyWith({
    String? text,
    double? xMm,
    double? yMm,
    double? widthMm,
    double? heightMm,
    bool? hasBorder,
    String? title,
  }) {
    return TechnicalRequirements(
      text: text ?? this.text,
      xMm: xMm ?? this.xMm,
      yMm: yMm ?? this.yMm,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      hasBorder: hasBorder ?? this.hasBorder,
      title: title ?? this.title,
    );
  }
}

/// Динамический чертежный лист (Layout / Paper Space)
class DrawingSheet {
  final String id;
  final String name;
  final int sheetNumber;
  final SheetFormat format;
  final TitleBlockForm titleBlockForm;
  final TitleBlockData titleBlockData;
  final SheetViewport viewport;
  final List<SheetTableItem> tables;
  final TechnicalRequirements? technicalRequirements;
  final DrawingLegend? legend;

  /// Разрешенные категории выносок на листе (null = показывать все существующие)
  final Set<CalloutTargetType>? enabledCalloutTypes;

  /// Показывать ли высотные отметки на этом листе
  final bool showElevationCallouts;

  /// Группировать ли элементы одного узла в многополочные этажерки
  final bool groupMultiLevelCallouts;

  /// Автоматически объединять одинаковые элементы в вилочные выноски ("Ласточкин хвост" по ГОСТ 2.316)
  final bool mergeIdenticalCallouts;

  /// Показывать ли визуальный отладочный слой препятствий (коридоры труб, боксы деталей)
  final bool debugShowObstacles;

  /// Сохраненные именованные пресеты расстановки выносок для этого листа
  final List<SheetCalloutPreset> calloutPresets;

  /// Сохраненные именованные пресеты ракурса и масштаба для этого листа
  final List<SheetViewPreset> viewPresets;

  /// ID выносного узла (DetailNode), если этот лист представляет собой укрупненный узел.
  /// Если null — это обычный обзорный лист.
  final String? detailNodeId;

  const DrawingSheet({
    required this.id,
    required this.name,
    this.sheetNumber = 1,
    this.format = const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
    this.titleBlockForm = TitleBlockForm.form3,
    this.titleBlockData = const TitleBlockData(),
    this.viewport = const SheetViewport(),
    this.tables = const [],
    this.technicalRequirements,
    this.legend,
    this.enabledCalloutTypes,
    this.showElevationCallouts = true,
    this.groupMultiLevelCallouts = true,
    this.mergeIdenticalCallouts = true,
    this.debugShowObstacles = false,
    this.calloutPresets = const [],
    this.viewPresets = const [],
    this.detailNodeId,
  });

  /// Проверяет, должна ли отображаться данная выноска на текущем листе.
  /// При передаче [network] дополнительно проверяет фильтр видимых систем
  /// видового экрана ([viewport.visibleSystemIds]) и принадлежность выносным узлам ([detailNodeId]).
  bool isCalloutVisible(Callout callout, [PipingNetwork? network]) {
    if (callout.isHidden) {
      return false;
    }
    if (callout.elevationStyle != null && !showElevationCallouts) {
      return false;
    }
    if (enabledCalloutTypes != null && !enabledCalloutTypes!.contains(callout.targetType)) {
      return false;
    }
    // Прямая врезка (directBranch) не является фасонной деталью/элементом сети
    if (callout.targetType == CalloutTargetType.fitting && network != null) {
      final fit = network.resolveFittingById(callout.targetId);
      if (fit != null && fit.fittingType == FittingType.directBranch) {
        return false;
      }
    }

    // Фильтрация выносных узлов (DetailNode):
    // 1. На листе самого узла показываем ТОЛЬКО выноски элементов этого узла.
    // 2. На общем листе скрываем выноски элементов, которые вынесены в укрупненный узел.
    if (network != null) {
      if (detailNodeId != null) {
        final dn = network.detailNodes[detailNodeId];
        if (dn != null && !network.isTargetInDetailNode(dn, callout.targetType, callout.targetId)) {
          return false;
        }
      } else {
        if (network.isCalloutSuppressedOnOverview(callout)) {
          return false;
        }
      }
    }

    // Фильтрация по видимым системам видового экрана
    final visibleSys = viewport.visibleSystemIds;
    if (visibleSys != null && visibleSys.isNotEmpty && network != null) {
      // Оборудование и штуцеры не привязаны к конкретной системе — всегда видны
      if (callout.targetType == CalloutTargetType.equipment || callout.targetType == CalloutTargetType.nozzle) {
        return true;
      }

      // Для фитингов: проверяем, видна ли хотя бы одна подключенная труба
      if (callout.targetType == CalloutTargetType.fitting) {
        final cfValve = network.getCounterFlangeValve(callout.targetId);
        if (cfValve != null) {
          final seg = network.segments[cfValve.segmentId];
          return seg != null && visibleSys.contains(seg.systemId);
        }
        Fitting? fit = network.fittings[callout.targetId];
        if (fit == null) {
          for (final f in network.fittings.values) {
            if (f.id == callout.targetId || f.nodeId == callout.targetId) {
              fit = f;
              break;
            }
          }
        }
        final nodeId = fit?.nodeId ?? callout.targetId;
        final conn = network.getConnectedSegments(nodeId);
        if (conn.isEmpty || !conn.any((s) => visibleSys.contains(s.systemId))) {
          return false;
        }
        return true;
      }

      // Для отметок уровня (узлов): проверяем подключенные сегменты
      if (callout.targetType == CalloutTargetType.node) {
        final conn = network.getConnectedSegments(callout.targetId);
        if (conn.isEmpty || !conn.any((s) => visibleSys.contains(s.systemId))) {
          return false;
        }
        return true;
      }

      final systemId = network.getCalloutSystemId(callout.targetType, callout.targetId);
      if (systemId == null || !visibleSys.contains(systemId)) {
        return false;
      }
    }
    return true;
  }

  /// Возвращает эффективную сеть для текущего листа с учетом фильтра видимых систем
  /// видового экрана ([viewport.visibleSystemIds]), выносного узла ([detailNodeId])
  /// и фильтра выносок ([isCalloutVisible]).
  PipingNetwork getEffectiveNetwork(PipingNetwork baseNetwork) {
    final visibleSys = viewport.visibleSystemIds;
    final detailNode = detailNodeId != null ? baseNetwork.detailNodes[detailNodeId] : null;
    var net = baseNetwork;

    if (detailNode != null) {
      // Лист укрупненного узла: оставляем строго сегменты и элементы этого узла
      final visibleSegs = Map<String, PipeSegment>.fromEntries(
        baseNetwork.segments.entries.where((e) {
          if (!detailNode.segmentIds.contains(e.key)) return false;
          if (visibleSys != null && visibleSys.isNotEmpty && !visibleSys.contains(e.value.systemId)) {
            return false;
          }
          return true;
        }),
      );
      final visibleSegIds = visibleSegs.keys.toSet();
      final detailNodeIds = <String>{};
      for (final seg in visibleSegs.values) {
        detailNodeIds.add(seg.startNodeId);
        detailNodeIds.add(seg.endNodeId);
      }

      final visibleValves = Map<String, Valve>.fromEntries(
        baseNetwork.valves.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleSupports = Map<String, PipeSupport>.fromEntries(
        baseNetwork.supports.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleWelds = Map<String, WeldJoint>.fromEntries(
        baseNetwork.weldJoints.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleSpools = Map<String, PipeSpool>.fromEntries(
        baseNetwork.spools.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleFittings = Map<String, Fitting>.fromEntries(
        baseNetwork.fittings.entries.where((e) => detailNodeIds.contains(e.value.nodeId)),
      );
      final visibleDimensions = Map<String, LinearDimension>.fromEntries(
        baseNetwork.dimensions.entries.where(
          (e) => baseNetwork.isDimensionInDetailNode(detailNode, e.value),
        ),
      );

      net = baseNetwork.copyWith(
        segments: visibleSegs,
        valves: visibleValves,
        supports: visibleSupports,
        weldJoints: visibleWelds,
        spools: visibleSpools,
        fittings: visibleFittings,
        dimensions: visibleDimensions,
      );
    } else if (visibleSys != null && visibleSys.isNotEmpty) {
      final visibleSegs = Map<String, PipeSegment>.fromEntries(
        baseNetwork.segments.entries.where((e) => visibleSys.contains(e.value.systemId)),
      );
      final visibleSegIds = visibleSegs.keys.toSet();

      final visibleValves = Map<String, Valve>.fromEntries(
        baseNetwork.valves.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleSupports = Map<String, PipeSupport>.fromEntries(
        baseNetwork.supports.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleWelds = Map<String, WeldJoint>.fromEntries(
        baseNetwork.weldJoints.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleSpools = Map<String, PipeSpool>.fromEntries(
        baseNetwork.spools.entries.where((e) => visibleSegIds.contains(e.value.segmentId)),
      );
      final visibleFittings = Map<String, Fitting>.fromEntries(
        baseNetwork.fittings.entries.where((e) =>
          baseNetwork.getConnectedSegments(e.value.nodeId).any((s) => visibleSegIds.contains(s.id)),
        ),
      );
      final visibleDimensions = Map<String, LinearDimension>.fromEntries(
        baseNetwork.dimensions.entries.where((e) {
          final dim = e.value;
          // Скрываем на общем листе размеры, относящиеся к выносным узлам
          for (final dn in baseNetwork.detailNodes.values) {
            if (dn.suppressCalloutsOnOverview && baseNetwork.isDimensionInDetailNode(dn, dim)) {
              return false;
            }
          }
          if (dim.startNodeId == null && dim.endNodeId == null) return true;
          final s1 = dim.startNodeId != null ? baseNetwork.getConnectedSegments(dim.startNodeId!) : const <PipeSegment>[];
          final s2 = dim.endNodeId != null ? baseNetwork.getConnectedSegments(dim.endNodeId!) : const <PipeSegment>[];
          final allConn = [...s1, ...s2];
          if (allConn.isEmpty) return true;
          return allConn.any((s) => visibleSegIds.contains(s.id));
        }),
      );

      net = baseNetwork.copyWith(
        segments: visibleSegs,
        valves: visibleValves,
        supports: visibleSupports,
        weldJoints: visibleWelds,
        spools: visibleSpools,
        fittings: visibleFittings,
        dimensions: visibleDimensions,
      );
    } else if (baseNetwork.detailNodes.isNotEmpty) {
      // Общий лист без фильтра систем: скрываем внутренние размеры выносных узлов
      final visibleDimensions = Map<String, LinearDimension>.fromEntries(
        baseNetwork.dimensions.entries.where((e) {
          final dim = e.value;
          for (final dn in baseNetwork.detailNodes.values) {
            if (dn.suppressCalloutsOnOverview && baseNetwork.isDimensionInDetailNode(dn, dim)) {
              return false;
            }
          }
          return true;
        }),
      );
      net = baseNetwork.copyWith(dimensions: visibleDimensions);
    }

    final visibleCallouts = Map<String, Callout>.fromEntries(
      baseNetwork.callouts.entries.where((e) => isCalloutVisible(e.value, baseNetwork)),
    );

    return net.copyWith(callouts: visibleCallouts);
  }

  /// Расчет координат и габаритов видового экрана по выбранному пресету
  static SheetViewport calculatePresetViewport(
    SheetFormat fmt,
    ViewportLayoutPreset preset, {
    Set<String>? visibleSystemIds,
  }) {
    const stampWidth = 185.0;
    const stampHeight = 55.0;

    switch (preset) {
      case ViewportLayoutPreset.wideAboveStamp:
        final x = fmt.frameLeftMm + 2.0;
        final y = fmt.frameTopMm + 2.0;
        final w = fmt.printableWidthMm - 4.0;
        final h = fmt.printableHeightMm - stampHeight - 8.0;
        return SheetViewport(
          xMm: x,
          yMm: y,
          widthMm: w > 50 ? w : fmt.printableWidthMm,
          heightMm: h > 50 ? h : fmt.printableHeightMm,
          autoFit: true,
          visibleSystemIds: visibleSystemIds,
        );

      case ViewportLayoutPreset.fullSheet:
        final x = fmt.frameLeftMm + 2.0;
        final y = fmt.frameTopMm + 2.0;
        final w = fmt.printableWidthMm - 4.0;
        final h = fmt.printableHeightMm - 4.0;
        return SheetViewport(
          xMm: x,
          yMm: y,
          widthMm: w > 50 ? w : fmt.printableWidthMm,
          heightMm: h > 50 ? h : fmt.printableHeightMm,
          autoFit: true,
          visibleSystemIds: visibleSystemIds,
        );

      case ViewportLayoutPreset.leftColumn:
        final x = fmt.frameLeftMm + 2.0;
        final y = fmt.frameTopMm + 2.0;
        final w = fmt.printableWidthMm - stampWidth - 8.0;
        final h = fmt.printableHeightMm - 4.0;
        return SheetViewport(
          xMm: x,
          yMm: y,
          widthMm: w > 50 ? w : fmt.printableWidthMm,
          heightMm: h > 50 ? h : fmt.printableHeightMm,
          autoFit: true,
          visibleSystemIds: visibleSystemIds,
        );
    }
  }

  /// Расчет координат и габаритов видового экрана по выбранному пресету для текущего листа
  SheetViewport getPresetViewport(ViewportLayoutPreset preset) =>
      calculatePresetViewport(format, preset, visibleSystemIds: viewport.visibleSystemIds);

  /// Применение пресета компоновки к текущему листу с сохранением центра модели и масштаба
  DrawingSheet applyViewportPreset(ViewportLayoutPreset preset) {
    final newVp = calculatePresetViewport(format, preset, visibleSystemIds: viewport.visibleSystemIds).copyWith(
      modelCenterX: viewport.modelCenterX,
      modelCenterY: viewport.modelCenterY,
      modelCenterZ: viewport.modelCenterZ,
      viewScale: viewport.viewScale,
      autoFit: viewport.autoFit,
      ghostInactiveSystems: viewport.ghostInactiveSystems,
    );
    return copyWith(viewport: newVp);
  }

  /// Создание листа со стандартными настройками СПДС (ВЭ во всю ширину листа над штампом)
  factory DrawingSheet.createDefault({
    required String id,
    required String name,
    required int sheetNumber,
    SheetFormatType formatType = SheetFormatType.a3,
    SheetOrientation orientation = SheetOrientation.landscape,
    Set<String>? visibleSystemIds,
    String? detailNodeId,
  }) {
    final fmt = SheetFormat(type: formatType, orientation: orientation);

    return DrawingSheet(
      id: id,
      name: name,
      sheetNumber: sheetNumber,
      format: fmt,
      titleBlockForm: TitleBlockForm.form3,
      titleBlockData: TitleBlockData(
        sheetNumber: sheetNumber,
        drawingTitle: detailNodeId != null ? name : 'Исполнительная схема трубопроводов $name',
      ),
      viewport: calculatePresetViewport(
        fmt,
        ViewportLayoutPreset.wideAboveStamp,
        visibleSystemIds: visibleSystemIds,
      ),
      legend: DrawingLegend.createDefault(
        xMm: fmt.widthMm - fmt.frameRightMm - 185.0,
        yMm: fmt.heightMm - fmt.frameBottomMm - 55.0 - 55.0 - 50.0, // Над примечаниями
        widthMm: 185.0,
        heightMm: 45.0,
      ),
      detailNodeId: detailNodeId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sheetNumber': sheetNumber,
        'format': format.toJson(),
        'titleBlockForm': titleBlockForm.name,
        'titleBlockData': titleBlockData.toJson(),
        'viewport': viewport.toJson(),
        'tables': tables.map((t) => t.toJson()).toList(),
        if (technicalRequirements != null) 'technicalRequirements': technicalRequirements!.toJson(),
        if (legend != null) 'legend': legend!.toJson(),
        if (enabledCalloutTypes != null)
          'enabledCalloutTypes': enabledCalloutTypes!.map((e) => e.name).toList(),
        'showElevationCallouts': showElevationCallouts,
        'groupMultiLevelCallouts': groupMultiLevelCallouts,
        'mergeIdenticalCallouts': mergeIdenticalCallouts,
        'debugShowObstacles': debugShowObstacles,
        if (calloutPresets.isNotEmpty)
          'calloutPresets': calloutPresets.map((p) => p.toJson()).toList(),
        if (viewPresets.isNotEmpty)
          'viewPresets': viewPresets.map((p) => p.toJson()).toList(),
        if (detailNodeId != null) 'detailNodeId': detailNodeId,
      };

  factory DrawingSheet.fromJson(Map<String, dynamic> json) => DrawingSheet(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Лист',
        sheetNumber: json['sheetNumber'] as int? ?? 1,
        format: json['format'] != null
            ? SheetFormat.fromJson(json['format'] as Map<String, dynamic>)
            : const SheetFormat(),
        titleBlockForm: TitleBlockForm.values.firstWhere(
          (e) => e.name == json['titleBlockForm'],
          orElse: () => TitleBlockForm.form3,
        ),
        titleBlockData: json['titleBlockData'] != null
            ? TitleBlockData.fromJson(json['titleBlockData'] as Map<String, dynamic>)
            : const TitleBlockData(),
        viewport: json['viewport'] != null
            ? SheetViewport.fromJson(json['viewport'] as Map<String, dynamic>)
            : const SheetViewport(),
        tables: json['tables'] is List
            ? (json['tables'] as List)
                .map((e) => SheetTableItem.fromJson(e as Map<String, dynamic>))
                .toList()
            : const [],
        technicalRequirements: json['technicalRequirements'] != null
            ? TechnicalRequirements.fromJson(json['technicalRequirements'] as Map<String, dynamic>)
            : null,
        legend: json['legend'] != null
            ? DrawingLegend.fromJson(json['legend'] as Map<String, dynamic>)
            : null,
        enabledCalloutTypes: json['enabledCalloutTypes'] is List
            ? (json['enabledCalloutTypes'] as List)
                .map((e) => CalloutTargetType.values.firstWhere(
                      (t) => t.name == e.toString(),
                      orElse: () => CalloutTargetType.segment,
                    ))
                .toSet()
            : null,
        showElevationCallouts: json['showElevationCallouts'] as bool? ?? true,
        groupMultiLevelCallouts: json['groupMultiLevelCallouts'] as bool? ?? true,
        mergeIdenticalCallouts: json['mergeIdenticalCallouts'] as bool? ?? true,
        debugShowObstacles: json['debugShowObstacles'] as bool? ?? false,
        calloutPresets: json['calloutPresets'] is List
            ? (json['calloutPresets'] as List)
                .map((e) => SheetCalloutPreset.fromJson(e as Map<String, dynamic>))
                .toList()
            : const [],
        viewPresets: json['viewPresets'] is List
            ? (json['viewPresets'] as List)
                .map((e) => SheetViewPreset.fromJson(e as Map<String, dynamic>))
                .toList()
            : const [],
        detailNodeId: json['detailNodeId'] as String?,
      );

  DrawingSheet copyWith({
    String? id,
    String? name,
    int? sheetNumber,
    SheetFormat? format,
    TitleBlockForm? titleBlockForm,
    TitleBlockData? titleBlockData,
    SheetViewport? viewport,
    List<SheetTableItem>? tables,
    TechnicalRequirements? technicalRequirements,
    bool clearTechnicalRequirements = false,
    DrawingLegend? legend,
    bool clearLegend = false,
    Set<CalloutTargetType>? enabledCalloutTypes,
    bool clearEnabledCalloutTypes = false,
    bool? showElevationCallouts,
    bool? groupMultiLevelCallouts,
    bool? mergeIdenticalCallouts,
    bool? debugShowObstacles,
    List<SheetCalloutPreset>? calloutPresets,
    List<SheetViewPreset>? viewPresets,
    String? detailNodeId,
    bool clearDetailNodeId = false,
  }) {
    return DrawingSheet(
      id: id ?? this.id,
      name: name ?? this.name,
      sheetNumber: sheetNumber ?? this.sheetNumber,
      format: format ?? this.format,
      titleBlockForm: titleBlockForm ?? this.titleBlockForm,
      titleBlockData: titleBlockData ?? this.titleBlockData,
      viewport: viewport ?? this.viewport,
      tables: tables ?? this.tables,
      technicalRequirements: clearTechnicalRequirements
          ? null
          : (technicalRequirements ?? this.technicalRequirements),
      legend: clearLegend ? null : (legend ?? this.legend),
      enabledCalloutTypes: clearEnabledCalloutTypes
          ? null
          : (enabledCalloutTypes ?? this.enabledCalloutTypes),
      showElevationCallouts: showElevationCallouts ?? this.showElevationCallouts,
      groupMultiLevelCallouts: groupMultiLevelCallouts ?? this.groupMultiLevelCallouts,
      mergeIdenticalCallouts: mergeIdenticalCallouts ?? this.mergeIdenticalCallouts,
      debugShowObstacles: debugShowObstacles ?? this.debugShowObstacles,
      calloutPresets: calloutPresets ?? this.calloutPresets,
      viewPresets: viewPresets ?? this.viewPresets,
      detailNodeId: clearDetailNodeId ? null : (detailNodeId ?? this.detailNodeId),
    );
  }
}
