import 'package:flutter/material.dart';
import '../../../../domain/models/project_model.dart';
import '../../../canvas/input_controller.dart';

/// Диалог просмотра и редактирования реквизитов и свойств проекта
class ProjectPropertiesDialog extends StatefulWidget {
  final PipingInputController controller;

  const ProjectPropertiesDialog({
    super.key,
    required this.controller,
  });

  @override
  State<ProjectPropertiesDialog> createState() => _ProjectPropertiesDialogState();
}

class _ProjectPropertiesDialogState extends State<ProjectPropertiesDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _codeController;
  late final TextEditingController _addressController;
  late final TextEditingController _engineerController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.currentProject;
    _titleController = TextEditingController(text: p.title);
    _codeController = TextEditingController(text: p.projectCode);
    _addressController = TextEditingController(text: p.objectAddress);
    _engineerController = TextEditingController(text: p.engineerName);
    _notesController = TextEditingController(text: p.notes);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _engineerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    widget.controller.updateProjectMetadata(
      title: _titleController.text.trim(),
      projectCode: _codeController.text.trim(),
      objectAddress: _addressController.text.trim(),
      engineerName: _engineerController.text.trim(),
      notes: _notesController.text.trim(),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.currentProject;
    final filePath = widget.controller.currentFilePath;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.assignment_outlined, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('Свойства проекта', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Название проекта',
                  hintText: 'Например: Узел учета тепла',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Шифр / Марка',
                        hintText: 'ТХ-01, ОВ-12',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.tag, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _engineerController,
                      decoration: const InputDecoration(
                        labelText: 'Разработал / Инженер',
                        hintText: 'Иванов И.И.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Объект / Адрес строительства',
                  hintText: 'г. Москва, Цех №2',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Примечания к чертежу',
                  hintText: 'Особые указания по монтажу, клеймам, сварке...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes, size: 20),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.folder_open, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            filePath != null ? filePath : 'Файл еще не сохранен на диске',
                            style: TextStyle(
                              fontSize: 12,
                              color: filePath != null ? null : Colors.orangeAccent,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                              'Создан: ${p.creationDate}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.update, size: 14, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                              'Изменен: ${_formatLastModified(p.lastModifiedDate)}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Сохранить'),
          onPressed: _save,
        ),
      ],
    );
  }

  String _formatLastModified(String dateStr) {
    if (dateStr.length >= 16) {
      // 2026-09-18T16:00:00 -> 2026-09-18 16:00
      return dateStr.substring(0, 16).replaceAll('T', ' ');
    }
    return dateStr;
  }
}
