import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/report_type.dart';
import 'package:akso/domain/models/report_template.dart';
import 'package:akso/domain/models/report_token_definition.dart';

void main() {
  group('ReportType tests', () {
    test('enum properties should be correct', () {
      expect(ReportType.weldJournal.displayName, 'Сварочный журнал');
      expect(ReportType.weldJournal.defaultFileName, 'weld_journal');
      expect(ReportType.materialsSpecification.displayName, 'Спецификация оборудования и материалов');
      expect(ReportType.spoolsList.displayName, 'Ведомость трубных заготовок');
    });
  });

  group('ReportColumn model tests', () {
    test('serialization and deserialization', () {
      const col = ReportColumn(
        id: 'col_1',
        header: 'Элемент №1',
        template: '{elem1_name}',
        groupHeader: 'Элемент №1',
        width: 150.0,
        isNumeric: false,
        alignment: TextAlign.left,
      );

      final json = col.toJson();
      final fromJson = ReportColumn.fromJson(json);

      expect(fromJson.id, 'col_1');
      expect(fromJson.header, 'Элемент №1');
      expect(fromJson.template, '{elem1_name}');
      expect(fromJson.groupHeader, 'Элемент №1');
      expect(fromJson.width, 150.0);
      expect(fromJson.isNumeric, false);
      expect(fromJson.alignment, TextAlign.left);
    });

    test('copyWith works correctly', () {
      const col = ReportColumn(
        id: 'col_1',
        header: 'Диаметр',
        template: '{elem1_dn}',
        width: 80.0,
        isNumeric: true,
      );

      final updated = col.copyWith(header: 'Диаметр №1', width: 90.0);
      expect(updated.header, 'Диаметр №1');
      expect(updated.width, 90.0);
      expect(updated.isNumeric, true);
    });
  });

  group('ReportTemplate model tests', () {
    test('serialization and deserialization of template', () {
      final template = ReportTemplate(
        id: 'custom_weld_1',
        name: 'Мой журнал',
        type: ReportType.weldJournal,
        isBuiltIn: false,
        headerNote: 'Объект: Резервуарный парк',
        columns: const [
          ReportColumn(id: 'c1', header: '№', template: '{num}', isNumeric: true),
          ReportColumn(id: 'c2', header: 'Стык', template: '{weld_num}'),
          ReportColumn(id: 'c3', header: 'Соединение', template: '{connection_type}'),
        ],
      );

      final json = template.toJson();
      final fromJson = ReportTemplate.fromJson(json);

      expect(fromJson.id, 'custom_weld_1');
      expect(fromJson.name, 'Мой журнал');
      expect(fromJson.type, ReportType.weldJournal);
      expect(fromJson.isBuiltIn, false);
      expect(fromJson.headerNote, 'Объект: Резервуарный парк');
      expect(fromJson.columns.length, 3);
      expect(fromJson.columns[2].template, '{connection_type}');
    });

    test('built-in templates exist and have columns', () {
      final transneft = ReportTemplate.defaultWeldJournalTransneftTemplate;
      expect(transneft.id, 'weld_journal_transneft');
      expect(transneft.type, ReportType.weldJournal);
      expect(transneft.columns.isNotEmpty, true);
      expect(transneft.columns.any((c) => c.template.contains('{connection_type}')), true);
      expect(transneft.columns.any((c) => c.template.contains('{elem1_name}')), true);
      expect(transneft.columns.any((c) => c.template.contains('{elem2_name}')), true);

      final gostWeld = ReportTemplate.defaultWeldJournalGostTemplate;
      expect(gostWeld.id, 'weld_journal_gost_spds');
      expect(gostWeld.columns.isNotEmpty, true);

      final mto = ReportTemplate.defaultMtoGostTemplate;
      expect(mto.id, 'mto_gost_21_110');
      expect(mto.type, ReportType.materialsSpecification);
      expect(mto.columns.isNotEmpty, true);

      final spools = ReportTemplate.defaultSpoolsCutListTemplate;
      expect(spools.id, 'spools_cut_list');
      expect(spools.type, ReportType.spoolsList);
      expect(spools.columns.isNotEmpty, true);
    });
  });

  group('ReportTokenDefinition tests', () {
    test('catalog contains tokens for weld journal and specification', () {
      final allTokens = ReportTokenDefinition.allTokens;
      expect(allTokens.isNotEmpty, true);

      final weldTokens = ReportTokenDefinition.getTokensForType(ReportType.weldJournal);
      expect(weldTokens.any((t) => t.code == '{connection_type}'), true);
      expect(weldTokens.any((t) => t.code == '{elem1_name}'), true);
      expect(weldTokens.any((t) => t.code == '{elem2_name}'), true);
      expect(weldTokens.any((t) => t.code == '{stamp}'), true);

      final mtoTokens = ReportTokenDefinition.getTokensForType(ReportType.materialsSpecification);
      expect(mtoTokens.any((t) => t.code == '{name}'), true);
      expect(mtoTokens.any((t) => t.code == '{qty}'), true);
    });
  });
}
