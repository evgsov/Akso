import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../data/repositories/project_repository.dart';
import '../../../../data/services/quick_bridge_service.dart';
import '../../../../domain/models/project_model.dart';
import '../../../canvas/input_controller.dart';

/// Диалог быстрого обмена проектами Akso между ПК и планшетом по Wi-Fi (QuickBridge 2.0)
class QuickBridgeDialog extends StatefulWidget {
  final PipingInputController controller;
  final QuickBridgeService? bridgeService;
  final bool enableBeacon;
  final QuickBridgeSession? initialSession;

  const QuickBridgeDialog({
    super.key,
    required this.controller,
    this.bridgeService,
    this.enableBeacon = true,
    this.initialSession,
  });

  @override
  State<QuickBridgeDialog> createState() => _QuickBridgeDialogState();
}

class _QuickBridgeDialogState extends State<QuickBridgeDialog> {
  late final QuickBridgeService _bridge;
  QuickBridgeSession? _session;
  bool _isSenderMode = true; // true = Поделиться чертежом, false = Получить чертеж
  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;

  // Режим раздачи: список интерфейсов и выбранный адаптер
  List<QuickBridgeNetworkInterface> _interfaces = [];
  QuickBridgeNetworkInterface? _selectedInterface;

  // Режим приема: обнаруженные хосты
  final List<QuickBridgeDiscoveredHost> _discoveredHosts = [];
  StreamSubscription<QuickBridgeDiscoveredHost>? _discoverySub;

