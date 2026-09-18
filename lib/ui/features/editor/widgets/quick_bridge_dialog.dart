import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../data/services/quick_bridge_service.dart';
import '../../../../domain/models/project_model.dart';
import '../../../canvas/input_controller.dart';

/// Диалог быстрого обмена проектами Akso между ПК и планшетом по Wi-Fi
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
  bool _isSenderMode = true;
  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;

  // Режим приема: обнаруженные хосты
  final List<QuickBridgeDiscoveredHost> _discoveredHosts = [];
  StreamSubscription<QuickBridgeDiscoveredHost>? _discoverySub;

  // Ручной ввод
  final _manualIpController = TextEditingController();
  final _manualPortController = TextEditingController();
  final _manualPinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridgeService ?? QuickBridgeService();
    if (widget.initialSession != null) {
      _session = widget.initialSession;
    } else {
      _startSenderSession();
    }
  }

  @override
  void dispose() {
    _session?.stop();
    _discoverySub?.cancel();
    _manualIpController.dispose();
    _manualPortController.dispose();
    _manualPinController.dispose();
    super.dispose();
  }

  Future<void> _startSenderSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _session = await _bridge.startSender(
        project: widget.controller.currentProject.copyWith(
          network: widget.controller.network,
          lastModifiedDate: DateTime.now().toIso8601String(),
        ),
        enableBeacon: widget.enableBeacon,
        onTransferred: (clientIp) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Проект успешно передан на устройство ($clientIp)!';
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
      _errorMessage = 'Не удалось запустить сервер: $e';
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
    _discoverySub = _bridge.discoverHosts(timeout: const Duration(seconds: 10)).listen((host) {
      if (mounted) {
        setState(() {
          if (!_discoveredHosts.contains(host)) {
            _discoveredHosts.add(host);
          }
        });
      }
    });
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
        _applyReceivedProject(project);
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

  Future<void> _uploadToHost(String ip, int port, String pin) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Отправка проекта на $ip:$port...';
    });

    try {
      final current = widget.controller.currentProject.copyWith(
        network: widget.controller.network,
        lastModifiedDate: DateTime.now().toIso8601String(),
      );
      await _bridge.uploadProject(
        hostIp: ip,
        port: port,
        pin: pin,
        project: current,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Проект успешно отправлен на компьютер!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _applyReceivedProject(ProjectModel project) {
    widget.controller.currentProject = project;
    widget.controller.network = project.network;
    widget.controller.currentFilePath = null;
    widget.controller.hasUnsavedChanges = false;
    widget.controller.history.clear();
    widget.controller.history.recordState(widget.controller.network);
    widget.controller.cancelCurrentOperation(keepTool: false);
    widget.controller.refresh();

    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Проект "${project.title}" успешно получен по Wi-Fi!'),
        backgroundColor: Colors.green.shade800,
      ),
    );
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
              // Переключатель режимов: Отправить vs Принять
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Отправить (ПК)'),
                    icon: Icon(Icons.upload, size: 16),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Принять (Планшет)'),
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
      return const Text('Инициализация точки передачи...');
    }

    final qrPayload = jsonEncode({
      'app': 'akso',
      'ip': _session!.localIp,
      'port': _session!.port,
      'pin': _session!.pin,
    });

    return Column(
      children: [
        const Text(
          'Откройте Akso на планшете в той же сети Wi-Fi для мгновенной передачи чертежа:',
          style: TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
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
            const SizedBox(width: 24),
            // Карточка PIN-кода и адреса
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PIN-код подключения:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    _session!.pin.split('').join(' '),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Colors.cyanAccent,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${_session!.localIp}:${_session!.port}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 14),
                      tooltip: 'Скопировать URL',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _session!.serverUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL скопирован в буфер обмена')),
                        );
                      },
                    ),
                  ],
                ),
              ],
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
              'Маяк автообнаружения активен в локальной сети',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReceiverView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Поиск устройств в сети Wi-Fi...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Обновить поиск',
              onPressed: _startDiscovery,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_discoveredHosts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Устройства не найдены. Убедитесь, что ПК и планшет подключены к одному Wi-Fi (или точке доступа).',
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
                  leading: const Icon(Icons.computer, color: Colors.cyanAccent),
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

        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Подключиться вручную',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _manualIpController,
                decoration: const InputDecoration(
                  labelText: 'IP хоста',
                  hintText: '192.168.1.50',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _manualPortController,
                decoration: const InputDecoration(
                  labelText: 'Порт',
                  hintText: '8080',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _manualPinController,
                decoration: const InputDecoration(
                  labelText: 'PIN-код',
                  hintText: '4 цифры',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Скачать проект с ПК'),
                onPressed: () {
                  final ip = _manualIpController.text.trim();
                  final port = int.tryParse(_manualPortController.text.trim()) ?? 0;
                  final pin = _manualPinController.text.trim();
                  if (ip.isNotEmpty && port > 0 && pin.isNotEmpty) {
                    _downloadFromHost(ip, port, pin);
                  } else {
                    setState(() {
                      _errorMessage = 'Введите корректный IP, порт и PIN-код';
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload, size: 18),
                label: const Text('Отправить на ПК'),
                onPressed: () {
                  final ip = _manualIpController.text.trim();
                  final port = int.tryParse(_manualPortController.text.trim()) ?? 0;
                  final pin = _manualPinController.text.trim();
                  if (ip.isNotEmpty && port > 0 && pin.isNotEmpty) {
                    _uploadToHost(ip, port, pin);
                  } else {
                    setState(() {
                      _errorMessage = 'Введите корректный IP, порт и PIN-код';
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showPinPromptAndDownload(String ip, int port) async {
    final pinController = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Введите PIN-код'),
        content: TextField(
          controller: pinController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '4-значный код с экрана ПК',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(pinController.text.trim()), child: const Text('ОК')),
        ],
      ),
    );

    if (pin != null && pin.isNotEmpty) {
      _downloadFromHost(ip, port, pin);
    }
  }
}
