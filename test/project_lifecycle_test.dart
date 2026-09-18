import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/project_model.dart';

void main() {
  group('ProjectModel Metadata Tests', () {
    test('ProjectModel has projectCode, notes, and lastModifiedDate with defaults', () {
      final project = ProjectModel(
        id: 'p1',
        title: 'Узел учета',
      );

      expect(project.id, equals('p1'));
      expect(project.title, equals('Узел учета'));
      expect(project.projectCode, equals(''));
      expect(project.notes, equals(''));
      expect(project.lastModifiedDate, isNotEmpty);
    });

    test('ProjectModel serializes and deserializes new metadata fields', () {
      final project = ProjectModel(
        id: 'p2',
        title: 'Насосная станция',
        projectCode: 'ТХ-02.1',
        objectAddress: 'г. Москва, Цех №4',
        engineerName: 'Иванов И.И.',
        notes: 'Проверить отметки фланцев насосов Н1 и Н2',
        creationDate: '2026-09-18',
        lastModifiedDate: '2026-09-18T16:00:00.000Z',
      );

      final json = project.toJson();
      expect(json['projectCode'], equals('ТХ-02.1'));
      expect(json['notes'], equals('Проверить отметки фланцев насосов Н1 и Н2'));
      expect(json['lastModifiedDate'], equals('2026-09-18T16:00:00.000Z'));

      final reconstructed = ProjectModel.fromJson(json);
      expect(reconstructed.id, equals('p2'));
      expect(reconstructed.title, equals('Насосная станция'));
      expect(reconstructed.projectCode, equals('ТХ-02.1'));
      expect(reconstructed.objectAddress, equals('г. Москва, Цех №4'));
      expect(reconstructed.engineerName, equals('Иванов И.И.'));
      expect(reconstructed.notes, equals('Проверить отметки фланцев насосов Н1 и Н2'));
      expect(reconstructed.creationDate, equals('2026-09-18'));
      expect(reconstructed.lastModifiedDate, equals('2026-09-18T16:00:00.000Z'));
    });

    test('ProjectModel.fromJson handles legacy JSON missing new fields', () {
      final legacyJson = {
        'id': 'legacy_1',
        'title': 'Старый проект',
        'objectAddress': 'Адрес',
        'engineerName': 'Инженер',
        'creationDate': '2025-01-01',
        'projectionType': 0,
        'activeSystemId': 'sys_b1',
        'activeDn': 25,
        'currentElevationZ': 0.0,
        'network': <String, dynamic>{
          'nodes': <String, dynamic>{},
          'segments': <String, dynamic>{},
          'valves': <String, dynamic>{},
          'welds': <String, dynamic>{},
          'reducers': <String, dynamic>{},
          'flanges': <String, dynamic>{},
          'caps': <String, dynamic>{},
          'supports': <String, dynamic>{},
          'equipments': <String, dynamic>{},
          'axes': <String, dynamic>{},
          'dimensions': <String, dynamic>{},
          'callouts': <String, dynamic>{},
        },
      };

      final project = ProjectModel.fromJson(legacyJson);
      expect(project.projectCode, equals(''));
      expect(project.notes, equals(''));
      expect(project.lastModifiedDate, equals('2025-01-01'));
    });

    test('copyWith updates new fields correctly', () {
      final project = ProjectModel(
        id: 'p3',
        title: 'Базовый',
        projectCode: '01',
        notes: 'Заметка 1',
      );

      final updated = project.copyWith(
        projectCode: '02',
        notes: 'Заметка 2',
        lastModifiedDate: '2026-09-18T16:30:00.000Z',
      );

      expect(updated.projectCode, equals('02'));
      expect(updated.notes, equals('Заметка 2'));
      expect(updated.lastModifiedDate, equals('2026-09-18T16:30:00.000Z'));
      expect(updated.title, equals('Базовый'));
    });
  });
}
