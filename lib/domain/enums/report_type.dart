import 'package:flutter/material.dart';

/// Тип отчетного документа / ведомости
enum ReportType {
  /// Сварочный журнал / исполнительный реестр стыков
  weldJournal(
    displayName: 'Сварочный журнал',
    defaultFileName: 'weld_journal',
    icon: Icons.assignment_outlined,
  ),

  /// Спецификация оборудования, изделий и материалов (СО по ГОСТ 21.110-2013)
  materialsSpecification(
    displayName: 'Спецификация оборудования и материалов',
    defaultFileName: 'specification',
    icon: Icons.list_alt_outlined,
  ),

  /// Ведомость трубных заготовок / катушек
  spoolsList(
    displayName: 'Ведомость трубных заготовок',
    defaultFileName: 'spools_cut_list',
    icon: Icons.straighten_outlined,
  );

  final String displayName;
  final String defaultFileName;
  final IconData icon;

  const ReportType({
    required this.displayName,
    required this.defaultFileName,
    required this.icon,
  });
}
