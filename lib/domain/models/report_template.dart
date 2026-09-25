import 'package:flutter/material.dart';
import '../enums/report_type.dart';

/// Описание одного столбца отчета или ведомости
class ReportColumn {
  final String id;
  final String header;
  final String template;
  final String? groupHeader;
  final double width;
  final bool isNumeric;
  final TextAlign alignment;

  const ReportColumn({
    required this.id,
    required this.header,
    required this.template,
    this.groupHeader,
    this.width = 120.0,
    this.isNumeric = false,
    this.alignment = TextAlign.left,
  });

  ReportColumn copyWith({
    String? id,
    String? header,
    String? template,
    String? groupHeader,
    bool clearGroupHeader = false,
    double? width,
    bool? isNumeric,
    TextAlign? alignment,
  }) {
    return ReportColumn(
      id: id ?? this.id,
      header: header ?? this.header,
      template: template ?? this.template,
      groupHeader: clearGroupHeader ? null : (groupHeader ?? this.groupHeader),
      width: width ?? this.width,
      isNumeric: isNumeric ?? this.isNumeric,
      alignment: alignment ?? this.alignment,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'header': header,
        'template': template,
        if (groupHeader != null) 'groupHeader': groupHeader,
        'width': width,
        'isNumeric': isNumeric,
        'alignment': alignment.index,
      };

  factory ReportColumn.fromJson(Map<String, dynamic> json) => ReportColumn(
        id: json['id'] as String,
        header: json['header'] as String,
        template: json['template'] as String,
        groupHeader: json['groupHeader'] as String?,
        width: (json['width'] as num?)?.toDouble() ?? 120.0,
        isNumeric: json['isNumeric'] as bool? ?? false,
        alignment: TextAlign.values[json['alignment'] as int? ?? 0],
      );
}

/// Настраиваемый шаблон отчета (Сварочный журнал, Спецификация, Ведомость заготовок)
class ReportTemplate {
  final String id;
  final String name;
  final ReportType type;
  final List<ReportColumn> columns;
  final bool isBuiltIn;
  final String? headerNote;

