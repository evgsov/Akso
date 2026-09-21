import 'package:flutter/material.dart';
import '../../../../domain/models/drawing_sheet.dart';
import '../../../../domain/models/title_block_data.dart';
import '../../../canvas/input_controller.dart';

/// Диалог редактирования основной надписи (штампа) чертежного листа по ГОСТ 21.101-2020
class TitleBlockEditorDialog extends StatefulWidget {
  final PipingInputController controller;
  final DrawingSheet sheet;

  const TitleBlockEditorDialog({
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
      barrierDismissible: false,
      builder: (ctx) => TitleBlockEditorDialog(controller: controller, sheet: sheet),
    );
  }

  @override
  State<TitleBlockEditorDialog> createState() => _TitleBlockEditorDialogState();
}

class _TitleBlockEditorDialogState extends State<TitleBlockEditorDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Основные данные
  late TextEditingController _projectNameController;
  late TextEditingController _buildingNameController;
  late TextEditingController _drawingTitleController;
  late TextEditingController _documentCodeController;
  late TextEditingController _organizationController;
  late TextEditingController _stageController;
  late TextEditingController _scaleTextController;
  late int _sheetNumber;
  late int _totalSheets;

  // Согласования
  final Map<String, TextEditingController> _approvalNames = {};
  final Map<String, TextEditingController> _approvalDates = {};
  final List<String> _standardRoles = [
    'Геодезист',
    'Исп. директор',
    'Мастер / Прораб',
    'Нач. участка',
    'ПТО',
    'Разраб.',
    'Пров.',
    'ГИП',
    'Н.контр.',
    'Утв.',
  ];

  // Правый верхний угол (Приложение к акту / Графа 26)
  late TopRightCornerMode _cornerMode;
  late TextEditingController _cornerTextController;

  // Архивные графы
  late TextEditingController _invPrimaryController;
  late TextEditingController _invDatePrimaryController;
  late TextEditingController _invReplacedController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final tb = widget.sheet.titleBlockData;

    _projectNameController = TextEditingController(text: tb.projectName);
    _buildingNameController = TextEditingController(text: tb.buildingName);
    _drawingTitleController = TextEditingController(text: tb.drawingTitle);
    _documentCodeController = TextEditingController(text: tb.documentCode);
    _organizationController = TextEditingController(text: tb.organization);
    _stageController = TextEditingController(text: tb.stage);
    _scaleTextController = TextEditingController(text: tb.scaleText);
    _sheetNumber = tb.sheetNumber;
    _totalSheets = tb.totalSheets;

    final allRoles = List<String>.from(_standardRoles);
    for (final a in tb.approvals) {
      if (a.role.isNotEmpty && !allRoles.contains(a.role)) {
        allRoles.add(a.role);
      }
    }

    for (final role in allRoles) {
      final app = tb.approvals.firstWhere((a) => a.role == role, orElse: () => TitleBlockApproval(role: role, name: ''));
      _approvalNames[role] = TextEditingController(text: app.name);
      _approvalDates[role] = TextEditingController(text: app.date);
    }

    _cornerMode = tb.topRightCorner.mode;
    _cornerTextController = TextEditingController(text: tb.topRightCorner.text);

    _invPrimaryController = TextEditingController(text: tb.archive.invNumberPrimary);
    _invDatePrimaryController = TextEditingController(text: tb.archive.invDatePrimary);
    _invReplacedController = TextEditingController(text: tb.archive.invNumberReplaced);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _projectNameController.dispose();
    _buildingNameController.dispose();
    _drawingTitleController.dispose();
    _documentCodeController.dispose();
    _organizationController.dispose();
    _stageController.dispose();
    _scaleTextController.dispose();
    for (final c in _approvalNames.values) {
      c.dispose();
    }
    for (final c in _approvalDates.values) {
      c.dispose();
    }
    _cornerTextController.dispose();
    _invPrimaryController.dispose();
    _invDatePrimaryController.dispose();
    _invReplacedController.dispose();
    super.dispose();
  }

  void _save() {
    final approvals = <TitleBlockApproval>[];
    for (final role in _approvalNames.keys) {
      final name = _approvalNames[role]?.text.trim() ?? '';
      final date = _approvalDates[role]?.text.trim() ?? '';
      if (name.isNotEmpty || date.isNotEmpty) {
        approvals.add(TitleBlockApproval(role: role, name: name, date: date));
      }
    }

    final updatedTb = widget.sheet.titleBlockData.copyWith(
      projectName: _projectNameController.text.trim(),
      buildingName: _buildingNameController.text.trim(),
      drawingTitle: _drawingTitleController.text.trim(),
      documentCode: _documentCodeController.text.trim(),
      organization: _organizationController.text.trim(),
      stage: _stageController.text.trim(),
      scaleText: _scaleTextController.text.trim(),
      sheetNumber: _sheetNumber,
      totalSheets: _totalSheets,
      approvals: approvals,
      topRightCorner: TopRightCornerBlock(
        mode: _cornerMode,
        text: _cornerTextController.text.trim(),
      ),
      archive: TitleBlockArchive(
        invNumberPrimary: _invPrimaryController.text.trim(),
        invDatePrimary: _invDatePrimaryController.text.trim(),
        invNumberReplaced: _invReplacedController.text.trim(),
      ),
    );

    widget.controller.updateSheet(widget.sheet.copyWith(titleBlockData: updatedTb));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B), // Dark slate
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 700,
        height: 600,
        child: Column(
          children: [
            // Заголовок диалога
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.cyanAccent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Основная надпись по ГОСТ 21.101 (${widget.sheet.name})',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Вкладки
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.cyanAccent,
              labelColor: Colors.cyanAccent,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(text: 'Основные графы'),
                Tab(text: 'Согласования'),
                Tab(text: 'Приложение к акту'),
                Tab(text: 'Архив и подшивка'),
              ],
            ),

            // Содержимое вкладок
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralTab(),
                  _buildApprovalsTab(),
                  _buildTopRightCornerTab(),
                  _buildArchiveTab(),
                ],
              ),
            ),

            // Нижняя панель действий
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            controller: _projectNameController,
            label: 'Наименование объекта строительства (Графа 1)',
            hint: 'например, Установка подготовки нефти УПН-200',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _buildingNameController,
            label: 'Наименование здания / сооружения (Графа 2)',
            hint: 'например, Блок технологический БТ-1',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _drawingTitleController,
            label: 'Наименование схемы / чертежа (Графа 3)',
            hint: 'например, Схема технологических трубопроводов В1',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _documentCodeController,
                  label: 'Обозначение документа / Шифр проекта (Графа 4)',
                  hint: 'например, 04-2026-ТХ.ИС',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 1,
                child: _buildTextField(
                  controller: _stageController,
                  label: 'Стадия (Графа 6)',
                  hint: 'И, Р или П',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _organizationController,
                  label: 'Наименование организации (Графа 5)',
                  hint: 'например, ООО "НефтеГазМонтаж"',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildTextField(
                  controller: _scaleTextController,
                  label: 'Масштаб чертежа',
                  hint: 'например, М 1:50',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Фамилии и даты подписей ответственных лиц (Графы 10, 11, 13)',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          for (final role in _approvalNames.keys) ...[
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    role,
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _approvalNames[role],
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Фамилия И.О.',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _approvalDates[role],
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Дата (09.26)',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildTopRightCornerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Оформление правого верхнего угла чертежа (Графа 26 / АОСР)',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<TopRightCornerMode>(
            initialValue: _cornerMode,
            dropdownColor: const Color(0xFF1E293B),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Режим отображения',
              labelStyle: const TextStyle(color: Colors.white70),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            items: const [
              DropdownMenuItem(
                value: TopRightCornerMode.actAttachment,
                child: Text('Приложение к Акту освидетельствования (АОСР)'),
              ),
              DropdownMenuItem(
                value: TopRightCornerMode.documentCodeRotated,
                child: Text('Шифр документа (ГОСТ 21.101 Графа 26)'),
              ),
              DropdownMenuItem(
                value: TopRightCornerMode.customText,
                child: Text('Произвольный пользовательский текст'),
              ),
              DropdownMenuItem(
                value: TopRightCornerMode.none,
                child: Text('Не отображать блок'),
              ),
            ],
            onChanged: (mode) {
              if (mode != null) {
                setState(() => _cornerMode = mode);
              }
            },
          ),
          const SizedBox(height: 16),
          if (_cornerMode != TopRightCornerMode.none) ...[
            TextField(
              controller: _cornerTextController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Текст в верхнем правом углу',
                labelStyle: const TextStyle(color: Colors.white70),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Быстрые шаблоны:', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Приложение к АОСР №...'),
                  onPressed: () {
                    _cornerTextController.text =
                        'Приложение №1\nк Акту освидетельствования скрытых работ\n№ ___ от "___" ________ 2026 г.';
                  },
                ),
                ActionChip(
                  label: const Text('Приложение к Акту испытаний'),
                  onPressed: () {
                    _cornerTextController.text =
                        'Приложение к Акту гидростатического\nиспытания на прочность и плотность\n№ ___ от "___" ________ 2026 г.';
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArchiveTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Архивные графы для поля подшивки (левое поле 20 мм)',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _invPrimaryController,
            label: 'Инв. № подл. (Инвентарный номер подлинника)',
            hint: 'например, 1428/26',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _invDatePrimaryController,
            label: 'Подпись и дата архива',
            hint: 'например, 15.09.26',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _invReplacedController,
            label: 'Взам. инв. № (Взамен инвентарного номера)',
            hint: 'например, 1102/25',
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
