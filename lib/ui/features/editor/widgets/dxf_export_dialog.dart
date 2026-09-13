import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../data/dxf/dxf_writer.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../../domain/models/piping_network.dart';

class DxfExportDialog extends StatefulWidget {
  final PipingNetwork network;
  final ProjectionType currentProjection;
  final Map<String, String>? calloutTemplates;

  const DxfExportDialog({
    super.key,
    required this.network,
    required this.currentProjection,
    this.calloutTemplates,
  });

  @override
  State<DxfExportDialog> createState() => _DxfExportDialogState();
}

class _DxfExportDialogState extends State<DxfExportDialog> {
  bool is3dMode = false;
  late ProjectionType selectedProjection;
  String statusMessage = '';
  String? exportedFilePath;

  @override
  void initState() {
    super.initState();
    selectedProjection = widget.currentProjection == ProjectionType.orbit3d
        ? ProjectionType.gostFrontal45
        : widget.currentProjection;
  }

  Future<void> _exportDxf() async {
    try {
      final String dxfContent;
      final String fileName;

      if (is3dMode) {
        dxfContent = DxfWriter.generate3dDxf(widget.network, calloutTemplates: widget.calloutTemplates);
        fileName = 'akso_scheme_3d.dxf';
      } else {
        dxfContent = DxfWriter.generate2dGostAxonometryDxf(
          widget.network,
          projection: selectedProjection,
          calloutTemplates: widget.calloutTemplates,
        );
        fileName = 'akso_scheme_gost_2d.dxf';
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // На мобильных/планшетах сохраняем во временный каталог и вызываем системный Share
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(dxfContent);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: 'Исполнительная схема $fileName',
            text: 'Экспорт схемы трубопроводов Akso в AutoCAD DXF',
          ),
        );

        setState(() {
          statusMessage = 'Файл $fileName готов к отправке!';
          exportedFilePath = file.path;
        });
      } else {
        // На десктопе даем пользователю выбрать путь
        String? targetPath;
        try {
          final bytes = Uint8List.fromList(utf8.encode(dxfContent));
          final uri = await FilePicker.saveFile(
            dialogTitle: 'Сохранить чертеж AutoCAD (DXF)',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['dxf'],
            bytes: bytes,
          );
          if (uri != null) {
            targetPath = uri.toFilePath();
          }
        } catch (_) {
          targetPath = null;
        }

        if (targetPath == null) {
          final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
          targetPath = '${dir.path}/$fileName';
        }

        if (!targetPath.toLowerCase().endsWith('.dxf')) {
          targetPath = '$targetPath.dxf';
        }

        final file = File(targetPath);
        await file.writeAsString(dxfContent);

        setState(() {
          statusMessage = 'Файл сохранен: $targetPath';
          exportedFilePath = targetPath;
        });
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Ошибка экспорта: $e';
      });
    }
  }

  void _openFileLocation() {
    final path = exportedFilePath;
    if (path == null) return;
    if (Platform.isWindows) {
      Process.run('explorer.exe', ['/select,', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [File(path).parent.path]);
    }
  }

  void _openWithCad() {
    final path = exportedFilePath;
    if (path == null) return;
    if (Platform.isWindows) {
      Process.run('cmd.exe', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.file_download, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('Экспорт в AutoCAD (DXF)'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите вариант экспорта для AutoCAD / nanoCAD / Revit:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            RadioGroup<bool>(
              groupValue: is3dMode,
              onChanged: (val) => setState(() => is3dMode = val ?? false),
              child: Column(
                children: [
                  const RadioListTile<bool>(
                    value: false,
                    title: Text('Плоская схема в аксонометрии ГОСТ / СПДС (2D DXF)'),
                    subtitle: Text(
                      'Готовый к печати чертеж с выносками сварки, клеймами, отметками ∇ и диаметрами на отдельных слоях',
                    ),
                  ),
                  if (!is3dMode)
                    Padding(
                      padding: const EdgeInsets.only(left: 32, bottom: 8),
                      child: DropdownButton<ProjectionType>(
                        value: selectedProjection,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: ProjectionType.gostFrontal45,
                            child: Text('ГОСТ 21.602 Фронтальная 45° (k=0.5)'),
                          ),
                          DropdownMenuItem(
                            value: ProjectionType.gostMirrored45,
                            child: Text('ГОСТ Зеркальная 45° (разворот взгляда)'),
                          ),
                          DropdownMenuItem(
                            value: ProjectionType.iso30,
                            child: Text('ISO Прямоугольная изометрия 30°'),
                          ),
                        ],
                        onChanged: (p) => setState(() => selectedProjection = p!),
                      ),
                    ),
                  const RadioListTile<bool>(
                    value: true,
                    title: Text('Пространственная 3D-модель (3D DXF)'),
                    subtitle: Text(
                      'Реальные координаты (X, Y, Z). Открывается в AutoCAD 3D или подгружается как семейство/подложка в Revit',
                    ),
                  ),
                ],
              ),
            ),
            if (statusMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  statusMessage,
                  style: TextStyle(color: Colors.green.shade900, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (exportedFilePath != null && !kIsWeb) ...[
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Показать в папке'),
            onPressed: _openFileLocation,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
            label: const Text('Открыть в AutoCAD'),
            onPressed: _openWithCad,
          ),
        ],
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Копировать'),
          onPressed: () {
            final content = is3dMode
                ? DxfWriter.generate3dDxf(widget.network, calloutTemplates: widget.calloutTemplates)
                : DxfWriter.generate2dGostAxonometryDxf(widget.network, projection: selectedProjection, calloutTemplates: widget.calloutTemplates);
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('DXF скопирован в буфер обмена')),
            );
          },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Экспортировать файл'),
          onPressed: _exportDxf,
        ),
        TextButton(
          child: const Text('Закрыть'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
