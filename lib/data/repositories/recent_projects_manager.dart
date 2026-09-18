import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Элемент списка недавних проектов
class RecentProjectEntry {
  final String title;
  final String filePath;
  final String projectCode;
  final DateTime lastOpened;

  RecentProjectEntry({
    required this.title,
    required this.filePath,
    this.projectCode = '',
    DateTime? lastOpened,
  }) : lastOpened = lastOpened ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'title': title,
        'filePath': filePath,
        'projectCode': projectCode,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory RecentProjectEntry.fromJson(Map<String, dynamic> json) => RecentProjectEntry(
        title: json['title'] as String? ?? 'Безымянный проект',
        filePath: json['filePath'] as String? ?? '',
        projectCode: json['projectCode'] as String? ?? '',
        lastOpened: json['lastOpened'] != null
            ? DateTime.tryParse(json['lastOpened'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

/// Менеджер хранения и ротации недавно открытых проектов (.akso)
class RecentProjectsManager {
  static const String _fileName = 'recent_projects.json';
  final Future<Directory> Function()? _getStorageDir;
  final int maxItems;

  RecentProjectsManager({
    Future<Directory> Function()? getStorageDir,
    this.maxItems = 10,
  }) : _getStorageDir = getStorageDir;

  Future<File> _getConfigFile() async {
    Directory dir;
    if (_getStorageDir != null) {
      dir = await _getStorageDir!();
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
  }

  /// Возвращает упорядоченный список недавних проектов (начиная с самых свежих)
  Future<List<RecentProjectEntry>> getRecentProjects() async {
    try {
      final file = await _getConfigFile();
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return [];
      }
      final decoded = jsonDecode(content);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .map((item) => RecentProjectEntry.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((entry) => entry.filePath.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Добавляет или обновляет проект в списке недавних
  Future<void> addRecentProject(RecentProjectEntry entry) async {
    if (entry.filePath.isEmpty) return;
    try {
      final currentList = await getRecentProjects();
      final updatedList = <RecentProjectEntry>[
        entry,
        ...currentList.where((e) => e.filePath.toLowerCase() != entry.filePath.toLowerCase()),
      ];

      if (updatedList.length > maxItems) {
        updatedList.removeRange(maxItems, updatedList.length);
      }

      await _saveList(updatedList);
    } catch (_) {}
  }

  /// Удаляет проект из списка недавних
  Future<void> removeRecentProject(String filePath) async {
    try {
      final currentList = await getRecentProjects();
      final updatedList = currentList
          .where((e) => e.filePath.toLowerCase() != filePath.toLowerCase())
          .toList();
      await _saveList(updatedList);
    } catch (_) {}
  }

  /// Очищает весь список недавних файлов
  Future<void> clearRecentProjects() async {
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _saveList(List<RecentProjectEntry> list) async {
    final file = await _getConfigFile();
    final jsonString = jsonEncode(list.map((e) => e.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
  }
}
