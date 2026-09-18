import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/services/quick_bridge_service.dart';
import 'package:akso/domain/models/project_model.dart';

void main() {
  group('QuickBridgeService Local Transfer Tests', () {
    late QuickBridgeService bridge;
    late ProjectModel sampleProject;
    QuickBridgeSession? session;

    setUp(() {
      bridge = QuickBridgeService();
      sampleProject = ProjectModel(
        id: 'qb_1',
        title: 'Узел напорный',
        projectCode: 'ОВ-01',
        notes: 'Синхронизация через Wi-Fi',
      );
    });

    tearDown(() async {
      if (session != null) {
        await session!.stop();
        session = null;
      }
    });

    test('startSender launches HttpServer on local port with 4-digit PIN', () async {
      session = await bridge.startSender(
        project: sampleProject,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      expect(session!.port, greaterThan(1024));
      expect(session!.pin.length, equals(4));
      expect(int.tryParse(session!.pin), isNotNull);
      expect(session!.serverUrl, contains('127.0.0.1:${session!.port}'));
    });

    test('downloadProject downloads ProjectModel with valid PIN', () async {
      bool transferredCalled = false;
      session = await bridge.startSender(
        project: sampleProject,
        bindAddress: InternetAddress.loopbackIPv4,
        onTransferred: (ip) {
          transferredCalled = true;
        },
      );

      final downloaded = await bridge.downloadProject(
        hostIp: '127.0.0.1',
        port: session!.port,
        pin: session!.pin,
      );

      expect(downloaded.id, equals('qb_1'));
      expect(downloaded.title, equals('Узел напорный'));
      expect(downloaded.projectCode, equals('ОВ-01'));
      expect(downloaded.notes, equals('Синхронизация через Wi-Fi'));
      expect(transferredCalled, isTrue);
    });

    test('downloadProject throws QuickBridgeAuthException on invalid PIN', () async {
      session = await bridge.startSender(
        project: sampleProject,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      expect(
        () async => await bridge.downloadProject(
          hostIp: '127.0.0.1',
          port: session!.port,
          pin: '0000', // Invalid PIN
        ),
        throwsA(isA<QuickBridgeAuthException>()),
      );
    });

    test('uploadProject uploads project and triggers onProjectReceived with valid PIN', () async {
      final completer = Completer<ProjectModel>();
      session = await bridge.startSender(
        project: sampleProject,
        bindAddress: InternetAddress.loopbackIPv4,
        onProjectReceived: (p) {
          completer.complete(p);
        },
      );

      final updatedProject = sampleProject.copyWith(
        title: 'Узел напорный (с планшета)',
        notes: 'Добавлены задвижки на месте',
      );

      final ok = await bridge.uploadProject(
        hostIp: '127.0.0.1',
        port: session!.port,
        pin: session!.pin,
        project: updatedProject,
      );

      expect(ok, isTrue);
      final received = await completer.future.timeout(const Duration(seconds: 3));
      expect(received.title, equals('Узел напорный (с планшета)'));
      expect(received.notes, equals('Добавлены задвижки на месте'));
    });

    test('uploadProject throws QuickBridgeAuthException on invalid PIN', () async {
      session = await bridge.startSender(
        project: sampleProject,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      expect(
        () async => await bridge.uploadProject(
          hostIp: '127.0.0.1',
          port: session!.port,
          pin: '9999',
          project: sampleProject,
        ),
        throwsA(isA<QuickBridgeAuthException>()),
      );
    });

    test('session stop closes server', () async {
      session = await bridge.startSender(
        project: sampleProject,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      final port = session!.port;
      await session!.stop();
      session = null;

      expect(
        () async => await bridge.downloadProject(
          hostIp: '127.0.0.1',
          port: port,
          pin: '1234',
        ),
        throwsA(isA<QuickBridgeConnectionException>()),
      );
    });

    test('GET /info returns project title and code without requiring PIN', () async {
      session = await bridge.startSender(
        project: sampleProject,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:${session!.port}/info'));
      final res = await req.close();
      expect(res.statusCode, equals(HttpStatus.ok));

      final body = await utf8.decodeStream(res);
      expect(body, contains('Узел напорный'));
      expect(body, contains('ОВ-01'));
      client.close();
    });

    test('QuickBridgeDiscoveredHost equality and hash code based on ip and port', () {
      final h1 = QuickBridgeDiscoveredHost(
        hostName: 'Host 1',
        ip: '192.168.1.10',
        port: 8080,
        projectTitle: 'P1',
      );
      final h2 = QuickBridgeDiscoveredHost(
        hostName: 'Host 2 (Renamed)',
        ip: '192.168.1.10',
        port: 8080,
        projectTitle: 'P2',
      );
      final h3 = QuickBridgeDiscoveredHost(
        hostName: 'Host 3',
        ip: '192.168.1.11',
        port: 8080,
        projectTitle: 'P1',
      );

      expect(h1, equals(h2));
      expect(h1.hashCode, equals(h2.hashCode));
      expect(h1, isNot(equals(h3)));
    });
  });
}