  const ReportTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.columns,
    this.isBuiltIn = false,
    this.headerNote,
  });

  ReportTemplate copyWith({
    String? id,
    String? name,
    ReportType? type,
    List<ReportColumn>? columns,
    bool? isBuiltIn,
    String? headerNote,
    bool clearHeaderNote = false,
  }) {
    return ReportTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      columns: columns ?? this.columns,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      headerNote: clearHeaderNote ? null : (headerNote ?? this.headerNote),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.index,
        'isBuiltIn': isBuiltIn,
        if (headerNote != null) 'headerNote': headerNote,
        'columns': columns.map((c) => c.toJson()).toList(),
      };

  factory ReportTemplate.fromJson(Map<String, dynamic> json) => ReportTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        type: ReportType.values[json['type'] as int? ?? 0],
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
        headerNote: json['headerNote'] as String?,
        columns: (json['columns'] as List<dynamic>?)
                ?.map((c) => ReportColumn.fromJson(Map<String, dynamic>.from(c as Map)))
                .toList() ??
            const [],
      );

  // ==========================================
  // Предустановленные встроенные шаблоны
  // ==========================================

  /// Реестр стыков Транснефти (по образцу СП14.15)
  static final ReportTemplate defaultWeldJournalTransneftTemplate = ReportTemplate(
    id: 'weld_journal_transneft',
    name: 'Реестр стыков Транснефть (СП14/15)',
    type: ReportType.weldJournal,
    isBuiltIn: true,
    headerNote: 'Реестр стыков по объекту строительства',
    columns: const [
      ReportColumn(id: 'col_num', header: '№', template: '{num}', groupHeader: 'Общая', width: 50, isNumeric: true, alignment: TextAlign.center),
      ReportColumn(id: 'col_date', header: 'Дата сварки', template: '{date}', groupHeader: 'Общая', width: 100, alignment: TextAlign.center),
      ReportColumn(id: 'col_weld_num', header: 'Номер стыка', template: '{weld_num}', groupHeader: 'Общая', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'col_section', header: 'Раздел', template: '{section}', groupHeader: 'Общая', width: 100, alignment: TextAlign.center),
      ReportColumn(id: 'col_line', header: 'Линия/узел', template: '{line_node}', groupHeader: 'Общая', width: 140),
      
      // Элемент №1
      ReportColumn(id: 'col_e1_name', header: 'Элемент (наименование) №1', template: '{elem1_name}', groupHeader: 'Элемент №1', width: 130),
      ReportColumn(id: 'col_e1_dn', header: 'Диаметр №1', template: '{elem1_dn}', groupHeader: 'Элемент №1', width: 90, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'col_e1_wall', header: 'Толщина стенки №1', template: '{elem1_wall}', groupHeader: 'Элемент №1', width: 90, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'col_e1_std', header: 'НД Элемент №1', template: '{elem1_standard}', groupHeader: 'Элемент №1', width: 150),
      ReportColumn(id: 'col_e1_steel', header: 'Марка стали №1', template: '{elem1_steel}', groupHeader: 'Элемент №1', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'col_e1_serial', header: 'Зв.№ элемента №1', template: '{elem1_serial}', groupHeader: 'Элемент №1', width: 110),
      ReportColumn(id: 'col_e1_len', header: 'Длина эл. №1', template: '{elem1_length}', groupHeader: 'Элемент №1', width: 90, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'col_e1_manuf', header: 'Завод изготовитель №1', template: '{elem1_manufacturer}', groupHeader: 'Элемент №1', width: 140),

      // Элемент №2
      ReportColumn(id: 'col_e2_name', header: 'Элемент (наименование) №2', template: '{elem2_name}', groupHeader: 'Элемент №2', width: 130),
      ReportColumn(id: 'col_e2_dn', header: 'Диаметр №2', template: '{elem2_dn}', groupHeader: 'Элемент №2', width: 90, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'col_e2_wall', header: 'Толщина стенки №2', template: '{elem2_wall}', groupHeader: 'Элемент №2', width: 90, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'col_e2_std', header: 'НД Элемент №2', template: '{elem2_standard}', groupHeader: 'Элемент №2', width: 150),
      ReportColumn(id: 'col_e2_steel', header: 'Марка стали №2', template: '{elem2_steel}', groupHeader: 'Элемент №2', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'col_e2_serial', header: 'Зв.№ элемента №2', template: '{elem2_serial}', groupHeader: 'Элемент №2', width: 110),
      ReportColumn(id: 'col_e2_len', header: 'Длина эл. №2', template: '{elem2_length}', groupHeader: 'Элемент №2', width: 90, alignment: TextAlign.right),
      ReportColumn(id: 'col_e2_manuf', header: 'Завод изготовитель №2', template: '{elem2_manufacturer}', groupHeader: 'Элемент №2', width: 140),

      // Сварочные материалы
      ReportColumn(id: 'col_mat', header: 'Сварочные материалы', template: '{welding_materials}', groupHeader: 'Свар. Материалы', width: 150),

      // Персонал
      ReportColumn(id: 'col_welder', header: 'Сварщик', template: '{welder}', groupHeader: 'Люди', width: 130),
      ReportColumn(id: 'col_stamp', header: 'Клеймо', template: '{stamp}', groupHeader: 'Люди', width: 80, alignment: TextAlign.center),

      // Неразрушающий контроль
      ReportColumn(id: 'col_vik', header: 'ВИК', template: '{ndt_vik}', groupHeader: 'Заключения', width: 75, alignment: TextAlign.center),
      ReportColumn(id: 'col_rk', header: 'РК', template: '{ndt_rk}', groupHeader: 'Заключения', width: 75, alignment: TextAlign.center),
      ReportColumn(id: 'col_uzk', header: 'УЗК', template: '{ndt_uzk}', groupHeader: 'Заключения', width: 75, alignment: TextAlign.center),
      ReportColumn(id: 'col_rep_num', header: 'Заключение №', template: '{report_num}', groupHeader: 'Заключения', width: 140),
      ReportColumn(id: 'col_rep_date', header: 'Дата заключений', template: '{report_date}', groupHeader: 'Заключения', width: 110, alignment: TextAlign.center),

      // Топология и схема
      ReportColumn(id: 'col_tag1', header: 'Маркировка на схеме эл №1', template: '{elem1_tag}', groupHeader: 'Схема', width: 140, alignment: TextAlign.center),
      ReportColumn(id: 'col_tag2', header: 'Маркировка на схеме эл №2', template: '{elem2_tag}', groupHeader: 'Схема', width: 140, alignment: TextAlign.center),
      ReportColumn(id: 'col_elev', header: 'Отметка проектная стыка', template: '{z_coord}', groupHeader: 'Геодезия', width: 130, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'col_conn', header: 'Тип соединения', template: '{connection_type}', groupHeader: 'Стыковка', width: 130, alignment: TextAlign.center),
    ],
  );

  /// Стандартный сварочный журнал СП 73.13330 (СПДС)
  static final ReportTemplate defaultWeldJournalGostTemplate = ReportTemplate(
    id: 'weld_journal_gost_spds',
    name: 'Сварочный журнал СП 73.13330 (СПДС)',
    type: ReportType.weldJournal,
    isBuiltIn: true,
    columns: const [
      ReportColumn(id: 'g_num', header: '№ шва', template: '{num}', width: 60, isNumeric: true, alignment: TextAlign.center),
      ReportColumn(id: 'g_seg', header: 'Участок / Линия', template: '{line_node}', width: 130),
      ReportColumn(id: 'g_weld_num', header: 'Номер стыка', template: '{weld_num}', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'g_dn', header: 'Диаметр DN', template: 'Ду{elem1_dn}', width: 100, alignment: TextAlign.center),
      ReportColumn(id: 'g_wall', header: 'Стенка S (мм)', template: '{elem1_wall}', width: 100, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'g_steel', header: 'Марка стали', template: '{elem1_steel}', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'g_mat', header: 'Сварочные материалы', template: '{welding_materials}', width: 150),
      ReportColumn(id: 'g_type', header: 'Тип шва по ГОСТ', template: '{weld_type}', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'g_stamp', header: 'Клеймо', template: '{stamp}', width: 90, alignment: TextAlign.center),
      ReportColumn(id: 'g_method', header: 'Метод контроля', template: '{ndt_method}', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'g_date', header: 'Дата сварки', template: '{date}', width: 100, alignment: TextAlign.center),
      ReportColumn(id: 'g_res', header: 'Результат контроля', template: '{notes}', width: 130),
    ],
  );

  /// Спецификация оборудования, изделий и материалов ГОСТ 21.110-2013 (Форма 1)
  static final ReportTemplate defaultMtoGostTemplate = ReportTemplate(
    id: 'mto_gost_21_110',
    name: 'Спецификация СО (ГОСТ 21.110-2013)',
    type: ReportType.materialsSpecification,
    isBuiltIn: true,
    columns: const [
      ReportColumn(id: 'm_pos', header: 'Поз.', template: '{pos}', width: 60, isNumeric: true, alignment: TextAlign.center),
      ReportColumn(id: 'm_name', header: 'Наименование и техническая характеристика', template: '{name}', width: 300),
      ReportColumn(id: 'm_mark', header: 'Тип, марка', template: '{type_mark}', width: 120, alignment: TextAlign.center),
      ReportColumn(id: 'm_std', header: 'ГОСТ / ТУ', template: '{standard}', width: 140),
      ReportColumn(id: 'm_mat', header: 'Материал', template: '{material}', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 'm_qty', header: 'Кол-во', template: '{qty}', width: 80, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'm_unit', header: 'Ед. изм.', template: '{unit}', width: 70, alignment: TextAlign.center),
      ReportColumn(id: 'm_mass', header: 'Масса ед., кг', template: '{mass_kg}', width: 90, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 'm_note', header: 'Примечание', template: '{notes}', width: 160),
    ],
  );

  /// Ведомость трубных заготовок / катушек
  static final ReportTemplate defaultSpoolsCutListTemplate = ReportTemplate(
    id: 'spools_cut_list',
    name: 'Ведомость заготовок и длин реза',
    type: ReportType.spoolsList,
    isBuiltIn: true,
    columns: const [
      ReportColumn(id: 's_pos', header: '№ катушки', template: '{spool_num}', width: 90, alignment: TextAlign.center),
      ReportColumn(id: 's_qty', header: 'Кол-во', template: '{qty}', width: 70, isNumeric: true, alignment: TextAlign.center),
      ReportColumn(id: 's_sys', header: 'Система / Линия', template: '{system}', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 's_dn', header: 'Диаметр DN', template: 'Ду{dn}', width: 90, alignment: TextAlign.center),
      ReportColumn(id: 's_wall', header: 'Стенка S (мм)', template: '{wall}', width: 100, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 's_cut', header: 'Длина реза (мм)', template: '{cut_length}', width: 120, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 's_total_cut', header: 'Общая длина (мм)', template: '{total_cut_length}', width: 120, isNumeric: true, alignment: TextAlign.right),
      ReportColumn(id: 's_elem1', header: 'Сопряжение 1', template: '{start_element}', width: 130),
      ReportColumn(id: 's_elem2', header: 'Сопряжение 2', template: '{end_element}', width: 130),
      ReportColumn(id: 's_mat', header: 'Марка стали', template: '{material}', width: 110, alignment: TextAlign.center),
      ReportColumn(id: 's_note', header: 'Примечание', template: '{notes}', width: 120),
    ],
  );

  /// Все встроенные шаблоны
  static List<ReportTemplate> get defaultTemplates => [
        defaultWeldJournalTransneftTemplate,
        defaultWeldJournalGostTemplate,
        defaultMtoGostTemplate,
        defaultSpoolsCutListTemplate,
      ];
}
