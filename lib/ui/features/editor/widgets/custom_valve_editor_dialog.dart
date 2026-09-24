import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/math/axonometry_projector.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../../domain/enums/valve_type.dart';
import '../../../../domain/models/custom_valve_definition.dart';
import '../../../../domain/models/node_3d.dart';
import '../../../../domain/models/valve.dart';
import '../../../../domain/services/custom_valve_catalog.dart';
import '../../../../domain/services/element_3d_geometry.dart';
import '../../../canvas/valve_symbol_painter.dart';

const _uuid = Uuid();

enum _EditorPreviewMode {
  plan2d,
  gost45,
  iso30,
}

class _QuickPreset {
  final String name;
  final String label;
  final IconData icon;
  final String description;
  final Valve3dBodyShape bodyShape;
  final ValveWingFillStyle leftWing;
  final ValveWingFillStyle rightWing;
  final ValveDividerType divider;
  final ValveStemSymbolType stem;
  final String stemText;
  final bool isFlanged;
  final double lengthFactor;
  final double minLength;

  const _QuickPreset({
    required this.name,
    required this.label,
    required this.icon,
    required this.description,
    required this.bodyShape,
    this.leftWing = ValveWingFillStyle.outline,
    this.rightWing = ValveWingFillStyle.outline,
    this.divider = ValveDividerType.none,
    this.stem = ValveStemSymbolType.handwheel,
    this.stemText = '',
    this.isFlanged = false,
    this.lengthFactor = 1.5,
    this.minLength = 100.0,
  });
}

const List<_QuickPreset> _kQuickPresets = [
  _QuickPreset(
    name: 'Задвижка клиновая',
    label: 'Задвижка',
    icon: Icons.straighten,
    description: 'Задвижка клиновая фланцевая с ручным маховиком',
    bodyShape: Valve3dBodyShape.doubleCones,
    isFlanged: true,
    stem: ValveStemSymbolType.handwheel,
    lengthFactor: 1.5,
    minLength: 120.0,
  ),
  _QuickPreset(
    name: 'Кран шаровой',
    label: 'Кран шаровой',
    icon: Icons.radio_button_checked,
    description: 'Кран шаровой муфтовый/приварной с поворотным рычагом',
    bodyShape: Valve3dBodyShape.doubleCones,
    divider: ValveDividerType.circle,
    stem: ValveStemSymbolType.lever,
    isFlanged: false,
    lengthFactor: 1.3,
    minLength: 90.0,
  ),
  _QuickPreset(
    name: 'Затвор дисковый (баттерфляй)',
    label: 'Затвор',
    icon: Icons.disc_full,
    description: 'Затвор дисковый поворотный межфланцевый',
    bodyShape: Valve3dBodyShape.doubleCones,
    divider: ValveDividerType.line,
    stem: ValveStemSymbolType.lever,
    isFlanged: true,
    lengthFactor: 1.1,
    minLength: 70.0,
  ),
  _QuickPreset(
    name: 'Клапан обратный',
    label: 'Клапан обр.',
    icon: Icons.arrow_forward,
    description: 'Клапан обратный поворотный со стрелкой направления потока',
    bodyShape: Valve3dBodyShape.doubleCones,
    leftWing: ValveWingFillStyle.outline,
    rightWing: ValveWingFillStyle.solid,
    divider: ValveDividerType.arrow,
    stem: ValveStemSymbolType.none,
    isFlanged: false,
    lengthFactor: 1.2,
    minLength: 90.0,
  ),
  _QuickPreset(
    name: 'Фильтр сетчатый (грязевик)',
    label: 'Фильтр',
    icon: Icons.filter_alt,
    description: 'Фильтр-грязевик сетчатый в цилиндрическом корпусе с наклонной сеткой',
    bodyShape: Valve3dBodyShape.cylinder,
    leftWing: ValveWingFillStyle.outline,
    rightWing: ValveWingFillStyle.hatched,
    divider: ValveDividerType.slantedDisc,
    stem: ValveStemSymbolType.none,
    isFlanged: true,
    lengthFactor: 1.4,
    minLength: 110.0,
  ),
  _QuickPreset(
    name: 'Виброкомпенсатор',
    label: 'Компенсатор',
    icon: Icons.waves,
    description: 'Антивибрационный сильфонный компенсатор с гофрированным корпусом',
    bodyShape: Valve3dBodyShape.bellows,
    leftWing: ValveWingFillStyle.hatched,
    rightWing: ValveWingFillStyle.hatched,
    divider: ValveDividerType.zigzag,
    stem: ValveStemSymbolType.boxWithText,
    stemText: 'АВ',
    isFlanged: true,
    lengthFactor: 1.5,
    minLength: 120.0,
  ),
  _QuickPreset(
    name: 'Редуктор давления',
    label: 'Редуктор',
    icon: Icons.speed,
    description: 'Регулятор давления прямого действия с мембранным блоком (М)',
    bodyShape: Valve3dBodyShape.doubleCones,
    stem: ValveStemSymbolType.diaphragm,
    stemText: 'М',
    isFlanged: false,
    lengthFactor: 1.6,
    minLength: 130.0,
  ),
  _QuickPreset(
    name: 'Задвижка с электроприводом',
    label: 'Электропривод',
    icon: Icons.bolt,
    description: 'Задвижка с блоком электрического привода (Э)',
    bodyShape: Valve3dBodyShape.doubleCones,
    divider: ValveDividerType.slantedDisc,
    stem: ValveStemSymbolType.boxWithText,
    stemText: 'Э',
    isFlanged: true,
    lengthFactor: 1.8,
    minLength: 140.0,
  ),
  _QuickPreset(
    name: 'Манометр технический (КИПиА)',
    label: 'КИПиА',
    icon: Icons.tune,
    description: 'Манометр показывающий с трехходовым краном',
    bodyShape: Valve3dBodyShape.cylinder,
    stem: ValveStemSymbolType.boxWithText,
    stemText: 'МП',
    isFlanged: false,
    lengthFactor: 1.0,
    minLength: 60.0,
  ),
];

