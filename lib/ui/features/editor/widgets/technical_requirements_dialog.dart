import 'package:flutter/material.dart';
import '../../../../domain/models/drawing_sheet.dart';
import '../../../canvas/input_controller.dart';

/// Диалог настройки и редактирования блока Технических требований (ТТ) чертежа
class TechnicalRequirementsDialog extends StatefulWidget {
  final PipingInputController controller;
  final DrawingSheet sheet;

  const TechnicalRequirementsDialog({
    super.key,
    required this.controller,
    required this.sheet,
  });

  static Future<void> show(BuildContext context, {
    required PipingInputController controller,
    required DrawingSheet sheet,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => TechnicalRequirementsDialog(controller: controller, sheet: sheet),
    );
  }

  @override
  State<TechnicalRequirementsDialog> createState() => _TechnicalRequirementsDialogState();
}

class _TechnicalRequirementsDialogState extends State<TechnicalRequirementsDialog> {
  late TextEditingController _textController;

  static const List<String> _standardTemplates = [
    '1. Сварные соединения трубопроводов выполнить по ГОСТ 16037-80.',
    '2. Контроль качества сварных соединений выполнить методами ВИК 100%, РК (УЗК) в объеме согласно проектной документации и СП 75.13330.',
    '3. Трубопровод испытать на прочность и плотность гидравлическим давлением Рисп = 1.5 Рраб, но не менее 0.2 МПа.',
    '4. Опоры и подвески трубопроводов выполнить по ГОСТ 14911-82 (ОСТ 36-146-88).',
    '5. Антикоррозийную защиту выполнить грунтовкой ГФ-021 по ГОСТ 25129-82 в 2 слоя.',
    '6. Уклоны трубопроводов выдержать не менее 0.002 в сторону спускных устройств.',
  ];

  @override
  void initState() {
    super.initState();
    final currentText = widget.sheet.technicalRequirements?.text ?? '';
    _textController = TextEditingController(text: currentText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _appendTemplate(String template) {
    if (_textController.text.trim().isEmpty) {
      _textController.text = template;
    } else {
      _textController.text = '${_textController.text.trimRight()}\n$template';
    }
  }

  void _save() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      widget.controller.updateActiveSheetTechnicalRequirements(null);
    } else {
      final tr = (widget.sheet.technicalRequirements ?? const TechnicalRequirements(text: '')).copyWith(
        text: text,
      );
      widget.controller.updateActiveSheetTechnicalRequirements(tr);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 650,
        height: 550,
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notes, color: Colors.cyanAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Технические требования (ТТ)',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Тело диалога
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Текст примечаний (размещается над основной надписью шириной 185 мм):',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                        decoration: InputDecoration(
                          hintText: 'Введите пункты технических требований...',
                          hintStyle: const TextStyle(color: Colors.white30),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Быстрые пункты из библиотеки:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (int i = 0; i < _standardTemplates.length; i++)
                          ActionChip(
                            label: Text('Пункт ${i + 1}'),
                            tooltip: _standardTemplates[i],
                            backgroundColor: const Color(0xFF334155),
                            labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                            onPressed: () => _appendTemplate(_standardTemplates[i]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Действия
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _textController.clear(),
                    child: const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Применить'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.cyan.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
