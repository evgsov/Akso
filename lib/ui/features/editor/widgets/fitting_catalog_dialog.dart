import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/enums/fitting_type.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/fitting.dart';
import '../../../../domain/models/fitting_definition.dart';
import '../../../../domain/models/piping_network.dart';

const _uuid = Uuid();

/// Диалог управления каталогом фитингов, коллекцией элементов и правилами трассировки
class FittingCatalogDialog extends StatefulWidget {
  final PipingNetwork network;
  final String? selectedNodeId;
  final VoidCallback? onCatalogChanged;

  const FittingCatalogDialog({
    super.key,
    required this.network,
    this.selectedNodeId,
    this.onCatalogChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required PipingNetwork network,
    String? selectedNodeId,
    VoidCallback? onCatalogChanged,
  }) {
    return showDialog(
      context: context,
      builder: (_) => FittingCatalogDialog(
        network: network,
        selectedNodeId: selectedNodeId,
        onCatalogChanged: onCatalogChanged,
      ),
    );
  }

  @override
  State<FittingCatalogDialog> createState() => _FittingCatalogDialogState();
}

typedef FittingSettingsDialog = FittingCatalogDialog;

class _FittingCatalogDialogState extends State<FittingCatalogDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedFilterGroup; // 'all', 'elbow', 'tee', 'directBranch', 'reducer', 'flange', 'custom'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 920,
        height: 680,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Заголовок диалога
            Row(
              children: [
                const Icon(Icons.settings_suggest, color: Colors.indigo, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Элементы и соединения',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.selectedNodeId != null
                            ? 'Настройка для узла: ${widget.selectedNodeId} | Коллекция элементов и правила трассировки'
                            : 'Коллекция фасонных элементов ГОСТ/ТУ, правила соединений и расчет сварных стыков',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('+ Создать свой элемент'),
                  onPressed: () => _showCreateCustomDialog(context),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Табы: 1 - Коллекция элементов, 2 - Правила соединений и трассировки
            TabBar(
              controller: _tabController,
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.indigo,
              tabs: const [
                Tab(icon: Icon(Icons.category), text: 'Коллекция элементов'),
                Tab(icon: Icon(Icons.rule), text: 'Правила соединений и трассировки'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCollectionTab(),
                  _buildRoutingRulesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== ВКЛАДКА 1: КОЛЛЕКЦИЯ ЭЛЕМЕНТОВ =====================
  Widget _buildCollectionTab() {
    final catalog = widget.network.catalog;
    final allDefs = catalog.definitions.values.toList();
    final filteredDefs = allDefs.where((d) {
      if (_selectedFilterGroup == null || _selectedFilterGroup == 'all') return true;
      if (_selectedFilterGroup == 'elbow') return d.archetype == FittingArchetype.elbow;
      if (_selectedFilterGroup == 'tee') return d.archetype == FittingArchetype.tee;
      if (_selectedFilterGroup == 'directBranch') return d.archetype == FittingArchetype.directBranch;
      if (_selectedFilterGroup == 'reducer') return d.archetype == FittingArchetype.reducer;
      if (_selectedFilterGroup == 'flange') return d.archetype == FittingArchetype.flange;
      if (_selectedFilterGroup == 'custom') return d.isCustom;
      return true;
    }).toList();

    final selectedFit = widget.selectedNodeId != null ? widget.network.fittings[widget.selectedNodeId] : null;

    return Column(
      children: [
        // Фильтры категорий
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Все элементы'),
                selected: _selectedFilterGroup == null || _selectedFilterGroup == 'all',
                onSelected: (_) => setState(() => _selectedFilterGroup = 'all'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Отводы (гибы)'),
                selected: _selectedFilterGroup == 'elbow',
                onSelected: (_) => setState(() => _selectedFilterGroup = 'elbow'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Тройники'),
                selected: _selectedFilterGroup == 'tee',
                onSelected: (_) => setState(() => _selectedFilterGroup = 'tee'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Прямые врезки'),
                selected: _selectedFilterGroup == 'directBranch',
                onSelected: (_) => setState(() => _selectedFilterGroup = 'directBranch'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Фланцы'),
                selected: _selectedFilterGroup == 'flange',
                onSelected: (_) => setState(() => _selectedFilterGroup = 'flange'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Переходы'),
                selected: _selectedFilterGroup == 'reducer',
                onSelected: (_) => setState(() => _selectedFilterGroup = 'reducer'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                label: Text('Свои (${catalog.customDefinitions.length})'),
                selected: _selectedFilterGroup == 'custom',
                onSelected: (_) => setState(() => _selectedFilterGroup = 'custom'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        // Список карточек элементов коллекции
        Expanded(
          child: filteredDefs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text('В этой категории пока нет элементов', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filteredDefs.length,
                  separatorBuilder: (ctx, idx) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final def = filteredDefs[index];
                    final isDefaultElbow = catalog.defaultElbowId == def.id;
                    final isDefaultBranch = catalog.defaultBranchId == def.id;
                    final isDefaultFlange = catalog.defaultFlangeId == def.id;
                    final isCurrentDefault = isDefaultElbow || isDefaultBranch || isDefaultFlange;

                    final isCompatibleWithSelected = selectedFit != null && _isCompatible(selectedFit, def);

                    return Container(
                      color: isCompatibleWithSelected ? Colors.indigo.shade50.withValues(alpha: 0.4) : null,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: def.isCustom ? Colors.amber.shade100 : Colors.indigo.shade50,
                          child: Icon(
                            _getArchetypeIcon(def.archetype),
                            color: def.isCustom ? Colors.amber.shade900 : Colors.indigo,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                def.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (def.isCustom) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Свой шаблон', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                            if (isCurrentDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('По умолчанию', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          'Стандарт: ${def.standard} | Вычет/Геометрия: ${_formatDeduction(def)} | Швы: ${_formatWelds(def)} | Сталь: ${def.defaultMaterial}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Кнопка применения к выбранному узлу
                            if (isCompatibleWithSelected) ...[
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () => _applyDefinitionToSelectedNode(def),
                                child: const Text('Применить к узлу', style: TextStyle(fontSize: 11)),
                              ),
                              const SizedBox(width: 6),
                            ],
                            // Кнопка установки по умолчанию
                            if (def.archetype == FittingArchetype.elbow && !isDefaultElbow)
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () {
                                  setState(() => catalog.defaultElbowId = def.id);
                                  widget.network.recalculateSpools();
                                  widget.onCatalogChanged?.call();
                                },
                                child: const Text('По умолч.', style: TextStyle(fontSize: 11)),
                              ),
                            if ((def.archetype == FittingArchetype.tee || def.archetype == FittingArchetype.directBranch) && !isDefaultBranch)
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () {
                                  setState(() => catalog.defaultBranchId = def.id);
                                  widget.network.recalculateSpools();
                                  widget.onCatalogChanged?.call();
                                },
                                child: const Text('По умолч.', style: TextStyle(fontSize: 11)),
                              ),
                            if (def.archetype == FittingArchetype.flange && !isDefaultFlange)
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () {
                                  setState(() => catalog.defaultFlangeId = def.id);
                                  widget.network.recalculateSpools();
                                  widget.onCatalogChanged?.call();
                                },
                                child: const Text('По умолч.', style: TextStyle(fontSize: 11)),
                              ),
                            const SizedBox(width: 6),
                            // Создать копию
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Создать на основе этого элемента',
                              onPressed: () => _showCreateCustomDialog(context, baseDef: def),
                            ),
                            // Удалить (только кастомные)
                            if (def.isCustom)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                tooltip: 'Удалить пользовательский элемент',
                                onPressed: () {
                                  setState(() => catalog.removeCustomDefinition(def.id));
                                  widget.network.recalculateSpools();
                                  widget.onCatalogChanged?.call();
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ===================== ВКЛАДКА 2: ПРАВИЛА ТРАССИРОВКИ =====================
  Widget _buildRoutingRulesTab() {
    final catalog = widget.network.catalog;
    final elbows = catalog.getByArchetype(FittingArchetype.elbow);
    final branches = [...catalog.getByArchetype(FittingArchetype.tee), ...catalog.getByArchetype(FittingArchetype.directBranch)];
    final flanges = catalog.getByArchetype(FittingArchetype.flange);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('1. Отводы при изменении направления трассы'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Тип отвода по умолчанию для прямых и косых поворотов:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: catalog.defaultElbowId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: elbows.map((e) => DropdownMenuItem(value: e.id, child: Text('${e.name} (${e.standard})', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() => catalog.defaultElbowId = id);
                      widget.network.recalculateSpools();
                      widget.onCatalogChanged?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('2. Ответвления (Тройники и Врезки)'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Способ врезки ответвления по умолчанию:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: catalog.defaultBranchId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: branches.map((b) => DropdownMenuItem(value: b.id, child: Text('${b.name} (${b.standard})', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() => catalog.defaultBranchId = id);
                      widget.network.recalculateSpools();
                      widget.onCatalogChanged?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('3. Фланцевые соединения и оборудование (ГОСТ 33259-2015)'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Тип фланцев по умолчанию:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: catalog.defaultFlangeId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: flanges.map((f) => DropdownMenuItem(value: f.id, child: Text('${f.name} (${f.standard})', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() => catalog.defaultFlangeId = id);
                      widget.network.recalculateSpools();
                      widget.onCatalogChanged?.call();
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Режим фланцевого подключения по умолчанию:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<FlangeConnectionType>(
                    segments: const [
                      ButtonSegment(
                        value: FlangeConnectionType.toEquipment,
                        label: Text('К оборудованию (1 стык)'),
                        icon: Icon(Icons.precision_manufacturing),
                      ),
                      ButtonSegment(
                        value: FlangeConnectionType.pipeToPipe,
                        label: Text('Межтрубное (2 стыка)'),
                        icon: Icon(Icons.compare_arrows),
                      ),
                    ],
                    selected: {catalog.defaultFlangeConnectionType},
                    onSelectionChanged: (set) {
                      setState(() => catalog.defaultFlangeConnectionType = set.first);
                      widget.onCatalogChanged?.call();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    catalog.defaultFlangeConnectionType == FlangeConnectionType.toEquipment
                        ? '• Подключение к оборудованию: создается ровно 1 ответный фланец со сварным стыком на примыкающей трубе. Штуцер насоса/емкости/арматуры имеет заводской фланец без монтажного шва.'
                        : '• Межтрубное соединение: создается пара ответных фланцев с 2 сварными стыками и прокладкой между ними.',
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('4. Исполнение трубной арматуры (задвижки, краны, затворы)'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Присоединение арматуры при установке на трубу:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Под приварку (стыковые швы)'),
                        icon: Icon(Icons.microwave),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Фланцевая (с фланцевыми парами)'),
                        icon: Icon(Icons.radio_button_checked),
                      ),
                    ],
                    selected: {catalog.defaultValveIsFlanged},
                    onSelectionChanged: (set) {
                      setState(() => catalog.defaultValveIsFlanged = set.first);
                      widget.onCatalogChanged?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo),
      ),
    );
  }

  // ===================== КОНСТРУКТОР НОВОГО ЭЛЕМЕНТА =====================
  void _showCreateCustomDialog(BuildContext context, {FittingDefinition? baseDef}) {
    final catalog = widget.network.catalog;
    final initial = baseDef ?? catalog.definitions.values.first;

    FittingArchetype currentArchetype = initial.archetype;
    final nameCtrl = TextEditingController(text: baseDef != null ? '${baseDef.name} (Свой)' : 'Новый элемент');
    final standardCtrl = TextEditingController(text: initial.standard);
    String material = initial.defaultMaterial;
    bool useRadiusFactor = initial.fixedLengthMm == null;
    double radiusFactor = initial.radiusFactor ?? 1.5;
    double fixedLength = initial.fixedLengthMm ?? 100.0;
    double branchLength = initial.branchLengthMm ?? 80.0;
    WeldType weldType = initial.weldType;
    bool cutsMainPipe = initial.cutsMainPipe;
    FlangeConnectionType fcType = initial.flangeConnectionType ?? FlangeConnectionType.toEquipment;
    int? customWeldCount = initial.defaultWeldCount;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.build_circle_outlined, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(baseDef != null ? 'Создать на основе «${baseDef.name}»' : 'Конструктор фасонного элемента'),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Тип элемента (Архетип)
                    DropdownButtonFormField<FittingArchetype>(
                      isExpanded: true,
                      initialValue: currentArchetype,
                      decoration: const InputDecoration(labelText: 'Тип (архетип) детали', border: OutlineInputBorder()),
                      items: FittingArchetype.values.map((a) {
                        return DropdownMenuItem(value: a, child: Text(a.displayName, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setModalState(() {
                          currentArchetype = val;
                          if (val == FittingArchetype.elbow) {
                            standardCtrl.text = 'ГОСТ 17375-2001';
                            useRadiusFactor = true;
                          } else if (val == FittingArchetype.tee) {
                            standardCtrl.text = 'ГОСТ 17376-2001';
                            cutsMainPipe = true;
                          } else if (val == FittingArchetype.directBranch) {
                            standardCtrl.text = 'ГОСТ 16037-80 У18';
                            weldType = WeldType.u18;
                            cutsMainPipe = false;
                          } else if (val == FittingArchetype.flange) {
                            standardCtrl.text = 'ГОСТ 33259-2015';
                          } else if (val == FittingArchetype.reducer) {
                            standardCtrl.text = 'ГОСТ 17378-2001';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Наименование элемента', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: standardCtrl,
                      decoration: const InputDecoration(labelText: 'Нормативный стандарт (ГОСТ / ТУ / ОСТ)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: material,
                      decoration: const InputDecoration(labelText: 'Марка стали по умолчанию', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Сталь 20', child: Text('Сталь 20 (ГОСТ 1050-2013)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '09Г2С', child: Text('09Г2С (ГОСТ 19281-2014)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '12Х18Н10Т', child: Text('12Х18Н10Т (Нержавеющая)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '10Г2', child: Text('10Г2', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Ст3сп', child: Text('Ст3сп', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) => setModalState(() => material = val ?? 'Сталь 20'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Геометрические параметры и строительные длины:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    // Параметры для отвода
                    if (currentArchetype == FittingArchetype.elbow) ...[
                      DropdownButtonFormField<bool>(
                        isExpanded: true,
                        initialValue: useRadiusFactor,
                        decoration: const InputDecoration(labelText: 'Расчет радиуса гиба R'),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('Коэффициент радиуса (R = k × DN)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: false, child: Text('Фиксированный радиус в мм', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setModalState(() => useRadiusFactor = v ?? true),
                      ),
                      const SizedBox(height: 8),
                      if (useRadiusFactor) ...[
                        Text('Коэффициент k = $radiusFactor (при DN=100 вычет R = ${(radiusFactor * 100).round()} мм):'),
                        Slider(
                          value: radiusFactor,
                          min: 0.5,
                          max: 6.0,
                          divisions: 22,
                          label: '$radiusFactor × DN',
                          onChanged: (v) => setModalState(() => radiusFactor = (v * 10).round() / 10.0),
                        ),
                      ] else ...[
                        TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Точный радиус гиба (мм)', suffixText: 'мм'),
                          controller: TextEditingController(text: fixedLength.toStringAsFixed(0)),
                          onChanged: (v) => fixedLength = double.tryParse(v) ?? fixedLength,
                        ),
                      ],
                    ],
                    // Параметры для тройника
                    if (currentArchetype == FittingArchetype.tee) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Строительная длина L (мм)', suffixText: 'мм'),
                              controller: TextEditingController(text: fixedLength.toStringAsFixed(0)),
                              onChanged: (v) => fixedLength = double.tryParse(v) ?? fixedLength,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Вылет ответвления H (мм)', suffixText: 'мм'),
                              controller: TextEditingController(text: branchLength.toStringAsFixed(0)),
                              onChanged: (v) => branchLength = double.tryParse(v) ?? branchLength,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Параметры для фланца
                    if (currentArchetype == FittingArchetype.flange) ...[
                      DropdownButtonFormField<FlangeConnectionType>(
                        isExpanded: true,
                        initialValue: fcType,
                        decoration: const InputDecoration(labelText: 'Исполнение фланцевого узла'),
                        items: FlangeConnectionType.values.map((fc) => DropdownMenuItem(value: fc, child: Text(fc.displayName, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setModalState(() => fcType = val ?? FlangeConnectionType.toEquipment),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Строительная длина (толщина) фланца L (мм)', suffixText: 'мм'),
                        controller: TextEditingController(text: fixedLength.toStringAsFixed(0)),
                        onChanged: (v) => fixedLength = double.tryParse(v) ?? fixedLength,
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text('Настройки сварных стыков:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<WeldType>(
                            isExpanded: true,
                            initialValue: weldType,
                            decoration: const InputDecoration(labelText: 'Тип шва ГОСТ 16037'),
                            items: WeldType.values.map((w) => DropdownMenuItem(value: w, child: Text('${w.shortName} (${w.gostCode})', overflow: TextOverflow.ellipsis))).toList(),
                            onChanged: (val) => setModalState(() => weldType = val ?? WeldType.c17),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            isExpanded: true,
                            initialValue: customWeldCount,
                            decoration: const InputDecoration(labelText: 'Число стыков детали'),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('По ГОСТ стандарту', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 1, child: Text('1 стык (к оборуд.)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 2, child: Text('2 стыка (пара/отвод)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 3, child: Text('3 стыка (тройник)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 4, child: Text('4 стыка (крест)', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (val) => setModalState(() => customWeldCount = val),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
              FilledButton(
                onPressed: () {
                  final fittingType = _resolveFittingType(currentArchetype);
                  final customDef = FittingDefinition(
                    id: 'custom_${currentArchetype.name}_${_uuid.v4()}',
                    name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'Пользовательская деталь',
                    archetype: currentArchetype,
                    fittingType: fittingType,
                    standard: standardCtrl.text.trim().isNotEmpty ? standardCtrl.text.trim() : 'ТУ/ГОСТ',
                    defaultMaterial: material,
                    radiusFactor: useRadiusFactor && currentArchetype == FittingArchetype.elbow ? radiusFactor : null,
                    fixedLengthMm: (!useRadiusFactor || currentArchetype != FittingArchetype.elbow) ? fixedLength : null,
                    branchLengthMm: currentArchetype == FittingArchetype.tee ? branchLength : null,
                    weldType: weldType,
                    cutsMainPipe: cutsMainPipe,
                    isCustom: true,
                    defaultWeldCount: customWeldCount,
                    flangeConnectionType: currentArchetype == FittingArchetype.flange ? fcType : null,
                  );

                  catalog.addCustomDefinition(customDef);
                  Navigator.of(ctx).pop();
                  setState(() {});
                  widget.network.recalculateSpools();
                  widget.onCatalogChanged?.call();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Деталь «${customDef.name}» добавлена в коллекцию')),
                  );
                },
                child: const Text('Сохранить деталь'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _applyDefinitionToSelectedNode(FittingDefinition def) {
    if (widget.selectedNodeId == null) return;
    final nodeId = widget.selectedNodeId!;
    final oldFit = widget.network.fittings[nodeId];
    if (oldFit == null) return;

    final updated = oldFit.copyWith(
      fittingType: def.fittingType,
      definitionId: def.id,
      name: def.name,
      standard: def.standard,
      material: def.defaultMaterial,
      weldType: def.weldType,
      cutsMainPipe: def.cutsMainPipe,
      radiusMm: def.fittingType == FittingType.directBranch
          ? 0.0
          : (def.radiusFactor != null ? def.radiusFactor! * oldFit.dn : oldFit.radiusMm),
      customRadiusMm: def.fittingType == FittingType.directBranch
          ? 0.0
          : (def.fixedLengthMm ?? (def.radiusFactor != null ? def.radiusFactor! * oldFit.dn : null)),
      buildingLengthMm: def.fixedLengthMm,
      branchLengthMm: def.branchLengthMm,
      flangeConnectionType: def.flangeConnectionType ?? oldFit.flangeConnectionType,
      customWeldCount: def.defaultWeldCount,
    );

    widget.network.updateFitting(nodeId, updated);
    widget.onCatalogChanged?.call();
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('К узлу $nodeId применен элемент «${def.name}»')),
    );
  }

  bool _isCompatible(Fitting fit, FittingDefinition def) {
    switch (fit.fittingType) {
      case FittingType.elbow90:
      case FittingType.elbow45:
        return def.archetype == FittingArchetype.elbow;
      case FittingType.tee:
      case FittingType.directBranch:
        return def.archetype == FittingArchetype.tee || def.archetype == FittingArchetype.directBranch;
      case FittingType.reducerConcentric:
      case FittingType.reducerEccentric:
        return def.archetype == FittingArchetype.reducer;
      case FittingType.flange:
        return def.archetype == FittingArchetype.flange;
      case FittingType.cap:
        return def.archetype == FittingArchetype.cap;
      case FittingType.cross:
        return def.archetype == FittingArchetype.cross;
    }
  }

  FittingType _resolveFittingType(FittingArchetype archetype) {
    switch (archetype) {
      case FittingArchetype.elbow:
        return FittingType.elbow90;
      case FittingArchetype.tee:
        return FittingType.tee;
      case FittingArchetype.directBranch:
        return FittingType.directBranch;
      case FittingArchetype.reducer:
        return FittingType.reducerConcentric;
      case FittingArchetype.flange:
        return FittingType.flange;
      case FittingArchetype.cap:
        return FittingType.cap;
      case FittingArchetype.cross:
        return FittingType.cross;
    }
  }

  IconData _getArchetypeIcon(FittingArchetype archetype) {
    switch (archetype) {
      case FittingArchetype.elbow:
        return Icons.turn_right;
      case FittingArchetype.tee:
      case FittingArchetype.directBranch:
        return Icons.alt_route;
      case FittingArchetype.reducer:
        return Icons.filter_list;
      case FittingArchetype.flange:
        return Icons.fiber_manual_record_outlined;
      case FittingArchetype.cap:
        return Icons.block;
      case FittingArchetype.cross:
        return Icons.add;
    }
  }

  String _formatDeduction(FittingDefinition def) {
    if (def.fixedLengthMm != null && def.fixedLengthMm! > 0) {
      return 'L = ${def.fixedLengthMm!.toStringAsFixed(0)} мм';
    }
    if (def.radiusFactor != null) {
      return 'R = ${def.radiusFactor} × DN';
    }
    return 'Табличный';
  }

  String _formatWelds(FittingDefinition def) {
    final weldCount = def.defaultWeldCount ??
        (def.archetype == FittingArchetype.elbow
            ? 2
            : (def.archetype == FittingArchetype.tee
                ? 3
                : (def.archetype == FittingArchetype.directBranch ? 1 : 2)));
    return '$weldCount стыка ${def.weldType.shortName}';
  }
}
