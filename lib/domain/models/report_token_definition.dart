import '../enums/report_type.dart';

/// Описание токена (чипа) в конструкторе отчетов
class ReportTokenDefinition {
  final String code;
  final String label;
  final String category;
  final String sampleValue;
  final Set<ReportType> appliesTo;

  const ReportTokenDefinition({
    required this.code,
    required this.label,
    required this.category,
    required this.sampleValue,
    required this.appliesTo,
  });

  /// Полный каталог всех доступных токенов
  static const List<ReportTokenDefinition> allTokens = [
    // ================= Общие параметры =================
    ReportTokenDefinition(
      code: '{num}',
      label: '№ по порядку',
      category: 'Общие',
      sampleValue: '1',
      appliesTo: {ReportType.weldJournal, ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{date}',
      label: 'Дата',
      category: 'Общие',
      sampleValue: '2026-09-20',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{system}',
      label: 'Система / Код',
      category: 'Общие',
      sampleValue: 'В1',
      appliesTo: {ReportType.weldJournal, ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{section}',
      label: 'Раздел проекта',
      category: 'Общие',
      sampleValue: '002-ТТ',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{line_node}',
      label: 'Линия / Узел',
      category: 'Общие',
      sampleValue: 'Линия 2, Т.П.2',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{notes}',
      label: 'Примечание / Результат',
      category: 'Общие',
      sampleValue: 'Годен',
      appliesTo: {ReportType.weldJournal, ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{z_coord}',
      label: 'Отметка Z (мм)',
      category: 'Геодезия',
      sampleValue: '1250',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elevation}',
      label: 'Отметка Z (м с ∇)',
      category: 'Геодезия',
      sampleValue: '+1.250',
      appliesTo: {ReportType.weldJournal},
    ),

    // ================= Сварной стык =================
    ReportTokenDefinition(
      code: '{weld_num}',
      label: 'Номер стыка',
      category: 'Сварка',
      sampleValue: '010РС',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{weld_type}',
      label: 'Тип шва по ГОСТ',
      category: 'Сварка',
      sampleValue: 'С17',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{stamp}',
      label: 'Клеймо сварщика',
      category: 'Сварка',
      sampleValue: 'ИВ-01',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{welder}',
      label: 'ФИО сварщика',
      category: 'Сварка',
      sampleValue: 'Иванов И.И.',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{brigade_stamp}',
      label: 'Бригадное клеймо',
      category: 'Сварка',
      sampleValue: 'А1',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{foreman}',
      label: 'Бригадир',
      category: 'Сварка',
      sampleValue: 'Морозов К.С.',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{welding_materials}',
      label: 'Сварочные материалы',
      category: 'Сварка',
      sampleValue: 'УОНИ 13/55',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{connection_type}',
      label: 'Тип соединения',
      category: 'Стыковка',
      sampleValue: 'труба-деталь',
      appliesTo: {ReportType.weldJournal},
    ),

    // ================= Неразрушающий контроль (НК) =================
    ReportTokenDefinition(
      code: '{ndt_method}',
      label: 'Основной метод контроля',
      category: 'Контроль',
      sampleValue: 'ВИК',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{ndt_vik}',
      label: 'Результат ВИК',
      category: 'Контроль',
      sampleValue: 'Годен',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{ndt_rk}',
      label: 'Результат РК',
      category: 'Контроль',
      sampleValue: 'Годен',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{ndt_uzk}',
      label: 'Результат УЗК',
      category: 'Контроль',
      sampleValue: 'Годен',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{report_num}',
      label: 'Номер заключения',
      category: 'Контроль',
      sampleValue: 'ПН1415-002-ТТ-010РС',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{report_date}',
      label: 'Дата заключения',
      category: 'Контроль',
      sampleValue: '2026-09-21',
      appliesTo: {ReportType.weldJournal},
    ),

    // ================= Элемент №1 (Side 1) =================
    ReportTokenDefinition(
      code: '{elem1_name}',
      label: 'Наименование эл. 1',
      category: 'Элемент №1',
      sampleValue: 'Труба',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_dn}',
      label: 'Диаметр №1',
      category: 'Элемент №1',
      sampleValue: '1220',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_wall}',
      label: 'Стенка №1 (мм)',
      category: 'Элемент №1',
      sampleValue: '13.0',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_standard}',
      label: 'НД / ГОСТ эл. 1',
      category: 'Элемент №1',
      sampleValue: 'ГОСТ 8732-78',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_steel}',
      label: 'Марка стали эл. 1',
      category: 'Элемент №1',
      sampleValue: '09Г2С',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_serial}',
      label: 'Заводской № эл. 1',
      category: 'Элемент №1',
      sampleValue: '293217.8',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_length}',
      label: 'Длина эл. 1 (мм)',
      category: 'Элемент №1',
      sampleValue: '2060',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_manufacturer}',
      label: 'Завод изготовитель эл. 1',
      category: 'Элемент №1',
      sampleValue: 'ПАО Северсталь',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem1_tag}',
      label: 'Маркировка на схеме эл. 1',
      category: 'Элемент №1',
      sampleValue: 'К-1',
      appliesTo: {ReportType.weldJournal},
    ),

    // ================= Элемент №2 (Side 2) =================
    ReportTokenDefinition(
      code: '{elem2_name}',
      label: 'Наименование эл. 2',
      category: 'Элемент №2',
      sampleValue: 'Тройник',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_dn}',
      label: 'Диаметр №2',
      category: 'Элемент №2',
      sampleValue: '1220',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_wall}',
      label: 'Стенка №2 (мм)',
      category: 'Элемент №2',
      sampleValue: '16.0',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_standard}',
      label: 'НД / ГОСТ эл. 2',
      category: 'Элемент №2',
      sampleValue: 'ГОСТ 17376-2001',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_steel}',
      label: 'Марка стали эл. 2',
      category: 'Элемент №2',
      sampleValue: '13К56',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_serial}',
      label: 'Заводской № эл. 2',
      category: 'Элемент №2',
      sampleValue: '16234-24',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_length}',
      label: 'Длина / габарит эл. 2',
      category: 'Элемент №2',
      sampleValue: '2000х246',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_manufacturer}',
      label: 'Завод изготовитель эл. 2',
      category: 'Элемент №2',
      sampleValue: 'ООО ТМК',
      appliesTo: {ReportType.weldJournal},
    ),
    ReportTokenDefinition(
      code: '{elem2_tag}',
      label: 'Маркировка на схеме эл. 2',
      category: 'Элемент №2',
      sampleValue: 'ТР-1',
      appliesTo: {ReportType.weldJournal},
    ),

    // ================= Спецификация оборудования и материалов (СО) =================
    ReportTokenDefinition(
      code: '{pos}',
      label: 'Позиция',
      category: 'Спецификация',
      sampleValue: '1',
      appliesTo: {ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{category}',
      label: 'Раздел спецификации',
      category: 'Спецификация',
      sampleValue: 'Трубы',
      appliesTo: {ReportType.materialsSpecification},
    ),
    ReportTokenDefinition(
      code: '{name}',
      label: 'Наименование и характеристика',
      category: 'Спецификация',
      sampleValue: 'Труба стальная 108х4.0 ГОСТ 8732-78',
      appliesTo: {ReportType.materialsSpecification},
    ),
    ReportTokenDefinition(
      code: '{type_mark}',
      label: 'Тип, марка',
      category: 'Спецификация',
      sampleValue: '30с41нж',
      appliesTo: {ReportType.materialsSpecification},
    ),
    ReportTokenDefinition(
      code: '{standard}',
      label: 'ГОСТ / ТУ / Опросный лист',
      category: 'Спецификация',
      sampleValue: 'ГОСТ 8732-78',
      appliesTo: {ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{material}',
      label: 'Материал / Марка стали',
      category: 'Спецификация',
      sampleValue: 'Сталь 20',
      appliesTo: {ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{dn}',
      label: 'Диаметр DN',
      category: 'Спецификация',
      sampleValue: '100',
      appliesTo: {ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{wall}',
      label: 'Стенка S (мм)',
      category: 'Спецификация',
      sampleValue: '4.0',
      appliesTo: {ReportType.materialsSpecification, ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{qty}',
      label: 'Количество',
      category: 'Спецификация',
      sampleValue: '12.50',
      appliesTo: {ReportType.materialsSpecification},
    ),
    ReportTokenDefinition(
      code: '{unit}',
      label: 'Ед. измерения',
      category: 'Спецификация',
      sampleValue: 'м',
      appliesTo: {ReportType.materialsSpecification},
    ),
    ReportTokenDefinition(
      code: '{mass_kg}',
      label: 'Масса ед., кг',
      category: 'Спецификация',
      sampleValue: '10.25',
      appliesTo: {ReportType.materialsSpecification},
    ),

    // ================= Ведомость заготовок / катушек =================
    ReportTokenDefinition(
      code: '{spool_num}',
      label: 'Номер заготовки/катушки',
      category: 'Заготовки',
      sampleValue: 'К-1',
      appliesTo: {ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{cut_length}',
      label: 'Длина реза (мм)',
      category: 'Заготовки',
      sampleValue: '1250',
      appliesTo: {ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{theoretical_length}',
      label: 'Осевая длина (мм)',
      category: 'Заготовки',
      sampleValue: '1400',
      appliesTo: {ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{start_element}',
      label: 'Начальное сопряжение',
      category: 'Заготовки',
      sampleValue: 'Отвод 90°',
      appliesTo: {ReportType.spoolsList},
    ),
    ReportTokenDefinition(
      code: '{end_element}',
      label: 'Конечное сопряжение',
      category: 'Заготовки',
      sampleValue: 'Тройник',
      appliesTo: {ReportType.spoolsList},
    ),
  ];

  /// Получение токенов для конкретного типа отчета
  static List<ReportTokenDefinition> getTokensForType(ReportType type) {
    return allTokens.where((t) => t.appliesTo.contains(type)).toList();
  }

  /// Группировка токенов по категориям для удобства отображения в UI
  static Map<String, List<ReportTokenDefinition>> getGroupedTokensForType(ReportType type) {
    final tokens = getTokensForType(type);
    final grouped = <String, List<ReportTokenDefinition>>{};
    for (final t in tokens) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }
    return grouped;
  }
}
