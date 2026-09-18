import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/repositories/recent_projects_manager.dart';

void main() {
  group('RecentProjectEntry Tests', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.parse('2026-09-18T16:00:00.000Z');
      final entry = RecentProjectEntry(
        title: 'Тестовый проект',
        filePath: 'C:/Projects/test.akso',
        projectCode: 'ТХ-01',
        lastOpened: now,
      );

      final json = entry.toJson();
      expect(json['title'], equals('Тестовый проект'));
      expect(json['filePath'], equals('C:/Projects/test.akso'));
      expect(json['projectCode'], equals('ТХ-01'));
      expect(json['lastOpened'], equals('2026-09-18T16:00:00.000Z'));

      final fromJson = RecentProjectEntry.fromJson(json);
      expect(fromJson.title, equals(entry.title));
      expect(fromJson.filePath, equals(entry.filePath));
      expect(fromJson.projectCode, equals(entry.projectCode));
      expect(fromJson.lastOpened.toUtc(), equals(now));
    });
  });

  group('RecentProjectsManager Tests', () {
    late Directory tempDir;
    late RecentProjectsManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('akso_recent_test_');
      manager = RecentProjectsManager(
        getStorageDir: () async => tempDir,
        maxItems: 3,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns empty list when no file exists', () async {
      final list = await manager.getRecentProjects();
      expect(list, isEmpty);
    });

    test('adds recent project and preserves order (most recent first)', () async {
      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 1',
        filePath: 'C:/p1.akso',
        projectCode: '01',
        lastOpened: DateTime(2026, 9, 10),
      ));

      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 2',
        filePath: 'C:/p2.akso',
        projectCode: '02',
        lastOpened: DateTime(2026, 9, 12),
      ));

      final list = await manager.getRecentProjects();
      expect(list.length, equals(2));
      expect(list[0].title, equals('Проект 2'));
      expect(list[1].title, equals('Проект 1'));
    });

    test('updates existing entry and moves it to the top without duplicates', () async {
      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 1',
        filePath: 'C:/p1.akso',
        projectCode: '01',
        lastOpened: DateTime(2026, 9, 10),
      ));

      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 2',
        filePath: 'C:/p2.akso',
        projectCode: '02',
        lastOpened: DateTime(2026, 9, 12),
      ));

      // Re-add Project 1 with updated title
      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 1 (Обновлен)',
        filePath: 'C:/p1.akso',
        projectCode: '01-A',
        lastOpened: DateTime(2026, 9, 15),
      ));

      final list = await manager.getRecentProjects();
      expect(list.length, equals(2));
      expect(list[0].filePath, equals('C:/p1.akso'));
      expect(list[0].title, equals('Проект 1 (Обновлен)'));
      expect(list[0].projectCode, equals('01-A'));
      expect(list[1].filePath, equals('C:/p2.akso'));
    });

    test('limits list size to maxItems', () async {
      for (int i = 1; i <= 5; i++) {
        await manager.addRecentProject(RecentProjectEntry(
          title: 'Проект $i',
          filePath: 'C:/p$i.akso',
          projectCode: '0$i',
          lastOpened: DateTime(2026, 9, i),
        ));
      }

      final list = await manager.getRecentProjects();
      expect(list.length, equals(3));
      expect(list[0].title, equals('Проект 5'));
      expect(list[1].title, equals('Проект 4'));
      expect(list[2].title, equals('Проект 3'));
    });

    test('removes entry by filePath', () async {
      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 1',
        filePath: 'C:/p1.akso',
        projectCode: '01',
        lastOpened: DateTime(2026, 9, 10),
      ));
      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 2',
        filePath: 'C:/p2.akso',
        projectCode: '02',
        lastOpened: DateTime(2026, 9, 12),
      ));

      await manager.removeRecentProject('C:/p1.akso');

      final list = await manager.getRecentProjects();
      expect(list.length, equals(1));
      expect(list[0].filePath, equals('C:/p2.akso'));
    });

    test('clears all recent projects', () async {
      await manager.addRecentProject(RecentProjectEntry(
        title: 'Проект 1',
        filePath: 'C:/p1.akso',
        projectCode: '01',
        lastOpened: DateTime(2026, 9, 10),
      ));

      await manager.clearRecentProjects();

      final list = await manager.getRecentProjects();
      expect(list, isEmpty);
    });
  });
}
