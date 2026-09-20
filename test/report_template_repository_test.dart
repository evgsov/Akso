import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/repositories/report_template_repository.dart';
import 'package:akso/domain/enums/report_type.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/domain/models/report_template.dart';

void main() {
  group('ProjectModel ReportTemplates serialization tests', () {
    test('ProjectModel serializes and deserializes reportTemplates', () {
      const customCol = ReportColumn(id: 'c1', header: 'Стык', template: '{weld_num}');
      const customTemplate = ReportTemplate(
        id: 'user_weld_1',
        name: 'Пользовательский журнал',
        type: ReportType.weldJournal,
        columns: [customCol],
      );

      final project = ProjectModel(
        id: 'p1',
        title: 'Тестовый проект',
        reportTemplates: {
          customTemplate.id: customTemplate,
        },
      );

      final json = project.toJson();
      final fromJson = ProjectModel.fromJson(json);

      expect(fromJson.reportTemplates, isNotNull);
      expect(fromJson.reportTemplates!.containsKey('user_weld_1'), true);
      expect(fromJson.reportTemplates!['user_weld_1']!.name, 'Пользовательский журнал');
      expect(fromJson.reportTemplates!['user_weld_1']!.columns.length, 1);
    });
  });

  group('ReportTemplateRepository tests', () {
    late Directory tempDir;
    late ReportTemplateRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('akso_templates_test_');
      repository = ReportTemplateRepository(getStorageDir: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns built-in templates by default', () async {
      final templates = await repository.getTemplatesForType(ReportType.weldJournal);
      expect(templates.any((t) => t.id == 'weld_journal_transneft'), true);
      expect(templates.any((t) => t.id == 'weld_journal_gost_spds'), true);
    });

    test('saves and loads custom template globally', () async {
      const template = ReportTemplate(
        id: 'user_global_1',
        name: 'Глобальный журнал',
        type: ReportType.weldJournal,
        columns: [ReportColumn(id: 'c1', header: '№', template: '{num}')],
      );

      await repository.saveTemplate(template);

      final loaded = await repository.getTemplatesForType(ReportType.weldJournal);
      expect(loaded.any((t) => t.id == 'user_global_1'), true);
      final found = loaded.firstWhere((t) => t.id == 'user_global_1');
      expect(found.name, 'Глобальный журнал');
    });

    test('merges project templates with global and built-in templates', () async {
      const projectTemplate = ReportTemplate(
        id: 'project_only_1',
        name: 'Журнал проекта',
        type: ReportType.materialsSpecification,
        columns: [ReportColumn(id: 'c1', header: 'Поз', template: '{pos}')],
      );

      final project = ProjectModel(
        id: 'proj_1',
        title: 'Тест',
        reportTemplates: {
          projectTemplate.id: projectTemplate,
        },
      );

      final loaded = await repository.getTemplatesForType(
        ReportType.materialsSpecification,
        project: project,
      );

      // Contains built-in MTO
      expect(loaded.any((t) => t.id == 'mto_gost_21_110'), true);
      // Contains project-specific template
      expect(loaded.any((t) => t.id == 'project_only_1'), true);
    });

    test('deletes custom template but preserves built-in', () async {
      const template = ReportTemplate(
        id: 'to_delete_1',
        name: 'Удаляемый шаблон',
        type: ReportType.spoolsList,
        columns: [ReportColumn(id: 'c1', header: '№', template: '{pos}')],
      );

      await repository.saveTemplate(template);
      var loaded = await repository.getTemplatesForType(ReportType.spoolsList);
      expect(loaded.any((t) => t.id == 'to_delete_1'), true);

      await repository.deleteTemplate('to_delete_1');
      loaded = await repository.getTemplatesForType(ReportType.spoolsList);
      expect(loaded.any((t) => t.id == 'to_delete_1'), false);

      // Attempt to delete built-in should do nothing
      await repository.deleteTemplate('spools_cut_list');
      loaded = await repository.getTemplatesForType(ReportType.spoolsList);
      expect(loaded.any((t) => t.id == 'spools_cut_list'), true);
    });
  });
}
