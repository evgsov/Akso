import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../domain/models/project_model.dart';

/// Исключение при неверном PIN-коде
class QuickBridgeAuthException implements Exception {
  final String message;
  QuickBridgeAuthException(this.message);
  @override
  String toString() => 'QuickBridgeAuthException: $message';
}

/// Исключение при ошибке соединения
class QuickBridgeConnectionException implements Exception {
  final String message;
  QuickBridgeConnectionException(this.message);
  @override
  String toString() => 'QuickBridgeConnectionException: $message';
}

/// Информация об обнаруженном в локальной сети хосте Akso
class QuickBridgeDiscoveredHost {
  final String hostName;
  final String ip;
  final int port;
  final String projectTitle;
  final String? pin;

  QuickBridgeDiscoveredHost({
    required this.hostName,
    required this.ip,
    required this.port,
    required this.projectTitle,
    this.pin,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuickBridgeDiscoveredHost &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
}

/// Активная сессия передачи/приема проекта
class QuickBridgeSession {
  final HttpServer _server;
  final Timer? _beaconTimer;
  final RawDatagramSocket? _beaconSocket;
  final String localIp;
  final int port;
  final String pin;
  final String serverUrl;

  QuickBridgeSession({
    required HttpServer server,
    Timer? beaconTimer,
    RawDatagramSocket? beaconSocket,
    required this.localIp,
    required this.port,
    required this.pin,
  })  : _server = server,
        _beaconTimer = beaconTimer,
        _beaconSocket = beaconSocket,
        serverUrl = 'http://$localIp:$port';

  /// Останавливает HTTP-сервер и широковещательный маяк
  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconSocket?.close();
    await _server.close(force: true);
  }
}

/// Сервис автономного обмена проектами Akso через локальную сеть Wi-Fi (P2P)
class QuickBridgeService {
  static const int beaconPort = 42425;

