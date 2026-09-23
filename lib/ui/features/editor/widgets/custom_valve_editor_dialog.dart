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

/// Интерактивный визуальный конструктор пользовательских семейств арматуры
/// с живым обновлением 2D УГО (ГОСТ) и 3D аксонометрии в реальном времени.
class CustomValveEditorDialog extends StatefulWidget {
  final CustomValveDefinition? initialDefinition;

  const CustomValveEditorDialog({
    super.key,
    this.initialDefinition,
  });

  @override
  State<CustomValveEditorDialog> createState() => _CustomValveEditorDialogState();
}

class _CustomValveEditorDialogState extends State<CustomValveEditorDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _stemTextController;
  late TextEditingController _minLengthController;

  late ValveWingFillStyle _leftWingStyle;
  late ValveWingFillStyle _rightWingStyle;
  late ValveDividerType _dividerType;
  late ValveStemSymbolType _stemType;
  late bool _hasBodyFlanges;

  late Valve3dBodyShape _bodyShape;
  late Valve3dActuatorType _actuatorType;
  late double _stemHeightRatio;
  late double _actuatorSizeRatio;
  late double _defaultLengthFactor;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final init = widget.initialDefinition;
    _nameController = TextEditingController(text: init?.name ?? 'Новый тип арматуры');
    _descController = TextEditingController(text: init?.description ?? '');
    _stemTextController = TextEditingController(text: init?.symbol2d.stemText ?? 'АВ');
    _minLengthController =
        TextEditingController(text: (init?.minLengthMm ?? 100.0).toStringAsFixed(0));

    _leftWingStyle = init?.symbol2d.leftWingStyle ?? ValveWingFillStyle.outline;
    _rightWingStyle = init?.symbol2d.rightWingStyle ?? ValveWingFillStyle.outline;
    _dividerType = init?.symbol2d.dividerType ?? ValveDividerType.none;
    _stemType = init?.symbol2d.stemType ?? ValveStemSymbolType.handwheel;
    _hasBodyFlanges = init?.symbol2d.hasBodyFlanges ?? false;

    _bodyShape = init?.geometry3d.bodyShape ?? Valve3dBodyShape.doubleCones;
    _actuatorType = init?.geometry3d.actuatorType ?? Valve3dActuatorType.handwheel;
    _stemHeightRatio = init?.geometry3d.stemHeightRatio ?? 2.2;
    _actuatorSizeRatio = init?.geometry3d.actuatorSizeRatio ?? 1.4;
    _defaultLengthFactor = init?.defaultLengthFactor ?? 1.5;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _stemTextController.dispose();
    _minLengthController.dispose();
    super.dispose();
  }

  ValveSymbolConfig _buildCurrentSymbolConfig() {
    return ValveSymbolConfig(
      leftWingStyle: _leftWingStyle,
      rightWingStyle: _rightWingStyle,
      dividerType: _dividerType,
      stemType: _stemType,
      stemText: _stemTextController.text,
      hasBodyFlanges: _hasBodyFlanges,
    );
  }

  ValveGeometry3dConfig _buildCurrentGeometryConfig() {
    return ValveGeometry3dConfig(
      bodyShape: _bodyShape,
      actuatorType: _actuatorType,
      stemHeightRatio: _stemHeightRatio,
      actuatorSizeRatio: _actuatorSizeRatio,
    );
  }

  CustomValveDefinition _buildDefinition() {
    final minLen = double.tryParse(_minLengthController.text) ?? 100.0;
    final isEditing = widget.initialDefinition != null;
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

    final screenSize = MediaQuery.of(context).size;
    final dialogW = math.min(860.0, screenSize.width - 32.0);
    final dialogH = math.min(640.0, screenSize.height - 32.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogW,
        height: dialogH,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Заголовок
            Row(
              children: [
                const Icon(Icons.architecture, color: Colors.indigo, size: 24),
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
            const Divider(),

            // Основная часть: 2 колонки (слева параметры, справа интерактивный предпросмотр)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Левая колонка: параметры
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            labelText: 'Описание / примечание',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        TabBar(
                          controller: _tabController,
                          labelColor: Colors.indigo,
                          indicatorColor: Colors.indigo,
                          tabs: const [
                            Tab(text: '2D УГО (ГОСТ)'),
                            Tab(text: '3D Геометрия'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              // Вкладка 2D параметров
                              _build2dSettingsTab(),
                              // Вкладка 3D параметров
                              _build3dSettingsTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 16),
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 16),

                  // Правая колонка: живой предпросмотр 2D и 3D
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.remove_red_eye, size: 16, color: Colors.blueGrey),
                            SizedBox(width: 6),
                            Text(
                              'Живой предпросмотр',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.blueGrey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 2D Canvas Preview
                        Expanded(
                          flex: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Stack(
                              children: [
                                const Positioned(
                                  left: 8,
                                  top: 6,
                                  child: Text('2D ГОСТ УГО',
                                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                                ),
                                Center(
                                  child: CustomPaint(
                                    size: const Size(200, 120),
                                    painter: _Valve2dLivePreviewPainter(symbolConfig: symbol),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 3D Canvas Preview
                        Expanded(
                          flex: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade800),
                            ),
                            child: Stack(
                              children: [
                                const Positioned(
                                  left: 8,
                                  top: 6,
                                  child: Text('3D Аксонометрия',
                                      style: TextStyle(fontSize: 10, color: Colors.white60)),
                                ),
                                Center(
                                  child: CustomPaint(
                                    size: const Size(200, 140),
                                    painter: _Valve3dLivePreviewPainter(
                                      definition: CustomValveDefinition(
                                        id: 'preview',
                                        name: 'Preview',
                                        symbol2d: symbol,
                                        geometry3d: geometry,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),

            // Кнопки сохранения
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

  Widget _build2dSettingsTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 8, right: 6),
      children: [
        // Заливка левого крыла
        Row(
          children: [
            const SizedBox(
              width: 110,
              child: Text('Левое крыло:', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: DropdownButton<ValveWingFillStyle>(
                value: _leftWingStyle,
                isDense: true,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                      value: ValveWingFillStyle.outline,
                      child: Text(ValveWingFillStyle.outline.displayName,
                          style: const TextStyle(fontSize: 11))),
                  DropdownMenuItem(
                      value: ValveWingFillStyle.solid,
                      child: Text(ValveWingFillStyle.solid.displayName,
                          style: const TextStyle(fontSize: 11))),
                  DropdownMenuItem(
                      value: ValveWingFillStyle.hatched,
                      child: Text(ValveWingFillStyle.hatched.displayName,
                          style: const TextStyle(fontSize: 11))),
                  DropdownMenuItem(
                      value: ValveWingFillStyle.crossHatched,
                      child: Text(ValveWingFillStyle.crossHatched.displayName,
                          style: const TextStyle(fontSize: 11))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _leftWingStyle = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Заливка правого крыла
        Row(
          children: [
            const SizedBox(
              width: 110,
              child: Text('Правое крыло:', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: DropdownButton<ValveWingFillStyle>(
                value: _rightWingStyle,
                isDense: true,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                      value: ValveWingFillStyle.outline,
                      child: Text(ValveWingFillStyle.outline.displayName,
                          style: const TextStyle(fontSize: 11))),
                  DropdownMenuItem(
                      value: ValveWingFillStyle.solid,
                      child: Text(ValveWingFillStyle.solid.displayName,
                          style: const TextStyle(fontSize: 11))),
                  DropdownMenuItem(
                      value: ValveWingFillStyle.hatched,
                      child: Text(ValveWingFillStyle.hatched.displayName,
                          style: const TextStyle(fontSize: 11))),
                  DropdownMenuItem(
                      value: ValveWingFillStyle.crossHatched,
                      child: Text(ValveWingFillStyle.crossHatched.displayName,
                          style: const TextStyle(fontSize: 11))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _rightWingStyle = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Разделитель
        Row(
          children: [
            const SizedBox(
              width: 110,
              child: Text('Разделитель:', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: DropdownButton<ValveDividerType>(
                value: _dividerType,
                isDense: true,
                isExpanded: true,
                items: ValveDividerType.values.map((d) {
                  return DropdownMenuItem(
                    value: d,
                    child: Text(d.displayName, style: const TextStyle(fontSize: 11)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _dividerType = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Шток / обозначение привода
        Row(
          children: [
            const SizedBox(
              width: 110,
              child: Text('Привод / шток:', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: DropdownButton<ValveStemSymbolType>(
                value: _stemType,
                isDense: true,
                isExpanded: true,
                items: ValveStemSymbolType.values.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(s.displayName, style: const TextStyle(fontSize: 11)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _stemType = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Текст на приводе (если boxWithText или diaphragm)
        if (_stemType == ValveStemSymbolType.boxWithText ||
            _stemType == ValveStemSymbolType.diaphragm) ...[
          TextField(
            controller: _stemTextController,
            decoration: const InputDecoration(
              labelText: 'Текст на приводе (например, Э, АВ, М)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            maxLength: 4,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
        ],

        // Фланцевые засечки
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Фланцевые засечки на торцах', style: TextStyle(fontSize: 12)),
          value: _hasBodyFlanges,
          onChanged: (v) => setState(() => _hasBodyFlanges = v ?? false),
        ),
      ],
    );
  }

  Widget _build3dSettingsTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 8, right: 6),
      children: [
        // Форма корпуса 3D
        Row(
          children: [
            const SizedBox(
              width: 120,
              child: Text('Форма корпуса 3D:', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: DropdownButton<Valve3dBodyShape>(
                value: _bodyShape,
                isDense: true,
                isExpanded: true,
                items: Valve3dBodyShape.values.map((b) {
                  return DropdownMenuItem(
                    value: b,
                    child: Text(b.displayName, style: const TextStyle(fontSize: 11)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _bodyShape = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Тип привода 3D
        Row(
          children: [
            const SizedBox(
              width: 120,
              child: Text('Привод 3D:', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: DropdownButton<Valve3dActuatorType>(
                value: _actuatorType,
                isDense: true,
                isExpanded: true,
                items: Valve3dActuatorType.values.map((a) {
                  return DropdownMenuItem(
                    value: a,
                    child: Text(a.displayName, style: const TextStyle(fontSize: 11)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _actuatorType = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_actuatorType != Valve3dActuatorType.none) ...[
          // Высота штока
          Text(
            'Высота штока (x диаметр трубы): ${_stemHeightRatio.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Slider(
            value: _stemHeightRatio,
            min: 1.0,
            max: 4.0,
            divisions: 30,
            onChanged: (v) => setState(() => _stemHeightRatio = v),
          ),

          // Размер привода
          Text(
            'Размер привода (x радиус): ${_actuatorSizeRatio.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Slider(
            value: _actuatorSizeRatio,
            min: 0.8,
            max: 3.0,
            divisions: 22,
            onChanged: (v) => setState(() => _actuatorSizeRatio = v),
          ),
        ],

        // Коэффициент строительной длины
        Text(
          'Коэффициент длины корпуса (x DN): ${_defaultLengthFactor.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        Slider(
          value: _defaultLengthFactor,
          min: 1.0,
          max: 3.0,
          divisions: 20,
          onChanged: (v) => setState(() => _defaultLengthFactor = v),
        ),

        // Минимальная длина корпуса
        TextField(
          controller: _minLengthController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Мин. строительная длина (мм)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

/// CustomPainter для предпросмотра 2D УГО по ГОСТ в диалоге
class _Valve2dLivePreviewPainter extends CustomPainter {
  final ValveSymbolConfig symbolConfig;

  const _Valve2dLivePreviewPainter({required this.symbolConfig});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 8);

    // Осевая линия трубы
    final axisPaint = Paint()
      ..color = Colors.blueGrey.shade300
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(10, center.dy), Offset(size.width - 10, center.dy), axisPaint);

    // Отрисовка УГО
    ValveSymbolPainter.drawCustomValve(
      canvas,
      center: center,
      angleRad: 0.0,
      symbolConfig: symbolConfig,
      color: Colors.black87,
      size: 32.0,
    );
  }

  @override
  bool shouldRepaint(covariant _Valve2dLivePreviewPainter oldDelegate) {
    return oldDelegate.symbolConfig != symbolConfig;
  }
}

/// CustomPainter для предпросмотра 3D каркаса в диалоге
class _Valve3dLivePreviewPainter extends CustomPainter {
  final CustomValveDefinition definition;

  const _Valve3dLivePreviewPainter({required this.definition});

  @override
  void paint(Canvas canvas, Size size) {
    const projector = AxonometryProjector(projectionType: ProjectionType.gostFrontal45);
    const startNode = Node3D(id: 's', x: -100, y: 0, z: 0);
    const endNode = Node3D(id: 'e', x: 100, y: 0, z: 0);

    final valve = Valve(
      id: 'v_preview',
      name: 'Preview',
      segmentId: 'seg',
      ratio: 0.5,
      dn: 50,
      lengthMm: 120,
      valveType: ValveType.gateValve,
      customDefinitionId: definition.id,
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

    // Осевая линия
    final axisPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;
    canvas.drawLine(projector.project(startNode), projector.project(endNode), axisPaint);

    final strokePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1.5
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
    return oldDelegate.definition != definition;
  }
}
