import '../enums/sheet_format_type.dart';
import '../enums/viewport_layout_preset.dart';
import 'callout.dart';
import 'drawing_legend.dart';
import 'sheet_format.dart';
import 'title_block_data.dart';

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
    );
  }
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
  final String? templateId;
  final bool filterBySheetSystems;

  const SheetTableItem({
    required this.id,
    required this.type,
    this.xMm = 25.0,
    this.yMm = 10.0,
    this.widthMm = 185.0,
    this.templateId,
    this.filterBySheetSystems = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'xMm': xMm,
        'yMm': yMm,
        'widthMm': widthMm,
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

  const DrawingSheet({
    required this.id,
    required this.name,
    required this.sheetNumber,
    this.format = const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
    this.titleBlockForm = TitleBlockForm.form3,
    this.titleBlockData = const TitleBlockData(),
    this.viewport = const SheetViewport(),
    this.tables = const [],
    this.technicalRequirements,
    this.legend,
    this.enabledCalloutTypes,
    this.showElevationCallouts = true,
  });

  /// Проверяет, должна ли отображаться данная выноска на текущем листе
  bool isCalloutVisible(Callout callout) {
    if (callout.elevationStyle != null && !showElevationCallouts) {
      return false;
    }
    if (enabledCalloutTypes != null && !enabledCalloutTypes!.contains(callout.targetType)) {
      return false;
    }
    return true;
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
        drawingTitle: 'Исполнительная схема трубопроводов $name',
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
    );
  }
}