  /// Определение локального IPv4 адреса устройства
  Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Запуск микросервера для передачи проекта
  Future<QuickBridgeSession> startSender({
    required ProjectModel project,
    InternetAddress? bindAddress,
    Function(String clientIp)? onTransferred,
    Function(ProjectModel project)? onProjectReceived,
  }) async {
    final address = bindAddress ?? InternetAddress.anyIPv4;
    final server = await HttpServer.bind(address, 0);
    final port = server.port;
    final pin = (1000 + Random().nextInt(9000)).toString();

    final localIp = bindAddress != null
        ? bindAddress.address
        : await getLocalIpAddress();

    // Запуск UDP маяка для автообнаружения в локальной сети
    RawDatagramSocket? beaconSocket;
    Timer? beaconTimer;
    try {
      beaconSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      beaconSocket.broadcastEnabled = true;

      final beaconData = jsonEncode({
        'app': 'akso',
        'type': 'beacon',
        'host': Platform.localHostname,
        'ip': localIp,
        'port': port,
        'title': project.title,
        'pin': pin,
      });
      final bytes = utf8.encode(beaconData);

      beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          beaconSocket?.send(
            bytes,
            InternetAddress('255.255.255.255'),
            beaconPort,
          );
        } catch (_) {}
      });
    } catch (_) {
      // Игнорируем ошибки сокета маяка (например, если нет broadcast поддержки)
    }

    // Обработка входящих HTTP-запросов
    server.listen((HttpRequest request) async {
      final res = request.response;
      // CORS заголовки для гибкости
      res.headers.set('Access-Control-Allow-Origin', '*');
      res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      res.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-Akso-Pin');

      if (request.method == 'OPTIONS') {
        res.statusCode = HttpStatus.ok;
        await res.close();
        return;
      }

      final uri = request.uri;
      final reqPin = uri.queryParameters['pin'] ?? request.headers.value('X-Akso-Pin');

      if (uri.path == '/info') {
        res.headers.contentType = ContentType.json;
        res.statusCode = HttpStatus.ok;
        res.write(jsonEncode({
          'app': 'akso',
          'title': project.title,
          'projectCode': project.projectCode,
        }));
        await res.close();
        return;
      }

      if (uri.path == '/download') {
        if (reqPin != pin) {
          res.statusCode = HttpStatus.forbidden;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'error': 'Invalid PIN'}));
          await res.close();
          return;
        }

        res.headers.contentType = ContentType.json;
        res.statusCode = HttpStatus.ok;
        final jsonString = jsonEncode(project.toJson());
        res.write(jsonString);
        final clientIp = request.connectionInfo?.remoteAddress.address ?? '';
        onTransferred?.call(clientIp);
        await res.close();
        return;
      }

      if (uri.path == '/upload') {
        if (reqPin != pin) {
          res.statusCode = HttpStatus.forbidden;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'error': 'Invalid PIN'}));
          await res.close();
          return;
        }

        try {
          final body = await utf8.decodeStream(request);
          final jsonMap = jsonDecode(body) as Map<String, dynamic>;
          final incomingProject = ProjectModel.fromJson(jsonMap);

          res.headers.contentType = ContentType.json;
          res.statusCode = HttpStatus.ok;
          res.write(jsonEncode({'status': 'ok'}));
          await res.close();

          onProjectReceived?.call(incomingProject);
        } catch (e) {
          res.statusCode = HttpStatus.badRequest;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'error': 'Malformed project data'}));
          await res.close();
        }
        return;
      }

      res.statusCode = HttpStatus.notFound;
      await res.close();
    });

    return QuickBridgeSession(
      server: server,
      beaconTimer: beaconTimer,
      beaconSocket: beaconSocket,
      localIp: localIp,
      port: port,
      pin: pin,
    );
  }

  /// Клиент: скачивание проекта с удаленного хоста
  Future<ProjectModel> downloadProject({
    required String hostIp,
    required int port,
    required String pin,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final uri = Uri.parse('http://$hostIp:$port/download?pin=$pin');
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      if (response.statusCode == HttpStatus.forbidden) {
        throw QuickBridgeAuthException('Неверный PIN-код');
      }

      if (response.statusCode != HttpStatus.ok) {
        throw QuickBridgeConnectionException('Сервер вернул статус ${response.statusCode}');
      }

      final body = await utf8.decodeStream(response).timeout(timeout);
      final jsonMap = jsonDecode(body) as Map<String, dynamic>;
      return ProjectModel.fromJson(jsonMap);
    } on QuickBridgeAuthException {
      rethrow;
    } on SocketException catch (e) {
      throw QuickBridgeConnectionException('Не удалось подключиться к $hostIp:$port: ${e.message}');
    } on TimeoutException {
      throw QuickBridgeConnectionException('Таймаут соединения с $hostIp:$port');
    } catch (e) {
      if (e is FormatException) {
        throw QuickBridgeConnectionException('Ошибка формата данных от сервера: $e');
      }
      throw QuickBridgeConnectionException('Ошибка передачи данных: $e');
    } finally {
      client.close();
    }
  }

  /// Клиент: отправка проекта на удаленный хост (обратный обмен)
  Future<bool> uploadProject({
    required String hostIp,
    required int port,
    required String pin,
    required ProjectModel project,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final uri = Uri.parse('http://$hostIp:$port/upload?pin=$pin');
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(project.toJson()));

      final response = await request.close().timeout(timeout);

      if (response.statusCode == HttpStatus.forbidden) {
        throw QuickBridgeAuthException('Неверный PIN-код');
      }

      if (response.statusCode != HttpStatus.ok) {
        throw QuickBridgeConnectionException('Сервер вернул ошибку ${response.statusCode}');
      }

      return true;
    } on QuickBridgeAuthException {
      rethrow;
    } on SocketException catch (e) {
      throw QuickBridgeConnectionException('Не удалось подключиться к $hostIp:$port: ${e.message}');
    } on TimeoutException {
      throw QuickBridgeConnectionException('Таймаут соединения с $hostIp:$port');
    } catch (e) {
      throw QuickBridgeConnectionException('Ошибка отправки проекта: $e');
    } finally {
      client.close();
    }
  }

  /// Слушает широковещательные маяки в локальной сети
  Stream<QuickBridgeDiscoveredHost> discoverHosts({
    Duration timeout = const Duration(seconds: 4),
  }) {
    final controller = StreamController<QuickBridgeDiscoveredHost>();
    final discoveredKeys = <String>{};
    RawDatagramSocket? socket;

    Future<void> startListening() async {
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          beaconPort,
          reuseAddress: true,
        );
        socket?.broadcastEnabled = true;

        socket?.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket?.receive();
            if (datagram == null) return;

            try {
              final text = utf8.decode(datagram.data);
              final map = jsonDecode(text) as Map<String, dynamic>;
              if (map['app'] == 'akso' && map['type'] == 'beacon') {
                final ip = map['ip'] as String? ?? datagram.address.address;
                final port = map['port'] as int;
                final key = '$ip:$port';

                if (!discoveredKeys.contains(key)) {
                  discoveredKeys.add(key);
                  controller.add(QuickBridgeDiscoveredHost(
                    hostName: map['host'] as String? ?? 'Устройство Akso',
                    ip: ip,
                    port: port,
                    projectTitle: map['title'] as String? ?? '',
                    pin: map['pin'] as String?,
                  ));
                }
              }
            } catch (_) {}
          }
        });
      } catch (e) {
        // Если порт 42425 занят или запрещен, тихо завершаем
      }
    }

    startListening();

    Timer(timeout, () {
      socket?.close();
      if (!controller.isClosed) {
        controller.close();
      }
    });

    return controller.stream;
  }
}
