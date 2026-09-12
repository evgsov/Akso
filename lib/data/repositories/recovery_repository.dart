import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/project_model.dart';

class RecoveryRepository {
  Future<File?> _getRecoveryFile() async {
    if (kIsWeb) return null;
    try {
      final directory = await getTemporaryDirectory();
      return File('${directory.path}/akso_recovery.json');
    } catch (e) {
      debugPrint('Error getting temporary directory: $e');
      return null;
    }
  }

  Future<void> saveRecovery(ProjectModel project) async {
    if (kIsWeb) return;
    try {
      final file = await _getRecoveryFile();
      if (file != null) {
        final jsonString = jsonEncode(project.toJson());
        await file.writeAsString(jsonString);
      }
    } catch (e) {
      debugPrint('Error saving recovery: $e');
    }
  }

  Future<ProjectModel?> loadRecovery() async {
    if (kIsWeb) return null;
    try {
      final file = await _getRecoveryFile();
      if (file != null && await file.exists()) {
        final jsonString = await file.readAsString();
        final jsonMap = jsonDecode(jsonString);
        return ProjectModel.fromJson(jsonMap);
      }
    } catch (e) {
      debugPrint('Error loading recovery: $e');
    }
    return null;
  }
}
