import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/math/axonometry_projector.dart';
import '../../../../data/dxf/dxf_writer.dart';
import '../../../../domain/enums/dxf_callout_options.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../../domain/models/piping_network.dart';
import '../../../../domain/models/drawing_sheet.dart';

class DxfExportDialog extends StatefulWidget {
  final PipingNetwork network;
  final ProjectionType currentProjection;
  final AxonometryProjector? activeProjector;
  final Map<String, String>? calloutTemplates;
  final List<DrawingSheet>? sheets;

  const DxfExportDialog({
    super.key,
    required this.network,
    required this.currentProjection,
    this.activeProjector,
    this.calloutTemplates,
    this.sheets,
  });

  @override
  State<DxfExportDialog> createState() => _DxfExportDialogState();
}

class _DxfExportDialogState extends State<DxfExportDialog> {
  bool is3dMode = false;
  late ProjectionType selectedProjection;
  DxfCalloutType selectedCalloutType = DxfCalloutType.monolithicBlock;
  DxfCalloutOrientation selectedCalloutOrientation = DxfCalloutOrientation.cameraFacing;
  String statusMessage = '';
  String? exportedFilePath;

  @override
  void initState() {
    super.initState();
    selectedProjection = widget.currentProjection;
  }

  Future<void> _exportDxf() async {
    try {
      final String dxfContent;
      final String fileName;

      if (is3dMode) {
        dxfContent = DxfWriter.generate3dDxf(
          widget.network,
          calloutTemplates: widget.calloutTemplates,
          calloutType: selectedCalloutType,
          calloutOrientation: selectedCalloutOrientation,
          activeProjector: widget.activeProjector,
        );
        fileName = 'akso_scheme_3d.dxf';
      } else if (widget.sheets != null && widget.sheets!.isNotEmpty) {
        dxfContent = DxfWriter.generate2dGostAxonometryWithLayoutsDxf(
          network: widget.network,
          sheets: widget.sheets!,
          projection: selectedProjection,
          activeProjector: selectedProjection == widget.currentProjection ? widget.activeProjector : null,
          calloutTemplates: widget.calloutTemplates,
        );
        fileName = 'akso_scheme_${selectedProjection.name}_layouts.dxf';
      } else {
        dxfContent = DxfWriter.generate2dGostAxonometryDxf(
          widget.network,
          projection: selectedProjection,
          activeProjector: selectedProjection == widget.currentProjection ? widget.activeProjector : null,
          calloutTemplates: widget.calloutTemplates,
        );
        fileName = 'akso_scheme_${selectedProjection.name}_2d.dxf';
      }

      final String? scrContent;
      const scrFileName = 'akso_scheme_3d_mleaders.scr';
      if (is3dMode && selectedCalloutType == DxfCalloutType.mleaderScript) {
        scrContent = DxfWriter.generateMleaderScript(
          widget.network,
          calloutTemplates: widget.calloutTemplates,
          calloutOrientation: selectedCalloutOrientation,
          activeProjector: widget.activeProjector,
        );
      } else {
        scrContent = null;
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // На мобильных/планшетах сохраняем во временный каталог и вызываем системный Share
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(dxfContent);

        final filesToShare = [XFile(file.path)];
        if (scrContent != null) {
          final scrFile = File('${dir.path}/$scrFileName');
          await scrFile.writeAsString(scrContent);
          filesToShare.add(XFile(scrFile.path));
        }

        await SharePlus.instance.share(
          ShareParams(
            files: filesToShare,
            subject: 'Исполнительная схема $fileName',
            text: 'Экспорт схемы трубопроводов Akso в AutoCAD DXF',
          ),
        );

        setState(() {
          statusMessage = scrContent != null
              ? 'Файлы $fileName и $scrFileName готовы к отправке!'
              : 'Файл $fileName готов к отправке!';
          exportedFilePath = file.path;
        });
      } else {
        // На десктопе даем пользователю выбрать путь
        String? targetPath;
        bool userCancelled = false;
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
            targetPath = uri.scheme == 'file' ? uri.toFilePath() : (uri.path.isNotEmpty ? uri.path : uri.toString());
          } else {
            userCancelled = true;
          }
        } catch (_) {
          targetPath = null;
        }

        if (userCancelled) {
          setState(() {
            statusMessage = 'Экспорт отменен';
          });
          return;
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

        String? scrSavedPath;
        if (scrContent != null) {
          final parentDir = file.parent.path;
          final scrPath = '$parentDir/$scrFileName';
          final scrFile = File(scrPath);
          await scrFile.writeAsString(scrContent);
          scrSavedPath = scrPath;
        }

        setState(() {
          if (scrSavedPath != null) {
            statusMessage = 'Файлы сохранены:\n• $targetPath\n• $scrSavedPath\n(Перетащите .scr в AutoCAD для создания нативных МВЫНОСОК)';
          } else {
            statusMessage = 'Файл сохранен: $targetPath';
          }
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
        width: 500,
        child: SingleChildScrollView(
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
                              value: ProjectionType.orbit3d,
                              child: Text('Текущий 3D-ракурс (с орбиты камеры)'),
                            ),
                            DropdownMenuItem(
                              value: ProjectionType.topPlan2d,
                              child: Text('План сверху (2D вид X, Y)'),
                            ),
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
                    if (is3dMode)
                      Padding(
                        padding: const EdgeInsets.only(left: 32, right: 8, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Тип выносок в AutoCAD:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            DropdownButton<DxfCalloutType>(
                              value: selectedCalloutType,
                              isExpanded: true,
                              items: DxfCalloutType.values.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(type.displayName, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => selectedCalloutType = val!),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 4, bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      selectedCalloutType.description,
                                      style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Ракурс / Положение выносок в 3D:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            DropdownButton<DxfCalloutOrientation>(
                              value: selectedCalloutOrientation,
                              isExpanded: true,
                              items: DxfCalloutOrientation.values.map((ori) {
                                return DropdownMenuItem(
                                  value: ori,
                                  child: Text(ori.displayName, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => selectedCalloutOrientation = val!),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Выноски поворачиваются по оси Z и ориентируются в сторону выбранного ракурса.',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
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
                ? DxfWriter.generate3dDxf(
                    widget.network,
                    calloutTemplates: widget.calloutTemplates,
                    calloutType: selectedCalloutType,
                    calloutOrientation: selectedCalloutOrientation,
                    activeProjector: widget.activeProjector,
                  )
                : DxfWriter.generate2dGostAxonometryDxf(
                    widget.network,
                    projection: selectedProjection,
                    activeProjector: selectedProjection == widget.currentProjection ? widget.activeProjector : null,
                    calloutTemplates: widget.calloutTemplates,
                  );
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
