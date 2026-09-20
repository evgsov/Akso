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

/// Сетевой интерфейс для выбора адаптера передачи
class QuickBridgeNetworkInterface {
  final String name;
  final String ip;
  final bool isWifi;
  final bool isVirtual;

  QuickBridgeNetworkInterface({
    required this.name,
    required this.ip,
    this.isWifi = false,
    this.isVirtual = false,
  });

  String get displayName {
    if (isWifi) return '$name (Wi-Fi: $ip)';
    if (isVirtual) return '$name (Виртуальный: $ip)';
    return '$name ($ip)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuickBridgeNetworkInterface &&
          runtimeType == other.runtimeType &&
          ip == other.ip;

  @override
  int get hashCode => ip.hashCode;
}

/// Распарсенная информация для прямого подключения к хосту
class QuickBridgeConnectionInfo {
  final String ip;
  final int port;
  final String pin;

  QuickBridgeConnectionInfo({
    required this.ip,
    required this.port,
    required this.pin,
  });

  String get code => '$ip:$port#$pin';
  String get url => 'http://$ip:$port/download?pin=$pin';

  @override
  String toString() => code;
}

/// Активная сессия передачи/приема проекта
class QuickBridgeSession {
  final HttpServer? _server;
  final Timer? _beaconTimer;
  final RawDatagramSocket? _beaconSocket;
  final String localIp;
  final int port;
  final String pin;
  final String serverUrl;

  QuickBridgeSession({
    HttpServer? server,
    Timer? beaconTimer,
    RawDatagramSocket? beaconSocket,
    required this.localIp,
    required this.port,
    required this.pin,
    String? serverUrl,
  })  : _server = server,
        _beaconTimer = beaconTimer,
        _beaconSocket = beaconSocket,
        serverUrl = serverUrl ?? 'http://$localIp:$port';

  /// Единый код быстрого подключения для планшета
  String get connectionCode => '$localIp:$port#$pin';

  /// Останавливает HTTP-сервер и широковещательный маяк
  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconSocket?.close();
    await _server?.close(force: true);
  }
}

/// Сервис автономного обмена проектами Akso через локальную сеть Wi-Fi (P2P)
class QuickBridgeService {
  static const int defaultPort = 42424;
  static const int beaconPort = 42425;

  static const List<String> virtualInterfacePatterns = [
    'vethernet',
    'wsl',
    'virtual',
    'vbox',
    'vmware',
    'docker',
    'loopback',
    'tailscale',
    'zerotier',
    'tap',
    'tun',
  ];

  /// Проверяет, является ли интерфейс виртуальным (WSL, Docker, VPN и т.д.)
  static bool isVirtualInterface(String name) {
    final lower = name.toLowerCase();
    return virtualInterfacePatterns.any((p) => lower.contains(p));
  }

  /// Проверяет, является ли интерфейс Wi-Fi / WLAN адаптером
  static bool isWifiInterface(String name) {
    final lower = name.toLowerCase();
    return lower.contains('wi-fi') || lower.contains('wlan') || lower.contains('wireless');
  }

