import 'package:flutter/foundation.dart';

/// Тип элемента условного обозначения
enum LegendItemType {
  /// Линейный размер (проектный и фактический)
  dimension,

  /// Отметка уровня (действительная отметка)
  elevation,

  /// Трубопровод инженерной системы (например, В1 ⌀32)
  pipeSystem,

  /// Сварной стык по ГОСТ 16037-80
  weldJoint,

  /// Запорная арматура (вентиль, задвижка)
  valve,

  /// Фасонный элемент (отвод, тройник)
  fitting,

  /// Пользовательский пункт
  custom,
}

/// Отдельный пункт условных обозначений
@immutable
class LegendItem {
  final String id;
  final LegendItemType type;
  final String label;
  final String? subLabel;
  final bool isVisible;
  final String? systemCode;
  final String? systemId;
  final int? dn;

  const LegendItem({
    required this.id,
    required this.type,
    required this.label,
    this.subLabel,
    this.isVisible = true,
    this.systemCode,
    this.systemId,
    this.dn,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'label': label,
        if (subLabel != null) 'subLabel': subLabel,
        'isVisible': isVisible,
        if (systemCode != null) 'systemCode': systemCode,
        if (systemId != null) 'systemId': systemId,
        if (dn != null) 'dn': dn,
      };

  factory LegendItem.fromJson(Map<String, dynamic> json) => LegendItem(
        id: json['id'] as String? ?? 'leg_${DateTime.now().millisecondsSinceEpoch}',
        type: LegendItemType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => LegendItemType.custom,
        ),
        label: json['label'] as String? ?? '',
        subLabel: json['subLabel'] as String?,
        isVisible: json['isVisible'] as bool? ?? true,
        systemCode: json['systemCode'] as String?,
        systemId: json['systemId'] as String?,
        dn: json['dn'] as int?,
      );

  LegendItem copyWith({
    String? id,
    LegendItemType? type,
    String? label,
    String? subLabel,
    bool? isVisible,
    String? systemCode,
    String? systemId,
    int? dn,
  }) {
    return LegendItem(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      subLabel: subLabel ?? this.subLabel,
      isVisible: isVisible ?? this.isVisible,
      systemCode: systemCode ?? this.systemCode,
      systemId: systemId ?? this.systemId,
      dn: dn ?? this.dn,
    );
  }
}

/// Блок «Условные обозначения» на чертежном листе оформления
@immutable
class DrawingLegend {
  final bool isVisible;
  final double xMm;
  final double yMm;
  final double widthMm;
  final double heightMm;
  final bool hasBorder;
  final String title;
  final List<LegendItem> items;

  const DrawingLegend({
    this.isVisible = true,
    this.xMm = 230.0,
    this.yMm = 125.0,
    this.widthMm = 185.0,
    this.heightMm = 45.0,
    this.hasBorder = false,
    this.title = 'Условные обозначения:',
    this.items = const [],
  });

  Map<String, dynamic> toJson() => {
        'isVisible': isVisible,
        'xMm': xMm,
        'yMm': yMm,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'hasBorder': hasBorder,
        'title': title,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory DrawingLegend.fromJson(Map<String, dynamic> json) => DrawingLegend(
        isVisible: json['isVisible'] as bool? ?? true,
        xMm: (json['xMm'] as num?)?.toDouble() ?? 230.0,
        yMm: (json['yMm'] as num?)?.toDouble() ?? 125.0,
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 185.0,
        heightMm: (json['heightMm'] as num?)?.toDouble() ?? 45.0,
        hasBorder: json['hasBorder'] as bool? ?? false,
        title: json['title'] as String? ?? 'Условные обозначения:',
        items: (json['items'] as List?)
                ?.map((e) => LegendItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );

  DrawingLegend copyWith({
    bool? isVisible,
    double? xMm,
    double? yMm,
    double? widthMm,
    double? heightMm,
    bool? hasBorder,
    String? title,
    List<LegendItem>? items,
  }) {
    return DrawingLegend(
      isVisible: isVisible ?? this.isVisible,
      xMm: xMm ?? this.xMm,
      yMm: yMm ?? this.yMm,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      hasBorder: hasBorder ?? this.hasBorder,
      title: title ?? this.title,
      items: items ?? this.items,
    );
  }

  /// Стандартный генератор условных обозначений по умолчанию для схем
  static DrawingLegend createDefault({
    double xMm = 230.0,
    double yMm = 125.0,
    double widthMm = 185.0,
    double heightMm = 45.0,
  }) {
    return DrawingLegend(
      isVisible: true,
      xMm: xMm,
      yMm: yMm,
      widthMm: widthMm,
      heightMm: heightMm,
      hasBorder: false,
      title: 'Условные обозначения:',
      items: const [
        LegendItem(
          id: 'leg_dim',
          type: LegendItemType.dimension,
          label: '- проектный размер, мм',
          subLabel: '- фактический размер, мм',
        ),
        LegendItem(
          id: 'leg_elev',
          type: LegendItemType.elevation,
          label: '- действительная отметка',
        ),
        LegendItem(
          id: 'leg_weld',
          type: LegendItemType.weldJoint,
          label: '- сварное соединение по ГОСТ 16037-80',
        ),
        LegendItem(
          id: 'leg_pipe',
          type: LegendItemType.pipeSystem,
          label: '- трубопровод проектный',
          systemCode: 'В1',
        ),
      ],
    );
  }
}