  // Поле быстрого подключения по коду/адресу
  final _connectionCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridgeService ?? QuickBridgeService();
    if (widget.initialSession != null) {
      _session = widget.initialSession;
    } else {
      _initAndStartSenderSession();
    }
  }

  @override
  void dispose() {
    _session?.stop();
    _discoverySub?.cancel();
    _connectionCodeController.dispose();
    super.dispose();
  }

  Future<void> _initAndStartSenderSession() async {
    try {
      final ifaces = await _bridge.getAvailableInterfaces();
      if (mounted) {
        setState(() {
          _interfaces = ifaces;
          if (_selectedInterface == null && ifaces.isNotEmpty) {
            _selectedInterface = ifaces.first;
          }
        });
      }
    } catch (_) {}
    await _startSenderSession();
  }

  Future<void> _startSenderSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _session?.stop();
      _session = await _bridge.startSender(
        project: widget.controller.currentProject.copyWith(
          network: widget.controller.network,
          lastModifiedDate: DateTime.now().toIso8601String(),
        ),
        customLocalIp: _selectedInterface?.ip,
        enableBeacon: widget.enableBeacon,
        onTransferred: (clientIp) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Чертеж успешно передан на устройство ($clientIp)!';
            });
          }
        },
        onProjectReceived: (incomingProject) {
          if (mounted) {
            _applyReceivedProject(incomingProject);
          }
        },
      );
    } catch (e) {
      _errorMessage = 'Не удалось запустить точку передачи: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startDiscovery() {
    _discoveredHosts.clear();
    _discoverySub?.cancel();
    if (!widget.enableBeacon) return;

    // 1. Прослушивание UDP маяка
    _discoverySub = _bridge.discoverHosts(timeout: const Duration(seconds: 8)).listen((host) {
      if (mounted) {
        setState(() {
          if (!_discoveredHosts.contains(host)) {
            _discoveredHosts.add(host);
          }
        });
      }
    });

    // 2. Резервный параллельный опрос подсети по HTTP (при блокировке UDP роутером)
    _bridge.scanSubnet().then((hosts) {
      if (mounted) {
        setState(() {
          for (final h in hosts) {
            if (!_discoveredHosts.contains(h)) {
              _discoveredHosts.add(h);
            }
          }
        });
      }
    }).catchError((_) {});
  }

  Future<void> _downloadFromHost(String ip, int port, String pin) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Подключение к $ip:$port...';
    });

    try {
      final project = await _bridge.downloadProject(hostIp: ip, port: port, pin: pin);
      if (mounted) {
        await _applyReceivedProject(project);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('QuickBridgeAuthException: ', '').replaceFirst('QuickBridgeConnectionException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connectUsingCode() async {
    final raw = _connectionCodeController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _errorMessage = 'Введите код подключения, ссылку или IP-адрес';
      });
      return;
    }

    final parsed = QuickBridgeService.parseConnectionCode(raw);
    if (parsed == null) {
      setState(() {
        _errorMessage = 'Не удалось распознать адрес. Пример формата: 192.168.1.50:42424#1234';
      });
      return;
    }

    String pin = parsed.pin;
    if (pin.isEmpty) {
      final enteredPin = await _showPinPrompt(parsed.ip, parsed.port);
      if (enteredPin == null || enteredPin.isEmpty) return;
      pin = enteredPin;
    }

    await _downloadFromHost(parsed.ip, parsed.port, pin);
  }

  Future<void> _applyReceivedProject(ProjectModel project) async {
    final hasContent = widget.controller.hasUnsavedChanges || widget.controller.network.segments.isNotEmpty;
    if (hasContent) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Заменить текущий чертеж?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('В открытом проекте есть несохраненные данные.'),
              const SizedBox(height: 12),
              Text(
                'Текущий чертеж: "${widget.controller.currentProject.title}" (${widget.controller.network.segments.length} труб)',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Входящий проект: "${project.title}" (${project.network.segments.length} труб)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Замена приведет к перезаписи текущего чертежа на холсте.',
                style: TextStyle(fontSize: 12, color: Colors.amber),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Заменить чертеж'),
            ),
          ],
        ),
      );

      if (shouldReplace != true) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
    }

    widget.controller.currentProject = project;
    widget.controller.network = project.network;
    widget.controller.currentFilePath = null;
    widget.controller.hasUnsavedChanges = false;
    widget.controller.history.clear();
    widget.controller.history.recordState(widget.controller.network);
    widget.controller.cancelCurrentOperation(keepTool: false);
    widget.controller.refresh();

    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Проект "${project.title}" успешно получен!'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    }
  }

  Future<void> _shareProjectFile() async {
    try {
      final jsonStr = jsonEncode(widget.controller.currentProject.copyWith(
        network: widget.controller.network,
        lastModifiedDate: DateTime.now().toIso8601String(),
      ).toJson());

      final tempDir = await getTemporaryDirectory();
      final safeTitle = widget.controller.currentProject.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '$safeTitle.akso';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonStr);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Проект Akso: ${widget.controller.currentProject.title}',
          text: 'Файл схемы трубопроводов Akso (.akso)',
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Не удалось экспортировать файл: $e';
        });
      }
    }
  }

  Future<void> _openProjectFile() async {
    try {
      final loaded = await ProjectRepository().loadProject();
      if (loaded != null && mounted) {
        await _applyReceivedProject(loaded.project);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка открытия файла: $e';
        });
      }
    }
  }

  Future<String?> _showPinPrompt(String ip, int port) async {
    final pinController = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Введите PIN-код'),
        content: TextField(
          controller: pinController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '4-значный код с экрана хоста $ip:$port',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(pinController.text.trim()), child: const Text('ОК')),
        ],
      ),
    );
    return pin;
  }

  Future<void> _showPinPromptAndDownload(String ip, int port) async {
    final pin = await _showPinPrompt(ip, port);
    if (pin != null && pin.isNotEmpty) {
      _downloadFromHost(ip, port, pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.wifi_tethering, color: Colors.cyanAccent),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Быстрый обмен Wi-Fi (QuickBridge)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Универсальные симметричные вкладки
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Поделиться чертежом'),
                    icon: Icon(Icons.wifi_tethering, size: 16),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Получить чертеж'),
                    icon: Icon(Icons.download, size: 16),
                  ),
                ],
                selected: {_isSenderMode},
                onSelectionChanged: (val) {
                  setState(() {
                    _isSenderMode = val.first;
                    _errorMessage = null;
                    _statusMessage = null;
                    if (!_isSenderMode) {
                      _startDiscovery();
                    }
                  });
                },
              ),
              const SizedBox(height: 20),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_isSenderMode)
                _buildSenderView()
              else
                _buildReceiverView(),

              if (_statusMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade400),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 18, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade400),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }

  Widget _buildSenderView() {
    if (_session == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final qrPayload = jsonEncode({
      'app': 'akso',
      'ip': _session!.localIp,
      'port': _session!.port,
      'pin': _session!.pin,
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Откройте Akso на втором устройстве в той же сети Wi-Fi для мгновенной передачи чертежа:',
          style: TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),

        // Селектор сетевого интерфейса при наличии нескольких карт
        if (_interfaces.length > 1) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi, size: 16, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                const Text('Адаптер:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<QuickBridgeNetworkInterface>(
                      value: _selectedInterface,
                      isDense: true,
                      isExpanded: true,
                      items: _interfaces.map((iface) {
                        return DropdownMenuItem(
                          value: iface,
                          child: Text(
                            iface.displayName,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newIface) {
                        if (newIface != null && newIface != _selectedInterface) {
                          setState(() {
                            _selectedInterface = newIface;
                          });
                          _startSenderSession();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // QR-код
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 140.0,
              ),
            ),
            const SizedBox(width: 20),
            // Карточка PIN-кода и адреса
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PIN-код подключения:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _session!.pin.split('').join(' '),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: Colors.cyanAccent,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Код подключения:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _session!.connectionCode,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Скопировать код подключения',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _session!.connectionCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Код подключения скопирован в буфер обмена')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Маяк автообнаружения активен в сети Wi-Fi',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),

        // Резервный канал передачи файла
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Поделиться файлом (.akso)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: _shareProjectFile,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '💡 Если нет общего Wi-Fi, включите «Точку доступа» на планшете или передайте файл через Telegram/флешку.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildReceiverView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.radar, size: 16, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            const Text(
              'Поиск устройств в сети Wi-Fi...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Обновить', style: TextStyle(fontSize: 12)),
              onPressed: _startDiscovery,
            ),
          ],
        ),
        const SizedBox(height: 6),

        if (_discoveredHosts.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Устройства не найдены. Убедитесь, что оба устройства подключены к одному Wi-Fi (или точке доступа).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _discoveredHosts.length,
            itemBuilder: (ctx, idx) {
              final host = _discoveredHosts[idx];
              return Card(
                color: const Color(0xFF2A2A2A),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.devices, color: Colors.cyanAccent),
                  title: Text(host.hostName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${host.ip}:${host.port} • ${host.projectTitle}'),
                  trailing: ElevatedButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Скачать'),
                    onPressed: () {
                      if (host.pin != null) {
                        _downloadFromHost(host.ip, host.port, host.pin!);
                      } else {
                        _showPinPromptAndDownload(host.ip, host.port);
                      }
                    },
                  ),
                ),
              );
            },
          ),

        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 6),

        // Подключение по коду или адресу
        const Text(
          'Быстрое подключение по коду / адресу:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _connectionCodeController,
                decoration: InputDecoration(
                  hintText: '192.168.1.50:42424#1234 или IP',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste, size: 16),
                    tooltip: 'Вставить из буфера',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _connectionCodeController.text = data!.text!.trim();
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Скачать'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onPressed: _connectUsingCode,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Кнопка открыть файл
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Открыть полученный файл (.akso)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: _openProjectFile,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
