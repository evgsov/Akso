import '../enums/sheet_format_type.dart';
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

/// Блок технических требований (ТТ) над штампом
class TechnicalRequirements {
  final String text;
  final double xMm;
  final double yMm;
  final double widthMm;

  const TechnicalRequirements({
    required this.text,
    this.xMm = 230.0,
    this.yMm = 180.0,
    this.widthMm = 185.0,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'xMm': xMm,
        'yMm': yMm,
        'widthMm': widthMm,
      };

  factory TechnicalRequirements.fromJson(Map<String, dynamic> json) => TechnicalRequirements(
        text: json['text'] as String? ?? '',
        xMm: (json['xMm'] as num?)?.toDouble() ?? 230.0,
        yMm: (json['yMm'] as num?)?.toDouble() ?? 180.0,
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 185.0,
      );

  TechnicalRequirements copyWith({
    String? text,
    double? xMm,
    double? yMm,
    double? widthMm,
  }) {
    return TechnicalRequirements(
      text: text ?? this.text,
      xMm: xMm ?? this.xMm,
      yMm: yMm ?? this.yMm,
      widthMm: widthMm ?? this.widthMm,
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
  });

  /// Создание листа со стандартными настройками СПДС
  factory DrawingSheet.createDefault({
    required String id,
    required String name,
    required int sheetNumber,
    SheetFormatType formatType = SheetFormatType.a3,
    SheetOrientation orientation = SheetOrientation.landscape,
    Set<String>? visibleSystemIds,
  }) {
    final fmt = SheetFormat(type: formatType, orientation: orientation);
    final stampWidth = 185.0;
    final stampHeight = 55.0;

    // Видовой экран по умолчанию занимает свободную область слева от штампа
    final vpWidth = fmt.printableWidthMm - (fmt.widthMm > 300 ? stampWidth + 10.0 : 0.0);
    final vpHeight = fmt.printableHeightMm - 10.0;

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
      viewport: SheetViewport(
        xMm: fmt.frameLeftMm + 5.0,
        yMm: fmt.frameTopMm + 5.0,
        widthMm: vpWidth > 100 ? vpWidth : fmt.printableWidthMm,
        heightMm: vpHeight > 100 ? vpHeight : fmt.printableHeightMm - stampHeight - 10.0,
        autoFit: true,
        visibleSystemIds: visibleSystemIds,
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
    );
  }
}