  /// Возвращает список всех доступных локальных IPv4 сетевых интерфейсов
  Future<List<QuickBridgeNetworkInterface>> getAvailableInterfaces() async {
    final result = <QuickBridgeNetworkInterface>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            final isVirt = isVirtualInterface(iface.name);
            final isWifi = isWifiInterface(iface.name);
            result.add(QuickBridgeNetworkInterface(
              name: iface.name,
              ip: addr.address,
              isWifi: isWifi,
              isVirtual: isVirt,
            ));
          }
        }
      }
    } catch (_) {}

    // Сортировка:
    // 1. Физический Wi-Fi
    // 2. Физический Ethernet с домашними адресами 192.168.x.x или 10.x.x.x
    // 3. Прочие физические
    // 4. Виртуальные адаптеры (в конец)
    result.sort((a, b) {
      if (a.isVirtual != b.isVirtual) {
        return a.isVirtual ? 1 : -1;
      }
      if (a.isWifi != b.isWifi) {
        return a.isWifi ? -1 : 1;
      }
      final aIsHome = a.ip.startsWith('192.168.') || a.ip.startsWith('10.');
      final bIsHome = b.ip.startsWith('192.168.') || b.ip.startsWith('10.');
      if (aIsHome != bIsHome) {
        return aIsHome ? -1 : 1;
      }
      return a.ip.compareTo(b.ip);
    });

    return result;
  }

  /// Определение лучшего локального IPv4 адреса устройства (с приоритетом Wi-Fi)
  Future<String> getLocalIpAddress() async {
    final ifaces = await getAvailableInterfaces();
    if (ifaces.isNotEmpty) {
      return ifaces.first.ip;
    }
    return '127.0.0.1';
  }

  /// Парсит единую строку подключения (код, ссылку или JSON) в структурированный объект
  static QuickBridgeConnectionInfo? parseConnectionCode(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // 1. Формат JSON из QR-кода: {"app":"akso","ip":"192.168.1.50","port":42424,"pin":"1234"}
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final map = jsonDecode(text) as Map<String, dynamic>;
        if (map['app'] == 'akso' && map['ip'] != null) {
          return QuickBridgeConnectionInfo(
            ip: map['ip'] as String,
            port: (map['port'] as num?)?.toInt() ?? defaultPort,
            pin: map['pin']?.toString() ?? '',
          );
        }
      } catch (_) {}
    }

    // 2. Формат URL: http://192.168.1.50:42424/download?pin=1234 или http://192.168.1.50:42424#1234
    if (text.startsWith('http://') || text.startsWith('https://')) {
      try {
        final uri = Uri.parse(text);
        final ip = uri.host;
        final port = uri.port != 0 ? uri.port : defaultPort;
        final pin = uri.queryParameters['pin'] ?? (uri.fragment.isNotEmpty ? uri.fragment : '');
        if (ip.isNotEmpty) {
          return QuickBridgeConnectionInfo(ip: ip, port: port, pin: pin);
        }
      } catch (_) {}
    }

    // 3. Формат: 192.168.1.50:42424#1234 или 192.168.1.50#1234
    String pin = '';
    if (text.contains('#')) {
      final hashParts = text.split('#');
      text = hashParts[0].trim();
      pin = hashParts[1].trim();
    }

    String ip = text;
    int port = defaultPort;
    if (text.contains(':')) {
      final colonParts = text.split(':');
      ip = colonParts[0].trim();
      port = int.tryParse(colonParts[1].trim()) ?? defaultPort;
    }

    if (ip.isNotEmpty) {
      return QuickBridgeConnectionInfo(ip: ip, port: port, pin: pin);
    }

    return null;
  }

  /// Вычисляет адрес подсетевого широковещания (например, 192.168.1.255)
  static String? getSubnetBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.255';
    }
    return null;
  }

  /// Запуск микросервера для передачи проекта
  Future<QuickBridgeSession> startSender({
    required ProjectModel project,
    InternetAddress? bindAddress,
    int? requestedPort,
    String? customLocalIp,
    bool enableBeacon = true,
    Function(String clientIp)? onTransferred,
    Function(ProjectModel project)? onProjectReceived,
  }) async {
    final address = bindAddress ?? InternetAddress.anyIPv4;

    // Пытаемся занять стандартный порт 42424, либо последовательно следующие
    HttpServer? server;
    final startPort = requestedPort ?? (bindAddress != null ? 0 : defaultPort);
    if (startPort > 0) {
      for (int p = startPort; p < startPort + 5; p++) {
        try {
          server = await HttpServer.bind(address, p);
          break;
        } catch (_) {}
      }
    }
    server ??= await HttpServer.bind(address, 0);
    final port = server.port;
    final pin = (1000 + Random().nextInt(9000)).toString();

    final localIp = customLocalIp ??
        (bindAddress != null
            ? bindAddress.address
            : await getLocalIpAddress());

    // Запуск UDP маяка для автообнаружения в локальной сети
    RawDatagramSocket? beaconSocket;
    Timer? beaconTimer;
    if (enableBeacon) {
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
        final subnetBroadcast = getSubnetBroadcast(localIp);

        beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          try {
            // Отправляем как на глобальный broadcast, так и на широковещательный адрес подсети
            beaconSocket?.send(
              bytes,
              InternetAddress('255.255.255.255'),
              beaconPort,
            );
            if (subnetBroadcast != null) {
              beaconSocket?.send(
                bytes,
                InternetAddress(subnetBroadcast),
                beaconPort,
              );
            }
          } catch (_) {}
        });
      } catch (_) {
        // Игнорируем ошибки сокета маяка (например, если нет broadcast поддержки)
      }
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

  /// Активное сканирование локальной подсети /24 (резерв при блокировке UDP-маяка роутером)
  Future<List<QuickBridgeDiscoveredHost>> scanSubnet({
    String? baseIp,
    int port = defaultPort,
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    final localIp = baseIp ?? await getLocalIpAddress();
    final parts = localIp.split('.');
    if (parts.length != 4) return [];
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    final discovered = <QuickBridgeDiscoveredHost>[];
    final client = HttpClient();
    client.connectionTimeout = timeout;

    final myOctet = int.tryParse(parts[3]) ?? 100;
    final hostsToScan = <int>{};
    // Сканируем диапазон 1..35 (обычно роутер и первые клиенты)
    for (int i = 1; i <= 35; i++) {
      hostsToScan.add(i);
    }
    // Сканируем диапазон +/- 10 вокруг нашего IP
    for (int i = max(1, myOctet - 10); i <= min(254, myOctet + 10); i++) {
      hostsToScan.add(i);
    }
    hostsToScan.remove(myOctet); // Не опрашиваем себя

    final futures = hostsToScan.map((octet) async {
      final ip = '$prefix.$octet';
      try {
        final req = await client.getUrl(Uri.parse('http://$ip:$port/info')).timeout(timeout);
        final resp = await req.close().timeout(timeout);
        if (resp.statusCode == HttpStatus.ok) {
          final body = await utf8.decodeStream(resp).timeout(timeout);
          final map = jsonDecode(body) as Map<String, dynamic>;
          if (map['app'] == 'akso') {
            discovered.add(QuickBridgeDiscoveredHost(
              hostName: map['title'] as String? ?? 'Устройство Akso ($ip)',
              ip: ip,
              port: port,
              projectTitle: map['title'] as String? ?? '',
            ));
          }
        }
      } catch (_) {}
    });

    await Future.wait(futures);
    client.close();
    return discovered;
  }
}
