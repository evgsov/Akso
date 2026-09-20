import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/enums/report_type.dart';
import '../../domain/models/project_model.dart';
import '../../domain/models/report_template.dart';

/// Репозиторий хранения и слияния шаблонов отчетов (встроенные + проект + локальный кэш)
class ReportTemplateRepository {
  static const String _fileName = 'report_templates.json';
  final Future<Directory> Function()? _getStorageDir;

  ReportTemplateRepository({
    Future<Directory> Function()? getStorageDir,
  }) : _getStorageDir = getStorageDir;

  Future<File?> _getConfigFile() async {
    if (kIsWeb) return null;
    try {
      Directory dir;
      final getDir = _getStorageDir;
      if (getDir != null) {
        dir = await getDir();
      } else {
        try {
          dir = await getApplicationSupportDirectory();
        } catch (_) {
          dir = await getApplicationDocumentsDirectory();
        }
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {
      return null;
    }
  }

  /// Загрузка глобальных пользовательских шаблонов из локального кэша устройства
  Future<List<ReportTemplate>> getGlobalTemplates() async {
    final file = await _getConfigFile();
    if (file == null || !await file.exists()) {
      return [];
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final decoded = jsonDecode(content);
      if (decoded is! List) return [];

      return decoded
          .map((item) => ReportTemplate.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Получение всех шаблонов для конкретного типа отчета с объединением:
  /// 1. Встроенные системные (Built-in)
  /// 2. Локальные пользовательские (Global Cache)
  /// 3. Шаблоны текущего проекта (Project-specific)
  Future<List<ReportTemplate>> getTemplatesForType(
    ReportType type, {
    ProjectModel? project,
  }) async {
    final merged = <String, ReportTemplate>{};

    // 1. Встроенные
    for (final t in ReportTemplate.defaultTemplates) {
      if (t.type == type) {
        merged[t.id] = t;
      }
    }

    // 2. Глобальные
    final globalTemplates = await getGlobalTemplates();
    for (final t in globalTemplates) {
      if (t.type == type) {
        merged[t.id] = t;
      }
    }

    // 3. Шаблоны проекта (имеют наивысший приоритет)
    if (project?.reportTemplates != null) {
      for (final t in project!.reportTemplates!.values) {
        if (t.type == type) {
          merged[t.id] = t;
        }
      }
    }

    return merged.values.toList();
  }

  /// Сохранение пользовательского шаблона
  Future<void> saveTemplate(
    ReportTemplate template, {
    ProjectModel? project,
    bool saveGlobally = true,
  }) async {
    if (saveGlobally) {
      final file = await _getConfigFile();
      if (file != null) {
        final current = await getGlobalTemplates();
        final updated = <ReportTemplate>[
          template,
          ...current.where((t) => t.id != template.id),
        ];
        final jsonStr = jsonEncode(updated.map((t) => t.toJson()).toList());
        await file.writeAsString(jsonStr, flush: true);
      }
    }
  }

  /// Удаление пользовательского шаблона
  Future<void> deleteTemplate(
    String templateId, {
    ProjectModel? project,
    bool deleteGlobally = true,
  }) async {
    // Встроенные шаблоны удалять нельзя
    if (ReportTemplate.defaultTemplates.any((t) => t.id == templateId)) {
      return;
    }

    if (deleteGlobally) {
      final file = await _getConfigFile();
      if (file != null && await file.exists()) {
        final current = await getGlobalTemplates();
        final updated = current.where((t) => t.id != templateId).toList();
        final jsonStr = jsonEncode(updated.map((t) => t.toJson()).toList());
        await file.writeAsString(jsonStr, flush: true);
      }
    }
  }
}