/// Интерактивная студия создания и редактирования пользовательских семейств арматуры
/// с поддержкой всех форм корпуса (конусы, цилиндр, сильфон, сфера) и живым предпросмотром.
class CustomValveEditorDialog extends StatefulWidget {
  final CustomValveDefinition? initialDefinition;

  const CustomValveEditorDialog({
    super.key,
    this.initialDefinition,
  });

  @override
  State<CustomValveEditorDialog> createState() => _CustomValveEditorDialogState();
}

class _CustomValveEditorDialogState extends State<CustomValveEditorDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _stemTextController;
  late TextEditingController _minLengthController;

  late Valve3dBodyShape _bodyShape;
  late ValveWingFillStyle _leftWingStyle;
  late ValveWingFillStyle _rightWingStyle;
  late ValveDividerType _dividerType;
  late ValveStemSymbolType _stemType;
  late bool _hasBodyFlanges;

  late double _defaultLengthFactor;
  late double _stemHeightRatio;
  late double _actuatorSizeRatio;

  _EditorPreviewMode _previewMode = _EditorPreviewMode.plan2d;
  bool _isDarkTheme = true;

  @override
  void initState() {
    super.initState();
    final init = widget.initialDefinition;
    _nameController = TextEditingController(text: init?.name ?? 'Новый тип арматуры');
    _descController = TextEditingController(text: init?.description ?? '');
    _stemTextController = TextEditingController(text: init?.symbol2d.stemText ?? 'АВ');
    _minLengthController =
        TextEditingController(text: (init?.minLengthMm ?? 100.0).toStringAsFixed(0));

    _bodyShape = init?.effectiveBodyShape ?? Valve3dBodyShape.doubleCones;
    _leftWingStyle = init?.symbol2d.leftWingStyle ?? ValveWingFillStyle.outline;
    _rightWingStyle = init?.symbol2d.rightWingStyle ?? ValveWingFillStyle.outline;
    _dividerType = init?.symbol2d.dividerType ?? ValveDividerType.none;
    _stemType = init?.symbol2d.stemType ?? ValveStemSymbolType.handwheel;
    _hasBodyFlanges = init?.symbol2d.hasBodyFlanges ?? false;

    _defaultLengthFactor = init?.defaultLengthFactor ?? 1.5;
    _stemHeightRatio = init?.geometry3d.stemHeightRatio ?? 2.2;
    _actuatorSizeRatio = init?.geometry3d.actuatorSizeRatio ?? 1.4;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _stemTextController.dispose();
    _minLengthController.dispose();
    super.dispose();
  }

  void _applyQuickPreset(_QuickPreset p) {
    setState(() {
      _nameController.text = p.name;
      _descController.text = p.description;
      _bodyShape = p.bodyShape;
      _leftWingStyle = p.leftWing;
      _rightWingStyle = p.rightWing;
      _dividerType = p.divider;
      _stemType = p.stem;
      _stemTextController.text = p.stemText;
      _hasBodyFlanges = p.isFlanged;
      _defaultLengthFactor = p.lengthFactor;
      _minLengthController.text = p.minLength.toStringAsFixed(0);
    });
  }

  ValveSymbolConfig _buildCurrentSymbolConfig() {
    return ValveSymbolConfig(
      bodyShape: _bodyShape,
      leftWingStyle: _leftWingStyle,
      rightWingStyle: _rightWingStyle,
      dividerType: _dividerType,
      stemType: _stemType,
      stemText: _stemTextController.text,
      hasBodyFlanges: _hasBodyFlanges,
    );
  }

  ValveGeometry3dConfig _buildCurrentGeometryConfig() {
    Valve3dActuatorType actType = Valve3dActuatorType.none;
    switch (_stemType) {
      case ValveStemSymbolType.none:
        actType = Valve3dActuatorType.none;
        break;
      case ValveStemSymbolType.handwheel:
        actType = Valve3dActuatorType.handwheel;
        break;
      case ValveStemSymbolType.lever:
        actType = Valve3dActuatorType.lever;
        break;
      case ValveStemSymbolType.boxWithText:
        actType = Valve3dActuatorType.actuatorBox;
        break;
      case ValveStemSymbolType.diaphragm:
        actType = Valve3dActuatorType.diaphragm;
        break;
      case ValveStemSymbolType.spring:
        actType = Valve3dActuatorType.springBonnet;
        break;
    }

    return ValveGeometry3dConfig(
      bodyShape: _bodyShape,
      actuatorType: actType,
      stemHeightRatio: _stemHeightRatio,
      actuatorSizeRatio: _actuatorSizeRatio,
    );
  }

  CustomValveDefinition _buildDefinition() {
    final minLen = double.tryParse(_minLengthController.text) ?? 100.0;
    final isEditing = widget.initialDefinition != null && !widget.initialDefinition!.isBuiltin;
    final id = isEditing
        ? widget.initialDefinition!.id
        : 'custom_valve_${_uuid.v4().substring(0, 8)}';

    return CustomValveDefinition(
      id: id,
      name: _nameController.text.trim().isEmpty
          ? 'Пользовательская арматура'
          : _nameController.text.trim(),
      description: _descController.text.trim(),
      defaultLengthFactor: _defaultLengthFactor,
      minLengthMm: minLen,
      symbol2d: _buildCurrentSymbolConfig(),
      geometry3d: _buildCurrentGeometryConfig(),
      isBuiltin: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final symbol = _buildCurrentSymbolConfig();
    final geometry = _buildCurrentGeometryConfig();
    final currentDef = CustomValveDefinition(
      id: 'preview',
      name: _nameController.text,
      symbol2d: symbol,
      geometry3d: geometry,
      defaultLengthFactor: _defaultLengthFactor,
      minLengthMm: double.tryParse(_minLengthController.text) ?? 100.0,
    );

    final screenSize = MediaQuery.of(context).size;
    final dialogW = math.min(1080.0, screenSize.width - 24.0);
    final dialogH = math.min(760.0, screenSize.height - 24.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogW,
        height: dialogH,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Заголовок и быстрые пресеты
            Row(
              children: [
                const Icon(Icons.architecture, color: Colors.indigo, size: 26),
                const SizedBox(width: 10),
                const Text(
                  'Редактор семейства арматуры',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Горизонтальная лента быстрых ГОСТ-пресетов
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kQuickPresets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final preset = _kQuickPresets[idx];
                  return ActionChip(
                    avatar: Icon(preset.icon, size: 16, color: Colors.indigo),
                    label: Text(preset.label, style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.indigo.shade50,
                    side: BorderSide(color: Colors.indigo.shade200),
                    onPressed: () => _applyQuickPreset(preset),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            const Divider(),

            // Основная часть: левая колонка (настройки) и правая колонка (живой холст)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Левая колонка параметров (единый скроллируемый поток)
                  Expanded(
                    flex: 6,
                    child: ListView(
                      padding: const EdgeInsets.only(right: 12),
                      children: [
                        _buildSectionCard(
                          title: 'Паспорт элемента',
                          icon: Icons.badge_outlined,
                          child: Column(
                            children: [
                              TextField(
                                key: const Key('valve_name_field'),
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Наименование типа арматуры',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _descController,
                                decoration: const InputDecoration(
                                  labelText: 'Описание / марка по проекту (ГОСТ, ТУ)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        _buildSectionCard(
                          title: 'Корпус арматуры',
                          icon: Icons.category_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Переключатель формы корпуса
                              const Text('Форма корпуса:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: Valve3dBodyShape.values.map((shape) {
                                  final isSelected = _bodyShape == shape;
                                  return ChoiceChip(
                                    label: Text(shape.displayName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              isSelected ? FontWeight.bold : FontWeight.normal,
                                        )),
                                    selected: isSelected,
                                    selectedColor: Colors.indigo.shade100,
                                    onSelected: (val) {
                                      if (val) setState(() => _bodyShape = shape);
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 10),

                              // Заливка и штриховка
                              if (_bodyShape == Valve3dBodyShape.doubleCones ||
                                  _bodyShape == Valve3dBodyShape.cylinder) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDropdownRow<ValveWingFillStyle>(
                                        label: 'Левая часть:',
                                        value: _leftWingStyle,
                                        items: ValveWingFillStyle.values,
                                        getName: (s) => s.displayName,
                                        onChanged: (v) => setState(() => _leftWingStyle = v),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildDropdownRow<ValveWingFillStyle>(
                                        label: 'Правая часть:',
                                        value: _rightWingStyle,
                                        items: ValveWingFillStyle.values,
                                        getName: (s) => s.displayName,
                                        onChanged: (v) => setState(() => _rightWingStyle = v),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                _buildDropdownRow<ValveWingFillStyle>(
                                  label: 'Стиль заливки / штриховки:',
                                  value: _leftWingStyle,
                                  items: ValveWingFillStyle.values,
                                  getName: (s) => s.displayName,
                                  onChanged: (v) => setState(() {
                                    _leftWingStyle = v;
                                    _rightWingStyle = v;
                                  }),
                                ),
                              ],
                              const SizedBox(height: 8),

                              // Центральный разделитель
                              _buildDropdownRow<ValveDividerType>(
                                label: 'Разделитель / механизм:',
                                value: _dividerType,
                                items: ValveDividerType.values,
                                getName: (d) => d.displayName,
                                onChanged: (v) => setState(() => _dividerType = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        _buildSectionCard(
                          title: 'Орган управления / Привод',
                          icon: Icons.settings_input_component_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDropdownRow<ValveStemSymbolType>(
                                label: 'Тип привода:',
                                value: _stemType,
                                items: ValveStemSymbolType.values,
                                getName: (s) => s.displayName,
                                onChanged: (v) => setState(() => _stemType = v),
                              ),
                              if (_stemType == ValveStemSymbolType.boxWithText ||
                                  _stemType == ValveStemSymbolType.diaphragm) ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _stemTextController,
                                  decoration: const InputDecoration(
                                    labelText: 'Текст на приводе (до 4 символов: Э, М, АВ, ФС)',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLength: 4,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        _buildSectionCard(
                          title: 'Монтаж и габариты',
                          icon: Icons.straighten,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                  'Фланцевые торцы (ГОСТ 33259 / 12821 с ответными фланцами)',
                                  style: TextStyle(fontSize: 12),
                                ),
                                value: _hasBodyFlanges,
                                onChanged: (v) => setState(() => _hasBodyFlanges = v ?? false),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: TextField(
                                      controller: _minLengthController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Мин. длина (мм)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 6,
                                    child: Text(
                                      'Длина корпуса: ${_defaultLengthFactor.toStringAsFixed(1)} × DN',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo),
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: _defaultLengthFactor,
                                min: 1.0,
                                max: 3.0,
                                divisions: 20,
                                onChanged: (v) => setState(() => _defaultLengthFactor = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 1),
                  const SizedBox(width: 12),

                  // Правая колонка: интерактивная студия предпросмотра
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Панель переключения ракурса и темы
                        Row(
                          children: [
                            Expanded(
                              child: SegmentedButton<_EditorPreviewMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: _EditorPreviewMode.plan2d,
                                    label: Text('2D УГО (ГОСТ)', style: TextStyle(fontSize: 10)),
                                  ),
                                  ButtonSegment(
                                    value: _EditorPreviewMode.gost45,
                                    label: Text('3D Геометрия', style: TextStyle(fontSize: 10)),
                                  ),
                                  ButtonSegment(
                                    value: _EditorPreviewMode.iso30,
                                    label: Text('ISO 30°', style: TextStyle(fontSize: 10)),
                                  ),
                                ],
                                selected: {_previewMode},
                                onSelectionChanged: (set) {
                                  setState(() => _previewMode = set.first);
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(
                                _isDarkTheme ? Icons.light_mode : Icons.dark_mode,
                                size: 18,
                              ),
                              tooltip: _isDarkTheme ? 'Светлая тема (бумага)' : 'Темная тема (CAD)',
                              onPressed: () => setState(() => _isDarkTheme = !_isDarkTheme),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Холст живого интерактивного предпросмотра
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isDarkTheme ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade300,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 10,
                                    top: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _isDarkTheme
                                            ? Colors.black38
                                            : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _previewMode == _EditorPreviewMode.plan2d
                                            ? '2D ГОСТ УГО (в плоскости трубы)'
                                            : (_previewMode == _EditorPreviewMode.gost45
                                                ? '3D Схема (ГОСТ 45° аксонометрия)'
                                                : '3D Схема (ISO 30° изометрия)'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: _isDarkTheme ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: _previewMode == _EditorPreviewMode.plan2d
                                        ? CustomPaint(
                                            size: const Size(260, 200),
                                            painter: _Valve2dLivePreviewPainter(
                                              symbolConfig: symbol,
                                              isDark: _isDarkTheme,
                                            ),
                                          )
                                        : CustomPaint(
                                            size: const Size(260, 200),
                                            painter: _Valve3dLivePreviewPainter(
                                              definition: currentDef,
                                              projection: _previewMode == _EditorPreviewMode.gost45
                                                  ? ProjectionType.gostFrontal45
                                                  : ProjectionType.iso30,
                                              isDark: _isDarkTheme,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Информационная плашка габаритов
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade100),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Форма: ${_bodyShape.displayName}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'DN 50 (Труба 57 мм) • L = ${(50 * _defaultLengthFactor).clamp(double.tryParse(_minLengthController.text) ?? 100.0, 999.0).toStringAsFixed(0)} мм',
                                style: const TextStyle(fontSize: 11, color: Colors.indigo),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Divider(),

            // Кнопки сохранения и отмены
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Сохранить'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final def = _buildDefinition();
                    await CustomValveCatalog.instance.saveDefinition(def);
                    if (context.mounted) {
                      Navigator.of(context).pop(def);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.indigo),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownRow<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) getName,
    required void Function(T) onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          flex: 6,
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            items: items.map((item) {
              return DropdownMenuItem<T>(
                value: item,
                child: Text(getName(item), style: const TextStyle(fontSize: 11)),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

/// CustomPainter для предпросмотра 2D УГО по ГОСТ в диалоге
class _Valve2dLivePreviewPainter extends CustomPainter {
  final ValveSymbolConfig symbolConfig;
  final bool isDark;

  const _Valve2dLivePreviewPainter({
    required this.symbolConfig,
    this.isDark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 8);

    // Осевая линия трубы
    final axisPaint = Paint()
      ..color = isDark ? Colors.white30 : Colors.blueGrey.shade300
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(15, center.dy), Offset(size.width - 15, center.dy), axisPaint);

    // Контуры трубы (внешний габарит трубы)
    final pipeWallPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.grey.shade400
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(15, center.dy - 12), Offset(size.width - 15, center.dy - 12), pipeWallPaint);
    canvas.drawLine(Offset(15, center.dy + 12), Offset(size.width - 15, center.dy + 12), pipeWallPaint);

    // Отрисовка УГО
    ValveSymbolPainter.drawCustomValve(
      canvas,
      center: center,
      angleRad: 0.0,
      symbolConfig: symbolConfig,
      color: isDark ? Colors.cyanAccent : Colors.indigo.shade900,
      size: 42.0,
    );
  }

  @override
  bool shouldRepaint(covariant _Valve2dLivePreviewPainter oldDelegate) {
    return oldDelegate.symbolConfig != symbolConfig || oldDelegate.isDark != isDark;
  }
}

/// CustomPainter для предпросмотра 3D каркаса в диалоге
class _Valve3dLivePreviewPainter extends CustomPainter {
  final CustomValveDefinition definition;
  final ProjectionType projection;
  final bool isDark;

  const _Valve3dLivePreviewPainter({
    required this.definition,
    this.projection = ProjectionType.gostFrontal45,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final projector = AxonometryProjector(projectionType: projection);
    const startNode = Node3D(id: 's', x: -140, y: 0, z: 0);
    const endNode = Node3D(id: 'e', x: 140, y: 0, z: 0);

    final valveLength = math.max(
      definition.minLengthMm,
      50.0 * definition.defaultLengthFactor,
    );

    final valve = Valve(
      id: 'v_preview',
      name: definition.name,
      segmentId: 'seg',
      ratio: 0.5,
      dn: 50,
      lengthMm: valveLength,
      valveType: ValveType.gateValve,
      customDefinitionId: definition.id,
      isFlanged: definition.symbol2d.hasBodyFlanges,
      includeCounterFlanges: true,
    );

    final segments = Element3dGeometry.generateValveWireframe(
      valve,
      startNode,
      endNode,
      pipeOuterDiameter: 57.0,
      customDefinition: definition,
    );

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + 15);

    // Осевая линия трубы
    final axisPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.grey.shade400
      ..strokeWidth = 1.0;
    canvas.drawLine(projector.project(startNode), projector.project(endNode), axisPaint);

    final strokePaint = Paint()
      ..color = isDark ? Colors.cyanAccent : Colors.indigo.shade900
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    for (final seg in segments) {
      final p1 = projector.project(seg.startNode);
      final p2 = projector.project(seg.endNode);
      canvas.drawLine(p1, p2, strokePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Valve3dLivePreviewPainter oldDelegate) {
    return oldDelegate.definition != definition ||
        oldDelegate.projection != projection ||
        oldDelegate.isDark != isDark;
  }
}
