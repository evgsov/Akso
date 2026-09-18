import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/math/axonometry_projector.dart';
import '../../core/math/snap_engine.dart';
import '../../domain/enums/fitting_type.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/enums/valve_type.dart';
import '../../domain/enums/weld_type.dart';
import '../../domain/models/callout.dart';
import '../../domain/models/construction_axis.dart';
import '../../domain/models/equipment.dart';
import '../../domain/models/linear_dimension.dart';
import '../../domain/models/network_history_manager.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/pipe_dimension.dart';
import '../../domain/models/pipe_segment.dart';
import '../../domain/models/pipe_spool.dart';
import '../../domain/models/pipe_support.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/project_model.dart';
import '../../domain/services/element_3d_geometry.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/recent_projects_manager.dart';
import '../../data/repositories/recovery_repository.dart';
import 'controllers/selection_controller.dart';
import 'controllers/tracing_controller.dart';
import 'painters/callout_painter.dart';
import 'painters/pipe_painter.dart';

const _uuid = Uuid();

enum CanvasTool {
  trace, // Черчение труб
  select, // Выбор и перемещение узлов/стояков
  move, // Перемещение выделенных элементов с базовой точкой
  copy, // Копирование выделенных элементов с базовой точкой
  rotate, // Поворот выделенных элементов вокруг базовой точки
  dimension, // Линейные размеры по ГОСТ
  insertValve, // Врезка арматуры
  insertReducer, // Врезка перехода диаметров
  insertWeld, // Врезка сварного стыка
  insertFlange, // Врезка фланцев
  insertCap, // Установка заглушки / днища
  insertSupport, // Установка опор и подвесок
  drawAxis, // Черчение строительных осей
  insertEquipment, // Размещение оборудования со штуцерами
  orbit, // 3D вращение сцены
  pan, // Панорамирование сцены (рука)
}

enum UiLayoutMode {
  desktopCad, // Профессиональный CAD-стиль с тулбарами, статус-баром, options-баром
  tabletTouch, // Сенсорный стиль с чистым холстом и плавающим островом
  auto, // Автоматический выбор по ширине экрана
}

/// Контроллер взаимодействия с холстом (стилус, мышь, мультитач, привязки, история)
class PipingInputController extends ChangeNotifier {
  PipingNetwork network;
  AxonometryProjector projector;

  CanvasTool currentTool = CanvasTool.trace;
  ValveType selectedValveType = ValveType.gateValve;
  String currentWelderStamp = 'ИВ-24';
  WeldType currentWeldType = WeldType.c17;

  int targetReducerDn = 50;
  bool isEccentricReducer = false;

  bool isFlangePair = true;
  int flangePressurePn = 16;
  String activeMaterial = 'Сталь 20';
  PipeSupportType selectedSupportType = PipeSupportType.sliding;

  String activeSystemId = 'sys_b1';
  int activeDn = 25;
  double activeWallThicknessMm = 3.2;
  double currentElevationZ = 0.0; // Текущая рабочая отметка в мм

  // Режим компоновки UI
  UiLayoutMode layoutMode = UiLayoutMode.auto;

  bool isSaving = false;
  bool isLoading = false;
  bool isVolumeMode = false;
  bool isCenterlineMode = false;

  void setVolumeMode(bool value) {
    if (isVolumeMode == value) return;
    isVolumeMode = value;
    notifyListeners();
  }

  void toggleCenterlineMode() {
    isCenterlineMode = !isCenterlineMode;
    notifyListeners();
  }

  void setCenterlineMode(bool value) {
    if (isCenterlineMode == value) return;
    isCenterlineMode = value;
    notifyListeners();
  }

  // История и отмена (Undo / Redo)
  late final NetworkHistoryManager history;

  // Движок магнитных привязок и полярных углов
  final SnapEngine snapEngine = const SnapEngine();
  SnapResult? currentSnapResult;
  bool isSnapEnabled = true;
  bool showGrid = true;

  // Модульные подконтроллеры селекции и трассировки
  final SelectionController selectionController = SelectionController();
  final TracingController tracingController = TracingController();

  // Привязка свойств трассировки к TracingController
  AngleSnapMode get angleSnapMode => tracingController.angleSnapMode;
  set angleSnapMode(AngleSnapMode val) => tracingController.angleSnapMode = val;

  double get customAngleDegrees => tracingController.customAngleDegrees;
  set customAngleDegrees(double val) => tracingController.customAngleDegrees = val;

  Node3D? get traceStartNode => tracingController.traceStartNode;
  set traceStartNode(Node3D? val) => tracingController.traceStartNode = val;

  Node3D? get axisStartNode => tracingController.axisStartNode;
  set axisStartNode(Node3D? val) => tracingController.axisStartNode = val;

  String get currentAxisLabel => tracingController.currentAxisLabel;
  set currentAxisLabel(String val) => tracingController.currentAxisLabel = val;

  bool get isBuildingGridAxis => tracingController.isBuildingGridAxis;
  set isBuildingGridAxis(bool val) => tracingController.isBuildingGridAxis = val;

  // Привязка интерактивного состояния и селекции к SelectionController
  String? get selectedNodeId => selectionController.selectedNodeId;
  set selectedNodeId(String? id) => selectionController.selectedNodeId = id;

  String? get selectedSegmentId => selectionController.selectedSegmentId;
  set selectedSegmentId(String? id) => selectionController.selectedSegmentId = id;

  String? get selectedSpoolId => selectionController.selectedSpoolId;
  set selectedSpoolId(String? id) => selectionController.selectedSpoolId = id;

  String? get selectedEquipmentId => selectionController.selectedEquipmentId;
  set selectedEquipmentId(String? id) => selectionController.selectedEquipmentId = id;

  String? get selectedCalloutId => selectionController.selectedCalloutId;
  set selectedCalloutId(String? id) => selectionController.selectedCalloutId = id;

  String? get selectedAxisId => selectionController.selectedAxisId;
  set selectedAxisId(String? id) => selectionController.selectedAxisId = id;

  String? get selectedDimensionId => selectionController.selectedDimensionId;
  set selectedDimensionId(String? id) => selectionController.selectedDimensionId = id;

  String? get selectedValveId => selectionController.selectedValveId;
  set selectedValveId(String? id) => selectionController.selectedValveId = id;

  String? get selectedSupportId => selectionController.selectedSupportId;
  set selectedSupportId(String? id) => selectionController.selectedSupportId = id;

  String? get selectedWeldId => selectionController.selectedWeldId;
  set selectedWeldId(String? id) => selectionController.selectedWeldId = id;

  String? hoveredNodeId;

  // Мультиселекция и рамочный выбор
  Set<String> get selectedNodeIds => selectionController.selectedNodeIds;
  Set<String> get selectedSegmentIds => selectionController.selectedSegmentIds;
  Set<String> get selectedSpoolIds => selectionController.selectedSpoolIds;
  Set<String> get selectedEquipmentIds => selectionController.selectedEquipmentIds;
  Set<String> get selectedAxisIds => selectionController.selectedAxisIds;
  Set<String> get selectedDimensionIds => selectionController.selectedDimensionIds;

  void selectSpool(String? spoolId) {
    selectionController.clearSelection();
    selectionController.selectedSpoolId = spoolId;
    if (spoolId != null) selectionController.selectedSpoolIds.add(spoolId);
    notifyListeners();
  }

  Rect? get selectionBoxRect => selectionController.selectionBoxRect;
  set selectionBoxRect(Rect? val) => selectionController.selectionBoxRect = val;

  Offset? get boxSelectStart => selectionController.boxSelectStart;
  set boxSelectStart(Offset? val) => selectionController.boxSelectStart = val;

  bool get isCrossingSelection => selectionController.isCrossingSelection;
  set isCrossingSelection(bool val) => selectionController.isCrossingSelection = val;

  // Инструменты редактирования (Move, Copy, Rotate с базовой точкой)
  Node3D? modifyBasePointWorld;
  Offset? modifyBasePointScreen;
  Offset? modifyCurrentPointScreen;

  // Линейные размеры (ГОСТ 2.307)
  Node3D? dimensionStartNode;
  Node3D? dimensionEndNode;
  String? dimensionStartNodeId;
  String? dimensionEndNodeId;
  double dimensionOffset = 35.0;
  Offset? currentCursorScreenPos;

  // Фиксация углов 90° (Орто-трассировка и параллельный сдвиг)
  bool isAngleLocked = true;
  void toggleAngleLock() {
    isAngleLocked = !isAngleLocked;
    notifyListeners();
  }

  // Режим перетаскивания и ручек (Grip Editing)
  bool isDraggingNode = false;
  bool isDraggingSegment = false;
  bool isDraggingEquipment = false;
  bool isDraggingCallout = false;
  bool isDraggingValve = false;
  bool isDraggingSupport = false;
  bool isDraggingWeld = false;
  String? _potentialDragNodeId;
  Offset? _dragNodeStartScreenPos;
  String? _potentialDragSegmentId;
  Offset? _dragSegmentStartScreenPos;
  Node3D? _dragSegmentStartWorldPos;
  Node3D? _initialSegmentStartNode;
  Node3D? _initialSegmentEndNode;
  String? _potentialDragEquipmentId;
  Offset? _dragEquipmentStartScreenPos;
  String? _potentialDragValveId;
  Offset? _dragValveStartScreenPos;
  String? _potentialDragSupportId;
  Offset? _dragSupportStartScreenPos;
  String? _potentialDragWeldId;
  Offset? _dragWeldStartScreenPos;
  Node3D? _dragEquipmentStartPos;
  Offset? _dragCalloutStartScreenPos;
  double _dragCalloutInitialOffsetX = 0.0;
  double _dragCalloutInitialOffsetY = 0.0;
  Timer? _longPressTimer;
  bool _canDragElement = false;
  bool enableDragDelay = true;

  // Grip Mode: активный перенос узла кликом мыши (AutoCAD Grip Editing)
  String? activeGripNodeId;
  Node3D? _gripOriginalNodePosition;

  // Grip Mode для строительных осей
  String? activeGripAxisId;
  bool? isGripAxisStart;

  // Модификаторы для рамочного выбора
  bool get _boxSelectIsShift => selectionController.boxSelectIsShift;
  set _boxSelectIsShift(bool val) => selectionController.boxSelectIsShift = val;
  bool get _boxSelectIsCtrl => selectionController.boxSelectIsCtrl;
  set _boxSelectIsCtrl(bool val) => selectionController.boxSelectIsCtrl = val;

  late ProjectModel currentProject;
  final IProjectRepository projectRepository;
  final RecentProjectsManager recentProjectsManager;
  String? currentFilePath;
  bool hasUnsavedChanges = false;
  bool _isInitializing = true;

  Timer? _recoveryTimer;

  PipingInputController({
    PipingNetwork? network,
    PipingNetwork? initialNetwork,
    AxonometryProjector? projector,
    IProjectRepository? projectRepository,
    IProjectRepository? repository,
    RecentProjectsManager? recentProjectsManager,
  })  : network = network ?? initialNetwork ?? PipingNetwork(),
        projector = projector ??
            const AxonometryProjector(
              projectionType: ProjectionType.gostFrontal45,
            ),
        projectRepository = repository ?? projectRepository ?? ProjectRepository(),
        recentProjectsManager = recentProjectsManager ?? RecentProjectsManager() {
    history = NetworkHistoryManager(
      maxSnapshots: 50,
      onStateRecorded: () {
        if (!_isInitializing) {
          hasUnsavedChanges = true;
        }
      },
    );
    currentProject = ProjectModel(
      id: _uuid.v4(),
      title: 'Новый проект',
      network: this.network,
    );
    history.recordState(this.network);

    _recoveryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      RecoveryRepository().saveRecovery(currentProject.copyWith(network: this.network));
    });
    _isInitializing = false;
  }

  Future<void> tryLoadRecovery() async {
    final recoveredProject = await RecoveryRepository().loadRecovery();
    if (recoveredProject != null) {
      currentProject = recoveredProject;
      network = recoveredProject.network;
      history.recordState(network);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _recoveryTimer?.cancel();
    super.dispose();
  }

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  void undo() {
    if (history.undo(network)) {
      cancelCurrentOperation(keepTool: true);
      hasUnsavedChanges = true;
      notifyListeners();
    }
  }

  void redo() {
    if (history.redo(network)) {
      cancelCurrentOperation(keepTool: true);
      hasUnsavedChanges = true;
      notifyListeners();
    }
  }

  /// Помечает проект как содержащий несохраненные изменения
  void markDirty() {
    if (!hasUnsavedChanges) {
      hasUnsavedChanges = true;
      notifyListeners();
    }
  }

  void recordSnapshot() {
    history.recordState(network);
    notifyListeners();
  }

  /// Полная очистка выделения всех элементов
  void clearSelection() {
    selectionController.clearSelection();
    notifyListeners();
  }

  /// Превью размерной линии в процессе черчения
  LinearDimension? get previewDimension {
    if (currentTool != CanvasTool.dimension || dimensionStartNode == null) return null;
    final endPoint = dimensionEndNode ??
        (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
            ? currentSnapResult!.worldPoint
            : (currentCursorScreenPos != null
                ? projector.unproject(currentCursorScreenPos!, currentElevationZ)
                : dimensionStartNode!));

    return LinearDimension(
      id: 'preview_dim',
      startPoint: dimensionStartNode!,
      endPoint: endPoint,
      offsetDistance: dimensionOffset,
    );
  }

  /// Отмена текущей операции (по клавише Esc, ПКМ или кнопке на экране)
  void cancelCurrentOperation({bool keepTool = false}) {
    _longPressTimer?.cancel();
    _canDragElement = false;
    clearSelection();
    traceStartNode = null;
    axisStartNode = null;
    currentCursorScreenPos = null;
    currentSnapResult = null;
    selectedNodeId = null;
    selectedSegmentId = null;
    selectedEquipmentId = null;
    selectedCalloutId = null;
    selectedDimensionId = null;
    selectedAxisId = null;
    selectedNodeIds.clear();
    selectedEquipmentIds.clear();
    selectedAxisIds.clear();
    selectedDimensionIds.clear();
    modifyBasePointWorld = null;
    modifyBasePointScreen = null;
    modifyCurrentPointScreen = null;
    selectionBoxRect = null;
    boxSelectStart = null;
    dimensionStartNode = null;
    dimensionEndNode = null;
    dimensionStartNodeId = null;
    dimensionEndNodeId = null;
    dimensionOffset = 35.0;
    isDraggingNode = false;
    isDraggingSegment = false;
    isDraggingEquipment = false;
    isDraggingCallout = false;
    isDraggingValve = false;
    isDraggingSupport = false;
    isDraggingWeld = false;
    _potentialDragNodeId = null;
    _dragNodeStartScreenPos = null;
    _potentialDragSegmentId = null;
    _dragSegmentStartScreenPos = null;
    _dragSegmentStartWorldPos = null;
    _initialSegmentStartNode = null;
    _initialSegmentEndNode = null;
    _potentialDragEquipmentId = null;
    _dragEquipmentStartScreenPos = null;
    _potentialDragValveId = null;
    _dragValveStartScreenPos = null;
    _potentialDragSupportId = null;
    _dragSupportStartScreenPos = null;
    _potentialDragWeldId = null;
    _dragWeldStartScreenPos = null;
    if (activeGripNodeId != null && _gripOriginalNodePosition != null) {
      network.moveNode(
        activeGripNodeId!,
        _gripOriginalNodePosition!.x,
        _gripOriginalNodePosition!.y,
        _gripOriginalNodePosition!.z,
      );
      activeGripNodeId = null;
      _gripOriginalNodePosition = null;
    }
    activeGripAxisId = null;
    isGripAxisStart = null;
    _dragEquipmentStartPos = null;
    _dragCalloutStartScreenPos = null;
    if (!keepTool &&
        currentTool != CanvasTool.select &&
        currentTool != CanvasTool.trace &&
        currentTool != CanvasTool.pan) {
      currentTool = CanvasTool.select;
    }
    notifyListeners();
  }

  void setTool(CanvasTool tool) {
    if (currentTool != tool) {
      final isModifyTool = tool == CanvasTool.move || tool == CanvasTool.copy || tool == CanvasTool.rotate;
      final wasModifyTool = currentTool == CanvasTool.move || currentTool == CanvasTool.copy || currentTool == CanvasTool.rotate;
      if (!isModifyTool && !(tool == CanvasTool.select && wasModifyTool)) {
        cancelCurrentOperation(keepTool: true);
      } else {
        modifyBasePointWorld = null;
        modifyBasePointScreen = null;
        modifyCurrentPointScreen = null;
      }
      currentTool = tool;
      notifyListeners();
    }
  }

  void setSelectedValveType(ValveType type) {
    selectedValveType = type;
    notifyListeners();
  }

  void setSelectedSupportType(PipeSupportType type) {
    selectedSupportType = type;
    notifyListeners();
  }

  void setCurrentWeldType(WeldType type) {
    currentWeldType = type;
    notifyListeners();
  }

  void setCurrentWelderStamp(String stamp) {
    currentWelderStamp = stamp;
    notifyListeners();
  }

  void setTargetReducerDn(int dn) {
    targetReducerDn = dn;
    notifyListeners();
  }

  void setIsEccentricReducer(bool val) {
    isEccentricReducer = val;
    notifyListeners();
  }

  bool get useDirectBranch => network.catalog.defaultBranchId == 'direct_branch_u18';
  set useDirectBranch(bool val) {
    network.catalog.defaultBranchId = val ? 'direct_branch_u18' : 'tee_gost_17376';
    notifyListeners();
  }

  void setUseDirectBranch(bool val) {
    useDirectBranch = val;
  }

  void setIsFlangePair(bool val) {
    isFlangePair = val;
    notifyListeners();
  }

  void setFlangePressurePn(int pn) {
    flangePressurePn = pn;
    notifyListeners();
  }

  void setActiveMaterial(String material) {
    activeMaterial = material;
    notifyListeners();
  }

  void setAngleSnapMode(AngleSnapMode mode) {
    angleSnapMode = mode;
    notifyListeners();
  }

  void setCustomAngleDegrees(double deg) {
    customAngleDegrees = deg;
    notifyListeners();
  }

  void toggleSnap() {
    isSnapEnabled = !isSnapEnabled;
    notifyListeners();
  }

  void toggleGrid() {
    showGrid = !showGrid;
    notifyListeners();
  }

  void setLayoutMode(UiLayoutMode mode) {
    layoutMode = mode;
    notifyListeners();
  }

  void setCurrentAxisLabel(String label) {
    currentAxisLabel = label;
    notifyListeners();
  }

  void setIsBuildingGridAxis(bool val) {
    if (isBuildingGridAxis == val) return;
    isBuildingGridAxis = val;
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }

  /// Смена типа проекции (ГОСТ 45°, ISO 30°, Орбита 3D)
  void setProjectionType(ProjectionType type) {
    if (type == ProjectionType.orbit3d && projector.projectionType != ProjectionType.orbit3d) {
      prepareOrbit();
    }
    projector = projector.copyWith(projectionType: type);
    if (type == ProjectionType.orbit3d) {
      currentTool = CanvasTool.orbit;
    } else if (currentTool == CanvasTool.orbit) {
      currentTool = CanvasTool.trace;
    }
    notifyListeners();
  }

  /// Смена активной системы (В1, Т3, К1...)
  void setActiveSystem(String systemId) {
    activeSystemId = systemId;
    final sys = network.systems[systemId];
    if (sys != null) {
      activeDn = sys.defaultDn;
      activeMaterial = sys.defaultMaterial;
      final dim = network.pipeCatalog.getDimension(activeDn);
      if (dim != null) {
        activeWallThicknessMm = dim.defaultWallThicknessMm;
      }
    }
    notifyListeners();
  }

  /// Смена диаметра DN
  void setActiveDn(int dn) {
    activeDn = dn;
    final dim = network.pipeCatalog.getDimension(dn);
    if (dim != null) {
      activeWallThicknessMm = dim.defaultWallThicknessMm;
    }
    notifyListeners();
  }

  /// Смена толщины стенки S (мм)
  void setActiveWallThickness(double wallThicknessMm) {
    activeWallThicknessMm = wallThicknessMm;
    notifyListeners();
  }

  /// Создание вертикального стояка / подъема на отметку при активном черчении
  /// Если черчение не ведется, просто устанавливает рабочую отметку трассировки
  void addVerticalRiser(double targetElevationZ) {
    // Определяем базовый узел для подъема/опуска
    final baseNode = traceStartNode ?? (currentTool == CanvasTool.select && selectedNodeId != null ? network.nodes[selectedNodeId!] : null);

    if (baseNode == null) {
      // Черчение не ведется: труба НЕ создается, просто выбираем уровень рабочей плоскости
      currentElevationZ = targetElevationZ;
      notifyListeners();
      return;
    }

    final newNode = Node3D(
      id: 'node_${_uuid.v4()}',
      x: baseNode.x,
      y: baseNode.y,
      z: targetElevationZ,
    );
    network.nodes[newNode.id] = newNode;

    final dim = network.pipeCatalog.getDimension(activeDn);
    final outerD = dim?.outerDiameterMm;

    final segId = 'seg_${_uuid.v4()}';
    final seg = PipeSegment(
      id: segId,
      startNodeId: baseNode.id,
      endNodeId: newNode.id,
      systemId: activeSystemId,
      dn: activeDn,
      outerDiameterMm: outerD,
      wallThicknessMm: activeWallThicknessMm,
      material: activeMaterial,
    );
    network.addSegment(seg);
    history.recordState(network);

    traceStartNode = newNode;
    selectedNodeId = newNode.id;
    currentElevationZ = targetElevationZ;
    notifyListeners();
  }

  /// Обработка нажатия на холст
  void handlePointerDown(Offset screenPos, {bool isShift = false, bool isCtrl = false}) {
    _longPressTimer?.cancel();
    if (!enableDragDelay) {
      _canDragElement = true;
    } else {
      _canDragElement = false;
      _longPressTimer = Timer(const Duration(milliseconds: 200), () {
        _canDragElement = true;
        if (hasListeners) {
          notifyListeners();
        }
      });
    }
    currentCursorScreenPos = screenPos;

    // Обновляем привязку
    _updateSnap(screenPos);

    // 1. Завершение Grip-переноса узла кликом ЛКМ
    if (activeGripNodeId != null) {
      final snapWorld = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
          ? currentSnapResult!.worldPoint
          : _snapToGrid(projector.unproject(screenPos, currentElevationZ));
      network.moveNode(activeGripNodeId!, snapWorld.x, snapWorld.y, snapWorld.z);
      _checkAndMergeOpenNodes();
      history.recordState(network);
      activeGripNodeId = null;
      _gripOriginalNodePosition = null;
      notifyListeners();
      return;
    }

    // 2. Завершение Grip-растяжения оси кликом ЛКМ
    if (activeGripAxisId != null && isGripAxisStart != null) {
      final snapWorld = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
          ? currentSnapResult!.worldPoint
          : _snapToGrid(projector.unproject(screenPos, currentElevationZ));
      final axis = network.axes[activeGripAxisId!];
      if (axis != null) {
        if (isGripAxisStart == true) {
          network.axes[activeGripAxisId!] = axis.copyWith(startPoint: snapWorld);
        } else {
          network.axes[activeGripAxisId!] = axis.copyWith(endPoint: snapWorld);
        }
        history.recordState(network);
      }
      activeGripAxisId = null;
      isGripAxisStart = null;
      notifyListeners();
      return;
    }

    var hitNodeId = currentSnapResult?.type == SnapType.node
        ? currentSnapResult!.snappedNodeId
        : _findNodeAtScreenPos(screenPos);
    if (hitNodeId == null && currentTool == CanvasTool.select) {
      hitNodeId = _findFittingAtScreenPos(screenPos);
    }

    final hitSegId = ((currentSnapResult?.type == SnapType.segmentAxis ||
                currentSnapResult?.type == SnapType.midpoint ||
                currentSnapResult?.type == SnapType.perpendicular) &&
            network.segments.containsKey(currentSnapResult!.snappedSegmentId))
        ? currentSnapResult!.snappedSegmentId
        : _findSegmentAtScreenPos(screenPos);

    switch (currentTool) {
      case CanvasTool.pan:
        // Панорамирование обрабатывается в drag
        break;

      case CanvasTool.drawAxis:
        if (axisStartNode == null) {
          final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
              ? currentSnapResult!.worldPoint
              : projector.unproject(screenPos, currentElevationZ);
          axisStartNode = Node3D(
            id: 'axis_start_${_uuid.v4()}',
            x: snapWorld.x,
            y: snapWorld.y,
            z: currentElevationZ,
          );
        } else {
          final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
              ? currentSnapResult!.worldPoint
              : projector.unproject(screenPos, currentElevationZ);
          final axisEndNode = Node3D(
            id: 'axis_end_${_uuid.v4()}',
            x: snapWorld.x,
            y: snapWorld.y,
            z: currentElevationZ,
          );
          final axisId = 'axis_${_uuid.v4()}';
          network.axes[axisId] = ConstructionAxis(
            id: axisId,
            label: isBuildingGridAxis ? currentAxisLabel : '',
            startPoint: axisStartNode!,
            endPoint: axisEndNode,
            isBuildingGrid: isBuildingGridAxis,
          );
          history.recordState(network);

          // Инкремент марки, только если это строительная ось и число
          if (isBuildingGridAxis) {
            final num = int.tryParse(currentAxisLabel);
            if (num != null) {
              currentAxisLabel = '${num + 1}';
            }
          }
          axisStartNode = null;
        }
        break;

      case CanvasTool.dimension:
        final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
            ? currentSnapResult!.worldPoint
            : ((hitNodeId != null ? network.nodes[hitNodeId] : null) ?? projector.unproject(screenPos, currentElevationZ));
        final snappedNodeId = (currentSnapResult?.type == SnapType.node ? currentSnapResult!.snappedNodeId : hitNodeId);

        if (dimensionStartNode == null) {
          dimensionStartNode = Node3D(
            id: 'dim_start_${_uuid.v4()}',
            x: snapWorld.x,
            y: snapWorld.y,
            z: snapWorld.z,
          );
          dimensionStartNodeId = snappedNodeId;
        } else if (dimensionEndNode == null) {
          dimensionEndNode = Node3D(
            id: 'dim_end_${_uuid.v4()}',
            x: snapWorld.x,
            y: snapWorld.y,
            z: snapWorld.z,
          );
          dimensionEndNodeId = snappedNodeId;
          _updateDimensionOffset(screenPos);
        } else {
          _updateDimensionOffset(screenPos);
          final dimId = 'dim_${_uuid.v4()}';
          final newDim = LinearDimension(
            id: dimId,
            startPoint: dimensionStartNode!,
            endPoint: dimensionEndNode!,
            startNodeId: dimensionStartNodeId,
            endNodeId: dimensionEndNodeId,
            offsetDistance: dimensionOffset == 0.0 ? 35.0 : dimensionOffset,
          );
          network.addDimension(newDim);
          history.recordState(network);
          dimensionStartNode = null;
          dimensionEndNode = null;
          dimensionStartNodeId = null;
          dimensionEndNodeId = null;
          dimensionOffset = 35.0;
        }
        break;

      case CanvasTool.trace:
        if (hitNodeId != null) {
          if (traceStartNode == null) {
            traceStartNode = network.nodes[hitNodeId];
            selectedNodeId = hitNodeId;
          } else {
            // Завершение сегмента в существующем узле
            _finishTraceSegment(screenPos);
          }
        } else if (traceStartNode != null) {
          // Завершаем сегмент в новой точке или на трубе
          _finishTraceSegment(screenPos);
        } else if (currentSnapResult != null &&
            currentSnapResult!.type == SnapType.equipmentFace &&
            currentSnapResult!.snappedEquipmentId != null &&
            network.equipments.containsKey(currentSnapResult!.snappedEquipmentId)) {
          final eqId = currentSnapResult!.snappedEquipmentId!;
          final w = currentSnapResult!.worldPoint;
          final nozzleNode = network.attachNozzleAtWorldPoint(
            eqId,
            w,
            dn: activeDn,
            face: currentSnapResult!.snappedEquipmentFace,
          );
          history.recordState(network);
          traceStartNode = nozzleNode;
          selectedNodeId = nozzleNode.id;
        } else if (_findEquipmentAtScreenPos(screenPos) != null &&
            network.equipments.containsKey(_findEquipmentAtScreenPos(screenPos))) {
          final hitEqId = _findEquipmentAtScreenPos(screenPos)!;
          final eq = network.equipments[hitEqId]!;
          final worldPt = projector.unproject(screenPos, eq.z + eq.height);
          final nozzleNode = network.attachNozzleAtWorldPoint(
            hitEqId,
            worldPt,
            dn: activeDn,
          );
          history.recordState(network);
          traceStartNode = nozzleNode;
          selectedNodeId = nozzleNode.id;
        } else if (hitSegId != null) {
          // Начало ответвления от существующей трубы: делим сегмент в точке касания
          final double ratio;
          if (currentSnapResult != null &&
              (currentSnapResult!.type == SnapType.midpoint || currentSnapResult!.type == SnapType.perpendicular) &&
              currentSnapResult!.snappedSegmentId == hitSegId &&
              network.segments.containsKey(hitSegId)) {
            final seg = network.segments[hitSegId]!;
            final s = network.nodes[seg.startNodeId];
            final e = network.nodes[seg.endNodeId];
            if (s != null && e != null) {
              final w = currentSnapResult!.worldPoint;
              final segLen = math.sqrt(math.pow(e.x - s.x, 2) + math.pow(e.y - s.y, 2) + math.pow(e.z - s.z, 2));
              ratio = segLen > 0.001
                  ? (math.sqrt(math.pow(w.x - s.x, 2) + math.pow(w.y - s.y, 2) + math.pow(w.z - s.z, 2)) / segLen).clamp(0.01, 0.99)
                  : 0.5;
            } else {
              ratio = 0.5;
            }
          } else {
            ratio = _calcSegmentRatio(hitSegId, screenPos);
          }
          final midNode = network.splitSegmentAtRatio(hitSegId, ratio);
          if (midNode != null) {
            history.recordState(network);
            traceStartNode = midNode;
            selectedNodeId = midNode.id;
          }
        } else {
          // Начинаем трассировку из новой точки на текущей отметке Z
          final worldNode = _snapToGrid(projector.unproject(screenPos, currentElevationZ));
          final newNode = Node3D(
            id: 'node_${_uuid.v4()}',
            x: worldNode.x,
            y: worldNode.y,
            z: currentElevationZ,
          );
          network.nodes[newNode.id] = newNode;
          history.recordState(network);
          traceStartNode = newNode;
          selectedNodeId = newNode.id;
        }
        break;

      case CanvasTool.select:
        // Проверка клика по ручкам на концах выделенной оси (Grip Handles)
        if (selectedAxisId != null && network.axes.containsKey(selectedAxisId)) {
          final axis = network.axes[selectedAxisId!]!;
          final p1 = projector.project(axis.startPoint);
          final p2 = projector.project(axis.endPoint);
          if ((screenPos - p1).distance <= 14.0) {
            activeGripAxisId = selectedAxisId;
            isGripAxisStart = true;
            notifyListeners();
            break;
          } else if ((screenPos - p2).distance <= 14.0) {
            activeGripAxisId = selectedAxisId;
            isGripAxisStart = false;
            notifyListeners();
            break;
          }
        }

        final hitCalloutId = _findCalloutAtScreenPos(screenPos);
        if (hitCalloutId != null) {
          selectedCalloutId = hitCalloutId;
          selectedNodeId = null;
          selectedSegmentId = null;
          selectedSpoolId = null;
          selectedEquipmentId = null;
          selectedDimensionId = null;
          selectedAxisId = null;
          selectedNodeIds.clear();
          selectedSegmentIds.clear();
          selectedSpoolIds.clear();
          selectedEquipmentIds.clear();
          selectedAxisIds.clear();
          selectedDimensionIds.clear();
          isDraggingCallout = true;
          _dragCalloutStartScreenPos = screenPos;
          final c = network.callouts[hitCalloutId]!;
          _dragCalloutInitialOffsetX = c.screenOffsetX;
          _dragCalloutInitialOffsetY = c.screenOffsetY;
          notifyListeners();
          break;
        }

        selectedCalloutId = null;

        final hitValveId = _findValveAtScreenPos(screenPos);
        if (hitValveId != null) {
          selectedValveId = hitValveId;
          selectedSupportId = null;
          selectedWeldId = null;
          selectedNodeId = null;
          selectedSegmentId = null;
          selectedSpoolId = null;
          selectedEquipmentId = null;
          selectedDimensionId = null;
          selectedAxisId = null;
          selectedCalloutId = null;
          selectedNodeIds.clear();
          selectedSegmentIds.clear();
          selectedSpoolIds.clear();
          selectedEquipmentIds.clear();
          selectedAxisIds.clear();
          selectedDimensionIds.clear();
          _potentialDragValveId = hitValveId;
          _dragValveStartScreenPos = screenPos;
          isDraggingValve = false;
          notifyListeners();
          break;
        }

        final hitWeldId = _findWeldAtScreenPos(screenPos);
        if (hitWeldId != null) {
          selectedWeldId = hitWeldId;
          selectedValveId = null;
          selectedSupportId = null;
          selectedNodeId = null;
          selectedSegmentId = null;
          selectedSpoolId = null;
          selectedEquipmentId = null;
          selectedDimensionId = null;
          selectedAxisId = null;
          selectedCalloutId = null;
          selectedNodeIds.clear();
          selectedSegmentIds.clear();
          selectedSpoolIds.clear();
          selectedEquipmentIds.clear();
          selectedAxisIds.clear();
          selectedDimensionIds.clear();
          _potentialDragWeldId = hitWeldId;
          _dragWeldStartScreenPos = screenPos;
          isDraggingWeld = false;
          notifyListeners();
          break;
        }

        final hitSupportId = _findSupportAtScreenPos(screenPos);
        if (hitSupportId != null) {
          selectedSupportId = hitSupportId;
          selectedValveId = null;
          selectedWeldId = null;
          selectedNodeId = null;
          selectedSegmentId = null;
          selectedSpoolId = null;
          selectedEquipmentId = null;
          selectedDimensionId = null;
          selectedAxisId = null;
          selectedCalloutId = null;
          selectedNodeIds.clear();
          selectedSegmentIds.clear();
          selectedSpoolIds.clear();
          selectedEquipmentIds.clear();
          selectedAxisIds.clear();
          selectedDimensionIds.clear();
          _potentialDragSupportId = hitSupportId;
          _dragSupportStartScreenPos = screenPos;
          isDraggingSupport = false;
          notifyListeners();
          break;
        }

        selectedValveId = null;
        selectedSupportId = null;
        selectedWeldId = null;
        selectedEquipmentId = _findEquipmentAtScreenPos(screenPos);

        if (hitNodeId != null) {
          final n = network.nodes[hitNodeId];
          if (n?.equipmentId != null) {
            selectedEquipmentId = n!.equipmentId;
            selectedEquipmentIds.add(n.equipmentId!);
          }
          if (isShift) {
            selectedNodeIds.remove(hitNodeId);
            if (selectedNodeId == hitNodeId) {
              selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
            }
            notifyListeners();
            break;
          }
          if (isCtrl) {
            if (selectedNodeIds.contains(hitNodeId)) {
              selectedNodeIds.remove(hitNodeId);
              if (selectedNodeId == hitNodeId) {
                selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
              }
            } else {
              selectedNodeIds.add(hitNodeId);
              selectedNodeId = hitNodeId;
            }
            notifyListeners();
            break;
          }

          // Повторный клик по уже выделенному единственному узлу оставляет его выделенным без залипания за курсором
          if (selectedNodeId == hitNodeId && selectedNodeIds.length == 1 && n != null) {
            _potentialDragNodeId = hitNodeId;
            _dragNodeStartScreenPos = screenPos;
            isDraggingNode = false;
            notifyListeners();
            break;
          }

          selectedNodeId = hitNodeId;
          selectedAxisId = null;
          selectedSpoolId = null;
          if (!selectedNodeIds.contains(hitNodeId)) {
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedSpoolIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedNodeIds.add(hitNodeId);
          }
          _potentialDragNodeId = hitNodeId;
          _dragNodeStartScreenPos = screenPos;
          isDraggingNode = false;
          notifyListeners();
          break;
        }

        PipeSpool? hitSpool = !isCenterlineMode ? _findSpoolAtScreenPos(screenPos) : null;
        if (hitSpool == null && !isCenterlineMode && hitSegId != null) {
          hitSpool = network.spools.values.where((s) => s.segmentId == hitSegId).firstOrNull;
        }
        if (hitSpool != null) {
          final spoolId = hitSpool.id;
          final segId = hitSpool.segmentId;
          if (isShift) {
            selectedSpoolIds.remove(spoolId);
            if (selectedSpoolId == spoolId) {
              selectedSpoolId = selectedSpoolIds.isEmpty ? null : selectedSpoolIds.first;
            }
            notifyListeners();
            break;
          }
          if (isCtrl) {
            if (selectedSpoolIds.contains(spoolId)) {
              selectedSpoolIds.remove(spoolId);
              if (selectedSpoolId == spoolId) {
                selectedSpoolId = selectedSpoolIds.isEmpty ? null : selectedSpoolIds.first;
              }
            } else {
              selectedSpoolIds.add(spoolId);
              selectedSpoolId = spoolId;
            }
            notifyListeners();
            break;
          }

          selectedSpoolId = spoolId;
          selectedSegmentId = segId;
          selectedAxisId = null;
          if (!selectedSpoolIds.contains(spoolId)) {
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedSpoolIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedSpoolIds.add(spoolId);
            selectedSegmentIds.add(segId);
          }
          _potentialDragSegmentId = segId;
          _dragSegmentStartScreenPos = screenPos;
          _dragSegmentStartWorldPos = projector.unproject(screenPos, currentElevationZ);
          isDraggingSegment = false;
          final seg = network.segments[segId];
          if (seg != null) {
            _initialSegmentStartNode = network.nodes[seg.startNodeId];
            _initialSegmentEndNode = network.nodes[seg.endNodeId];
          }
          notifyListeners();
          break;
        } else if (hitSegId != null && (isCenterlineMode || !network.isButtJoint(hitSegId))) {
          selectedSpoolId = null;
          selectedSpoolIds.clear();
          if (isShift) {
            selectedSegmentIds.remove(hitSegId);
            if (selectedSegmentId == hitSegId) {
              selectedSegmentId = selectedSegmentIds.isEmpty ? null : selectedSegmentIds.first;
            }
            notifyListeners();
            break;
          }
          if (isCtrl) {
            if (selectedSegmentIds.contains(hitSegId)) {
              selectedSegmentIds.remove(hitSegId);
              if (selectedSegmentId == hitSegId) {
                selectedSegmentId = selectedSegmentIds.isEmpty ? null : selectedSegmentIds.first;
              }
            } else {
              selectedSegmentIds.add(hitSegId);
              selectedSegmentId = hitSegId;
            }
            notifyListeners();
            break;
          }

          selectedSegmentId = hitSegId;
          selectedAxisId = null;
          if (!selectedSegmentIds.contains(hitSegId)) {
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedSpoolIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedSegmentIds.add(hitSegId);
          }
          _potentialDragSegmentId = hitSegId;
          _dragSegmentStartScreenPos = screenPos;
          _dragSegmentStartWorldPos = projector.unproject(screenPos, currentElevationZ);
          isDraggingSegment = false;
          final seg = network.segments[hitSegId];
          if (seg != null) {
            _initialSegmentStartNode = network.nodes[seg.startNodeId];
            _initialSegmentEndNode = network.nodes[seg.endNodeId];
          }
          notifyListeners();
          break;
        } else if (selectedEquipmentId != null) {
          final eqId = selectedEquipmentId!;
          if (isShift) {
            selectedEquipmentIds.remove(eqId);
            selectedEquipmentId = selectedEquipmentIds.isEmpty ? null : selectedEquipmentIds.first;
            notifyListeners();
            break;
          }
          if (isCtrl) {
            if (selectedEquipmentIds.contains(eqId)) {
              selectedEquipmentIds.remove(eqId);
              selectedEquipmentId = selectedEquipmentIds.isEmpty ? null : selectedEquipmentIds.first;
            } else {
              selectedEquipmentIds.add(eqId);
              selectedEquipmentId = eqId;
            }
            notifyListeners();
            break;
          }

          selectedEquipmentId = eqId;
          selectedAxisId = null;
          if (!selectedEquipmentIds.contains(eqId)) {
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedEquipmentIds.add(eqId);
          }
          _potentialDragEquipmentId = eqId;
          _dragEquipmentStartScreenPos = screenPos;
          isDraggingEquipment = false;
          final eq = network.equipments[eqId];
          if (eq != null) {
            final unproj = projector.unproject(screenPos, eq.z);
            _dragEquipmentStartPos = Node3D(id: 'drag', x: unproj.x, y: unproj.y, z: eq.z);
          }
          notifyListeners();
          break;
        } else {
          final hitDimId = _findDimensionAtScreenPos(screenPos);
          if (hitDimId != null) {
            if (isShift) {
              selectedDimensionIds.remove(hitDimId);
              if (selectedDimensionId == hitDimId) {
                selectedDimensionId = selectedDimensionIds.isEmpty ? null : selectedDimensionIds.first;
              }
              notifyListeners();
              break;
            }
            if (isCtrl) {
              if (selectedDimensionIds.contains(hitDimId)) {
                selectedDimensionIds.remove(hitDimId);
                if (selectedDimensionId == hitDimId) {
                  selectedDimensionId = selectedDimensionIds.isEmpty ? null : selectedDimensionIds.first;
                }
              } else {
                selectedDimensionIds.add(hitDimId);
                selectedDimensionId = hitDimId;
              }
              notifyListeners();
              break;
            }
            selectedDimensionId = hitDimId;
            selectedAxisId = null;
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedDimensionIds.add(hitDimId);
            selectedNodeId = null;
            selectedSegmentId = null;
            selectedEquipmentId = null;
            notifyListeners();
            break;
          } else {
            final hitAxisId = ((currentSnapResult?.type == SnapType.midpoint ||
                        currentSnapResult?.type == SnapType.perpendicular ||
                        currentSnapResult?.type == SnapType.gridAxis ||
                        currentSnapResult?.type == SnapType.endpoint) &&
                    network.axes.containsKey(currentSnapResult?.snappedSegmentId))
                ? currentSnapResult!.snappedSegmentId
                : _findAxisAtScreenPos(screenPos);
            if (hitAxisId != null) {
              if (isShift) {
                selectedAxisIds.remove(hitAxisId);
                if (selectedAxisId == hitAxisId) {
                  selectedAxisId = selectedAxisIds.isEmpty ? null : selectedAxisIds.first;
                }
                notifyListeners();
                break;
              }
              if (isCtrl) {
                if (selectedAxisIds.contains(hitAxisId)) {
                  selectedAxisIds.remove(hitAxisId);
                  if (selectedAxisId == hitAxisId) {
                    selectedAxisId = selectedAxisIds.isEmpty ? null : selectedAxisIds.first;
                  }
                } else {
                  selectedAxisIds.add(hitAxisId);
                  selectedAxisId = hitAxisId;
                }
                notifyListeners();
                break;
              }
              selectedAxisId = hitAxisId;
              selectedDimensionId = null;
              selectedNodeIds.clear();
              selectedSegmentIds.clear();
              selectedEquipmentIds.clear();
              selectedAxisIds.clear();
              selectedDimensionIds.clear();
              selectedAxisIds.add(hitAxisId);
              selectedNodeId = null;
              selectedSegmentId = null;
              selectedEquipmentId = null;
              notifyListeners();
              break;
            } else {
              // Клик по пустому холсту
              if (!isShift && !isCtrl) {
                selectedAxisId = null;
                selectedNodeId = null;
                selectedSegmentId = null;
                selectedEquipmentId = null;
                selectedDimensionId = null;
                selectedValveId = null;
                selectedSupportId = null;
                selectedWeldId = null;
                selectedNodeIds.clear();
                selectedSegmentIds.clear();
                selectedEquipmentIds.clear();
                selectedAxisIds.clear();
                selectedDimensionIds.clear();
              }
              boxSelectStart = screenPos;
              selectionBoxRect = Rect.fromPoints(screenPos, screenPos);
              _boxSelectIsShift = isShift;
              _boxSelectIsCtrl = isCtrl;
              notifyListeners();
              break;
            }
          }
        }

      case CanvasTool.move:
        final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
            ? currentSnapResult!.worldPoint
            : projector.unproject(screenPos, currentElevationZ);
        final snapped = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
            ? snapWorld
            : _snapToGrid(snapWorld);

        if (modifyBasePointWorld == null) {
          modifyBasePointWorld = snapped;
          modifyBasePointScreen = projector.project(snapped);
          modifyCurrentPointScreen = screenPos;
        } else {
          final dx = snapped.x - modifyBasePointWorld!.x;
          final dy = snapped.y - modifyBasePointWorld!.y;
          final dz = snapped.z - modifyBasePointWorld!.z;
          moveSelectedBy(dx: dx, dy: dy, dz: dz);
          modifyBasePointWorld = null;
          modifyBasePointScreen = null;
          modifyCurrentPointScreen = null;
          setTool(CanvasTool.select);
        }
        break;

      case CanvasTool.copy:
        final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
            ? currentSnapResult!.worldPoint
            : projector.unproject(screenPos, currentElevationZ);
        final snapped = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
            ? snapWorld
            : _snapToGrid(snapWorld);

        if (modifyBasePointWorld == null) {
          modifyBasePointWorld = snapped;
          modifyBasePointScreen = projector.project(snapped);
          modifyCurrentPointScreen = screenPos;
        } else {
          final dx = snapped.x - modifyBasePointWorld!.x;
          final dy = snapped.y - modifyBasePointWorld!.y;
          final dz = snapped.z - modifyBasePointWorld!.z;
          duplicateSelection(dx: dx, dy: dy, dz: dz, updateSelection: false);
        }
        break;

      case CanvasTool.rotate:
        final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
            ? currentSnapResult!.worldPoint
            : projector.unproject(screenPos, currentElevationZ);
        final snapped = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
            ? snapWorld
            : _snapToGrid(snapWorld);

        if (modifyBasePointWorld == null) {
          modifyBasePointWorld = snapped;
          modifyBasePointScreen = projector.project(snapped);
          modifyCurrentPointScreen = screenPos;
        } else {
          final dx = snapped.x - modifyBasePointWorld!.x;
          final dy = snapped.y - modifyBasePointWorld!.y;
          double angleDeg = math.atan2(dy, dx) * 180.0 / math.pi;
          if (angleDeg < 0) angleDeg += 360.0;
          if (angleSnapMode == AngleSnapMode.ortho90) {
            angleDeg = (angleDeg / 90.0).round() * 90.0;
          } else if (angleSnapMode == AngleSnapMode.isometric45) {
            angleDeg = (angleDeg / 45.0).round() * 45.0;
          }
          rotateSelectionAroundZ(angleDeg, customCenter: modifyBasePointWorld);
          modifyBasePointWorld = null;
          modifyBasePointScreen = null;
          modifyCurrentPointScreen = null;
          setTool(CanvasTool.select);
        }
        break;

      case CanvasTool.insertEquipment:
        final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
            ? currentSnapResult!.worldPoint
            : projector.unproject(screenPos, currentElevationZ);
        final snapped = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
            ? snapWorld
            : _snapToGrid(snapWorld);

        final eqId = 'eq_${_uuid.v4()}';
        final eqCount = network.equipments.length + 1;
        final eq = Equipment(
          id: eqId,
          name: 'Емкость Е-$eqCount',
          type: EquipmentType.box,
          x: snapped.x,
          y: snapped.y,
          z: currentElevationZ,
          width: 1000,
          length: 1000,
          height: 2000,
          rotationAngleDeg: 0.0,
          nozzles: const [],
        );

        network.addEquipment(eq);
        history.recordState(network);
        selectedEquipmentId = eq.id;
        selectedNodeId = null;
        break;

      case CanvasTool.insertValve:
        if (hitNodeId != null) {
          final conn = network.getConnectedSegments(hitNodeId);
          if (conn.length == 1) {
            network.attachEndValveToNode(
              hitNodeId,
              valveType: selectedValveType,
            );
            history.recordState(network);
            notifyListeners();
            break;
          }
        }
        if (hitSegId != null) {
          final seg = network.segments[hitSegId];
          if (seg != null) {
            final ratio = _calcSegmentRatio(hitSegId, screenPos);
            network.addValve(
              segmentId: hitSegId,
              ratio: ratio,
              valveType: selectedValveType,
              dn: seg.dn,
            );
            history.recordState(network);
          }
        }
        break;

      case CanvasTool.insertWeld:
        if (hitSegId != null) {
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.addWeldJoint(
            segmentId: hitSegId,
            ratio: ratio,
            stamp: currentWelderStamp,
            weldType: currentWeldType,
          );
          history.recordState(network);
        }
        break;

      case CanvasTool.insertReducer:
        if (hitSegId != null) {
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.insertReducer(
            segmentId: hitSegId,
            ratio: ratio,
            newDn: targetReducerDn,
            isEccentric: isEccentricReducer,
          );
          history.recordState(network);
        }
        break;

      case CanvasTool.insertFlange:
        if (hitNodeId != null) {
          final conn = network.getConnectedSegments(hitNodeId);
          if (conn.length == 1) {
            network.attachEndFlangeToNode(
              hitNodeId,
              flangeConnectionType: isFlangePair ? FlangeConnectionType.pipeToPipe : FlangeConnectionType.toEquipment,
              pressurePn: flangePressurePn,
              material: activeMaterial,
            );
            history.recordState(network);
            break;
          }
        }
        if (hitSegId != null) {
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.insertFlange(
            segmentId: hitSegId,
            ratio: ratio,
            isPair: isFlangePair,
            pressurePn: flangePressurePn,
            material: activeMaterial,
          );
          history.recordState(network);
        }
        break;

      case CanvasTool.insertCap:
        if (hitNodeId != null) {
          final conn = network.getConnectedSegments(hitNodeId);
          if (conn.length == 1) {
            network.attachCapToNode(hitNodeId);
            history.recordState(network);
            break;
          }
        } else if (hitSegId != null) {
          final seg = network.segments[hitSegId];
          if (seg != null) {
            final ratio = _calcSegmentRatio(hitSegId, screenPos);
            final targetNodeId = ratio < 0.5 ? seg.startNodeId : seg.endNodeId;
            final conn = network.getConnectedSegments(targetNodeId);
            if (conn.length == 1) {
              network.attachCapToNode(targetNodeId);
              history.recordState(network);
              break;
            }
          }
        }
        break;

      case CanvasTool.insertSupport:
        if (hitSegId != null) {
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.addSupport(
            segmentId: hitSegId,
            distanceRatio: ratio,
            type: selectedSupportType,
          );
          history.recordState(network);
        }
        break;

      case CanvasTool.orbit:
        break;
    }

    notifyListeners();
  }

  /// Обработка ведения стилуса / перемещения
  void handlePointerMove(Offset screenPos, {Offset delta = Offset.zero}) {
    currentCursorScreenPos = screenPos;

    if (currentTool == CanvasTool.pan) {
      pan(delta);
      return;
    }

    if (currentTool == CanvasTool.orbit) {
      orbit(delta);
      return;
    }

    // Обновляем привязку
    _updateSnap(screenPos);

    if (modifyBasePointWorld != null) {
      if (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none) {
        modifyCurrentPointScreen = currentSnapResult!.screenPoint;
      } else {
        modifyCurrentPointScreen = screenPos;
      }
      notifyListeners();
    }

    if (isDraggingCallout && selectedCalloutId != null && _dragCalloutStartScreenPos != null) {
      final callout = network.callouts[selectedCalloutId!];
      if (callout != null) {
        final d = screenPos - _dragCalloutStartScreenPos!;
        final newX = _dragCalloutInitialOffsetX + d.dx;
        final newY = _dragCalloutInitialOffsetY + d.dy;
        network.callouts[selectedCalloutId!] = callout.copyWith(
          screenOffsetX: newX,
          screenOffsetY: newY,
        );
        notifyListeners();
      }
      return;
    }

    if (currentTool == CanvasTool.dimension && dimensionStartNode != null && dimensionEndNode != null) {
      _updateDimensionOffset(screenPos);
      notifyListeners();
      return;
    }

    // Активное растяжение строительной оси за ручку-маркер
    if (activeGripAxisId != null && isGripAxisStart != null) {
      final snapWorld = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
          ? currentSnapResult!.worldPoint
          : _snapToGrid(projector.unproject(screenPos, currentElevationZ));
      final axis = network.axes[activeGripAxisId!];
      if (axis != null) {
        if (isGripAxisStart == true) {
          network.axes[activeGripAxisId!] = axis.copyWith(startPoint: snapWorld);
        } else {
          network.axes[activeGripAxisId!] = axis.copyWith(endPoint: snapWorld);
        }
        notifyListeners();
      }
      return;
    }

    // Активное перемещение узла в Grip Mode
    if (activeGripNodeId != null) {
      final snapWorld = (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none)
          ? currentSnapResult!.worldPoint
          : _snapToGrid(projector.unproject(screenPos, currentElevationZ));
      network.moveNode(activeGripNodeId!, snapWorld.x, snapWorld.y, snapWorld.z);
      notifyListeners();
      return;
    }

    // Проверка порога перетаскивания для узлов (порог 12 px и удержание 200мс)
    if (_potentialDragNodeId != null && !isDraggingNode && _dragNodeStartScreenPos != null) {
      if ((screenPos - _dragNodeStartScreenPos!).distance > 12.0) {
        if (!_canDragElement) {
          _longPressTimer?.cancel();
          _potentialDragNodeId = null;
          _dragNodeStartScreenPos = null;
        } else {
          isDraggingNode = true;
        }
      }
    }

    // Проверка порога перетаскивания для сегментов (порог 12 px и удержание 200мс)
    if (_potentialDragSegmentId != null && !isDraggingSegment && _dragSegmentStartScreenPos != null) {
      if ((screenPos - _dragSegmentStartScreenPos!).distance > 12.0) {
        if (!_canDragElement) {
          _longPressTimer?.cancel();
          _potentialDragSegmentId = null;
          _dragSegmentStartScreenPos = null;
          _dragSegmentStartWorldPos = null;
        } else {
          isDraggingSegment = true;
        }
      }
    }

    // Проверка порога перетаскивания для оборудования (порог 12 px и удержание 200мс)
    if (_potentialDragEquipmentId != null && !isDraggingEquipment && _dragEquipmentStartScreenPos != null) {
      if ((screenPos - _dragEquipmentStartScreenPos!).distance > 12.0) {
        if (!_canDragElement) {
          _longPressTimer?.cancel();
          _potentialDragEquipmentId = null;
          _dragEquipmentStartScreenPos = null;
          _dragEquipmentStartPos = null;
        } else {
          isDraggingEquipment = true;
        }
      }
    }

    // Проверка порога перетаскивания для арматуры (порог 12 px и удержание 200мс)
    if (_potentialDragValveId != null && !isDraggingValve && _dragValveStartScreenPos != null) {
      if ((screenPos - _dragValveStartScreenPos!).distance > 12.0) {
        if (!_canDragElement) {
          _longPressTimer?.cancel();
          _potentialDragValveId = null;
          _dragValveStartScreenPos = null;
        } else {
          isDraggingValve = true;
        }
      }
    }

    // Проверка порога перетаскивания для опор (порог 12 px и удержание 200мс)
    if (_potentialDragSupportId != null && !isDraggingSupport && _dragSupportStartScreenPos != null) {
      if ((screenPos - _dragSupportStartScreenPos!).distance > 12.0) {
        if (!_canDragElement) {
          _longPressTimer?.cancel();
          _potentialDragSupportId = null;
          _dragSupportStartScreenPos = null;
        } else {
          isDraggingSupport = true;
        }
      }
    }

    // Проверка порога перетаскивания для сварных стыков (порог 12 px и удержание 200мс)
    if (_potentialDragWeldId != null && !isDraggingWeld && _dragWeldStartScreenPos != null) {
      if ((screenPos - _dragWeldStartScreenPos!).distance > 12.0) {
        if (!_canDragElement) {
          _longPressTimer?.cancel();
          _potentialDragWeldId = null;
          _dragWeldStartScreenPos = null;
        } else {
          isDraggingWeld = true;
        }
      }
    }

    if (boxSelectStart != null) {
      selectionBoxRect = Rect.fromPoints(boxSelectStart!, screenPos);
      isCrossingSelection = screenPos.dx < boxSelectStart!.dx;
      notifyListeners();
      return;
    }

    if (isDraggingSegment && selectedSegmentId != null && _initialSegmentStartNode != null && _initialSegmentEndNode != null) {
      final seg = network.segments[selectedSegmentId!];
      if (seg != null) {
        final currentWorld = projector.unproject(screenPos, currentElevationZ);
        final startWorld = _dragSegmentStartWorldPos ?? currentWorld;
        final rawDx = currentWorld.x - startWorld.x;
        final rawDy = currentWorld.y - startWorld.y;
        final rawDz = currentWorld.z - startWorld.z;
        final s0 = _initialSegmentStartNode!;
        final e0 = _initialSegmentEndNode!;
        double shiftX = rawDx;
        double shiftY = rawDy;
        double shiftZ = rawDz;
        if (isAngleLocked) {
          final vx = e0.x - s0.x;
          final vy = e0.y - s0.y;
          final vz = e0.z - s0.z;
          final segLen = math.sqrt(vx * vx + vy * vy + vz * vz);
          if (segLen > 0.01) {
            final ux = vx / segLen;
            final uy = vy / segLen;
            final uz = vz / segLen;
            final dotParallel = rawDx * ux + rawDy * uy + rawDz * uz;
            shiftX = rawDx - dotParallel * ux;
            shiftY = rawDy - dotParallel * uy;
            shiftZ = rawDz - dotParallel * uz;
          }
        }
        if (isSnapEnabled) {
          shiftX = (shiftX / 10.0).round() * 10.0;
          shiftY = (shiftY / 10.0).round() * 10.0;
          shiftZ = (shiftZ / 10.0).round() * 10.0;
        }
        network.moveNode(seg.startNodeId, s0.x + shiftX, s0.y + shiftY, s0.z + shiftZ);
        network.moveNode(seg.endNodeId, e0.x + shiftX, e0.y + shiftY, e0.z + shiftZ);
        notifyListeners();
        return;
      }
    }

    if (isDraggingNode && selectedNodeId != null) {
      final unproj = projector.unproject(screenPos, currentElevationZ);
      final snapped = _snapToGrid(unproj);
      final targetNode = network.nodes[selectedNodeId!];
      if (targetNode != null) {
        final dx = snapped.x - targetNode.x;
        final dy = snapped.y - targetNode.y;
        final dz = snapped.z - targetNode.z;
        if (selectedNodeIds.length > 1 && selectedNodeIds.contains(selectedNodeId)) {
          for (final nId in selectedNodeIds) {
            final n = network.nodes[nId];
            if (n != null) {
              network.moveNode(nId, n.x + dx, n.y + dy, n.z + dz);
            }
          }
        } else {
          network.moveNode(selectedNodeId!, snapped.x, snapped.y, snapped.z);
        }
      }
      notifyListeners();
      return;
    }

    if (isDraggingEquipment && selectedEquipmentId != null && _dragEquipmentStartPos != null) {
      final eq = network.equipments[selectedEquipmentId!];
      if (eq != null) {
        final unproj = projector.unproject(screenPos, eq.z);
        final snapped = _snapToGrid(unproj);
        final dx = snapped.x - _dragEquipmentStartPos!.x;
        final dy = snapped.y - _dragEquipmentStartPos!.y;
        if (dx.abs() > 0.1 || dy.abs() > 0.1) {
          network.moveEquipment(selectedEquipmentId!, dx, dy, 0);
          _dragEquipmentStartPos = Node3D(id: 'drag', x: snapped.x, y: snapped.y, z: eq.z);
          notifyListeners();
        }
      }
      return;
    }

    if (isDraggingValve && selectedValveId != null) {
      final valve = network.valves[selectedValveId!];
      if (valve != null) {
        final seg = network.segments[valve.segmentId];
        if (seg != null) {
          final s = network.nodes[seg.startNodeId];
          final e = network.nodes[seg.endNodeId];
          if (s != null && e != null) {
            final p1 = projector.project(s);
            final p2 = projector.project(e);
            final v = p2 - p1;
            final len2 = v.dx * v.dx + v.dy * v.dy;
            if (len2 > 0.001) {
              final t = (((screenPos.dx - p1.dx) * v.dx + (screenPos.dy - p1.dy) * v.dy) / len2).clamp(0.05, 0.95);
              network.valves[selectedValveId!] = valve.copyWith(ratio: t);
              notifyListeners();
            }
          }
        }
      }
      return;
    }

    if (isDraggingSupport && selectedSupportId != null) {
      final support = network.supports[selectedSupportId!];
      if (support != null) {
        final seg = network.segments[support.segmentId];
        if (seg != null) {
          final s = network.nodes[seg.startNodeId];
          final e = network.nodes[seg.endNodeId];
          if (s != null && e != null) {
            final p1 = projector.project(s);
            final p2 = projector.project(e);
            final v = p2 - p1;
            final len2 = v.dx * v.dx + v.dy * v.dy;
            if (len2 > 0.001) {
              final t = (((screenPos.dx - p1.dx) * v.dx + (screenPos.dy - p1.dy) * v.dy) / len2).clamp(0.0, 1.0);
              network.supports[selectedSupportId!] = support.copyWith(distanceRatio: t);
              notifyListeners();
            }
          }
        }
      }
      return;
    }

    if (isDraggingWeld && selectedWeldId != null) {
      final weld = network.weldJoints[selectedWeldId!];
      if (weld != null) {
        final seg = network.segments[weld.segmentId];
        if (seg != null) {
          final s = network.nodes[seg.startNodeId];
          final e = network.nodes[seg.endNodeId];
          if (s != null && e != null) {
            final p1 = projector.project(s);
            final p2 = projector.project(e);
            final v = p2 - p1;
            final len2 = v.dx * v.dx + v.dy * v.dy;
            if (len2 > 0.001) {
              final t = (((screenPos.dx - p1.dx) * v.dx + (screenPos.dy - p1.dy) * v.dy) / len2).clamp(0.0, 1.0);
              network.weldJoints[selectedWeldId!] = weld.copyWith(ratio: t);
              notifyListeners();
            }
          }
        }
      }
      return;
    }

    notifyListeners();
  }

  void _updateSnap(Offset screenPos) {
    if (isSnapEnabled) {
      final effectiveAngleMode = isAngleLocked ? AngleSnapMode.ortho90 : angleSnapMode;
      currentSnapResult = snapEngine.findSnap(
        screenPos: screenPos,
        network: network,
        projector: projector,
        currentElevationZ: currentElevationZ,
        traceStartNode: traceStartNode ??
            axisStartNode ??
            dimensionStartNode ??
            (modifyBasePointWorld != null
                ? Node3D(id: 'base_point', x: modifyBasePointWorld!.x, y: modifyBasePointWorld!.y, z: modifyBasePointWorld!.z)
                : null),
        angleMode: effectiveAngleMode,
        customAngleStepDegrees: customAngleDegrees,
      );
    } else {
      currentSnapResult = SnapResult.none(screenPos, projector.unproject(screenPos, currentElevationZ));
    }
  }

  /// Обработка отпускания стилуса / пальца / кнопки мыши
  void handlePointerUp() {
    _longPressTimer?.cancel();
    _canDragElement = false;
    if (activeGripAxisId != null || activeGripNodeId != null) {
      // В режиме Grip Edit отпускание кнопки мыши не фиксирует элемент (фиксация по следующему клику ЛКМ)
      return;
    }

    if (selectionBoxRect != null && boxSelectStart != null) {
      final rect = selectionBoxRect!;
      if (rect.width > 6.0 || rect.height > 6.0) {
        final isCrossing = isCrossingSelection;
        final boxedNodeIds = <String>{};
        final boxedSegmentIds = <String>{};
        final boxedEquipmentIds = <String>{};
        final boxedAxisIds = <String>{};
        final boxedDimensionIds = <String>{};

        for (final node in network.nodes.values) {
          final p = projector.project(node);
          if (rect.contains(p)) {
            boxedNodeIds.add(node.id);
          }
        }
        for (final seg in network.segments.values) {
          final n1 = network.nodes[seg.startNodeId];
          final n2 = network.nodes[seg.endNodeId];
          if (n1 == null || n2 == null) continue;
          final p1 = projector.project(n1);
          final p2 = projector.project(n2);
          if (isCrossing) {
            if (rect.contains(p1) || rect.contains(p2) || _segmentIntersectsRect(p1, p2, rect)) {
              boxedSegmentIds.add(seg.id);
              boxedNodeIds.add(n1.id);
              boxedNodeIds.add(n2.id);
            }
          } else {
            if (rect.contains(p1) && rect.contains(p2)) {
              boxedSegmentIds.add(seg.id);
              boxedNodeIds.add(n1.id);
              boxedNodeIds.add(n2.id);
            }
          }
        }

        // Выбор оборудования
        for (final eq in network.equipments.values) {
          final p = projector.projectCoordinates(eq.x, eq.y, eq.z);
          final w = math.max(20.0, (eq.width / 2) * projector.scale);
          final l = math.max(20.0, (eq.length / 2) * projector.scale);
          final eqBounds = Rect.fromCenter(center: p, width: w * 2, height: l * 2);
          if (isCrossing) {
            if (rect.overlaps(eqBounds) || rect.contains(p)) {
              boxedEquipmentIds.add(eq.id);
            }
          } else {
            if (rect.contains(eqBounds.topLeft) && rect.contains(eqBounds.bottomRight)) {
              boxedEquipmentIds.add(eq.id);
            }
          }
        }

        // Выбор строительных и опорных осей
        for (final axis in network.axes.values) {
          final p1Native = projector.project(axis.startPoint);
          final p2Native = projector.project(axis.endPoint);

          final aWorld = Node3D(id: '', x: axis.startPoint.x, y: axis.startPoint.y, z: currentElevationZ);
          final bWorld = Node3D(id: '', x: axis.endPoint.x, y: axis.endPoint.y, z: currentElevationZ);
          final p1z = projector.project(aWorld);
          final p2z = projector.project(bWorld);

          bool matches(Offset p1, Offset p2) {
            if (isCrossing) {
              return rect.contains(p1) || rect.contains(p2) || _segmentIntersectsRect(p1, p2, rect);
            } else {
              return rect.contains(p1) && rect.contains(p2);
            }
          }

          if (matches(p1Native, p2Native) || matches(p1z, p2z)) {
            boxedAxisIds.add(axis.id);
          }
        }

        // Выбор линейных размеров
        for (final dim in network.dimensions.values) {
          final p1 = projector.project(dim.startPoint);
          final p2 = projector.project(dim.endPoint);
          if (isCrossing) {
            if (rect.contains(p1) || rect.contains(p2) || _segmentIntersectsRect(p1, p2, rect)) {
              boxedDimensionIds.add(dim.id);
            }
          } else {
            if (rect.contains(p1) && rect.contains(p2)) {
              boxedDimensionIds.add(dim.id);
            }
          }
        }

        if (_boxSelectIsShift) {
          selectedNodeIds.removeAll(boxedNodeIds);
          selectedSegmentIds.removeAll(boxedSegmentIds);
          selectedEquipmentIds.removeAll(boxedEquipmentIds);
          selectedAxisIds.removeAll(boxedAxisIds);
          selectedDimensionIds.removeAll(boxedDimensionIds);
          if (selectedNodeId != null && !selectedNodeIds.contains(selectedNodeId)) {
            selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
          }
          if (selectedSegmentId != null && !selectedSegmentIds.contains(selectedSegmentId)) {
            selectedSegmentId = selectedSegmentIds.isEmpty ? null : selectedSegmentIds.first;
          }
        } else if (_boxSelectIsCtrl) {
          selectedNodeIds.addAll(boxedNodeIds);
          selectedSegmentIds.addAll(boxedSegmentIds);
          selectedEquipmentIds.addAll(boxedEquipmentIds);
          selectedAxisIds.addAll(boxedAxisIds);
          selectedDimensionIds.addAll(boxedDimensionIds);
          if (selectedNodeId == null && selectedNodeIds.isNotEmpty) {
            selectedNodeId = selectedNodeIds.first;
          }
        } else {
          selectedNodeIds
            ..clear()
            ..addAll(boxedNodeIds);
          selectedSegmentIds
            ..clear()
            ..addAll(boxedSegmentIds);
          selectedEquipmentIds
            ..clear()
            ..addAll(boxedEquipmentIds);
          selectedAxisIds
            ..clear()
            ..addAll(boxedAxisIds);
          selectedDimensionIds
            ..clear()
            ..addAll(boxedDimensionIds);
          selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
          selectedSegmentId = selectedSegmentIds.isEmpty ? null : selectedSegmentIds.first;
          selectedEquipmentId = selectedEquipmentIds.isEmpty ? null : selectedEquipmentIds.first;
          selectedAxisId = selectedAxisIds.isEmpty ? null : selectedAxisIds.first;
          selectedDimensionId = selectedDimensionIds.isEmpty ? null : selectedDimensionIds.first;
        }
      }
      boxSelectStart = null;
      selectionBoxRect = null;
      _boxSelectIsShift = false;
      _boxSelectIsCtrl = false;
      _potentialDragNodeId = null;
      _dragNodeStartScreenPos = null;
      _potentialDragEquipmentId = null;
      _dragEquipmentStartScreenPos = null;
      notifyListeners();
      return;
    }

    _potentialDragNodeId = null;
    _dragNodeStartScreenPos = null;
    _potentialDragSegmentId = null;
    _dragSegmentStartScreenPos = null;
    _dragSegmentStartWorldPos = null;
    _initialSegmentStartNode = null;
    _initialSegmentEndNode = null;
    _potentialDragEquipmentId = null;
    _dragEquipmentStartScreenPos = null;
    _potentialDragValveId = null;
    _dragValveStartScreenPos = null;
    _potentialDragSupportId = null;
    _dragSupportStartScreenPos = null;
    _potentialDragWeldId = null;
    _dragWeldStartScreenPos = null;

    if (isDraggingSegment) {
      _checkAndMergeOpenNodes();
      history.recordState(network);
      isDraggingSegment = false;
      notifyListeners();
      return;
    }
    isDraggingSegment = false;

    if (isDraggingValve) {
      network.recalculateSpools();
      history.recordState(network);
      isDraggingValve = false;
      notifyListeners();
      return;
    }
    isDraggingValve = false;

    if (isDraggingSupport) {
      history.recordState(network);
      isDraggingSupport = false;
      notifyListeners();
      return;
    }
    isDraggingSupport = false;

    if (isDraggingWeld) {
      network.recalculateSpools();
      history.recordState(network);
      isDraggingWeld = false;
      notifyListeners();
      return;
    }
    isDraggingWeld = false;

    if (isDraggingCallout) {
      history.recordState(network);
      isDraggingCallout = false;
      _dragCalloutStartScreenPos = null;
      notifyListeners();
      return;
    }
    isDraggingCallout = false;

    if (isDraggingNode) {
      _checkAndMergeOpenNodes();
      history.recordState(network);
      isDraggingNode = false;
      notifyListeners();
      return;
    }
    isDraggingNode = false;

    if (isDraggingEquipment) {
      history.recordState(network);
      isDraggingEquipment = false;
      _dragEquipmentStartPos = null;
      notifyListeners();
      return;
    }
    isDraggingEquipment = false;

    // Поддержка жеста Drag-to-Draw (проведение стилусом/пальцем и отпускание)
    if (currentCursorScreenPos != null) {
      if (currentTool == CanvasTool.trace && traceStartNode != null) {
        final startScreen = projector.project(traceStartNode!);
        if ((currentCursorScreenPos! - startScreen).distance > 24.0) {
          _finishTraceSegment(currentCursorScreenPos!);
          notifyListeners();
          return;
        }
      } else if (currentTool == CanvasTool.drawAxis && axisStartNode != null) {
        final startScreen = projector.project(axisStartNode!);
        if ((currentCursorScreenPos! - startScreen).distance > 24.0) {
          history.recordState(network);
          final snapWorld = isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none
              ? currentSnapResult!.worldPoint
              : projector.unproject(currentCursorScreenPos!, currentElevationZ);
          final axisEndNode = Node3D(
            id: 'axis_end_${_uuid.v4()}',
            x: snapWorld.x,
            y: snapWorld.y,
            z: currentElevationZ,
          );
          final axisId = 'axis_${_uuid.v4()}';
          network.axes[axisId] = ConstructionAxis(
            id: axisId,
            label: isBuildingGridAxis ? currentAxisLabel : '',
            startPoint: axisStartNode!,
            endPoint: axisEndNode,
            isBuildingGrid: isBuildingGridAxis,
          );
          if (isBuildingGridAxis) {
            final num = int.tryParse(currentAxisLabel);
            if (num != null) {
              currentAxisLabel = '${num + 1}';
            }
          }
          axisStartNode = null;
          notifyListeners();
          return;
        }
      }
    }

    notifyListeners();
  }

  /// Завершение трассировки сегмента
  void _finishTraceSegment(Offset endScreenPos) {
    if (traceStartNode == null) return;

    String targetNodeId;

    if (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none) {
      if (currentSnapResult!.type == SnapType.node &&
          currentSnapResult!.snappedNodeId != null &&
          currentSnapResult!.snappedNodeId != traceStartNode!.id) {
        targetNodeId = currentSnapResult!.snappedNodeId!;
      } else if (currentSnapResult!.type == SnapType.equipmentFace &&
          currentSnapResult!.snappedEquipmentId != null &&
          network.equipments.containsKey(currentSnapResult!.snappedEquipmentId)) {
        final eqId = currentSnapResult!.snappedEquipmentId!;
        final w = currentSnapResult!.worldPoint;
        final nozzleNode = network.attachNozzleAtWorldPoint(
          eqId,
          w,
          dn: activeDn,
          face: currentSnapResult!.snappedEquipmentFace,
          dirX: traceStartNode!.x - w.x,
          dirY: traceStartNode!.y - w.y,
          dirZ: traceStartNode!.z - w.z,
        );
        targetNodeId = nozzleNode.id;
      } else if ((currentSnapResult!.type == SnapType.segmentAxis ||
                  currentSnapResult!.type == SnapType.midpoint ||
                  currentSnapResult!.type == SnapType.perpendicular) &&
                 currentSnapResult!.snappedSegmentId != null &&
                 network.segments.containsKey(currentSnapResult!.snappedSegmentId)) {
        final segId = currentSnapResult!.snappedSegmentId!;
        final seg = network.segments[segId]!;
        final s = network.nodes[seg.startNodeId];
        final e = network.nodes[seg.endNodeId];
        final w = currentSnapResult!.worldPoint;
        final double ratio;
        if (s != null && e != null) {
          final segLen = math.sqrt(math.pow(e.x - s.x, 2) + math.pow(e.y - s.y, 2) + math.pow(e.z - s.z, 2));
          ratio = segLen > 0.001
              ? (math.sqrt(math.pow(w.x - s.x, 2) + math.pow(w.y - s.y, 2) + math.pow(w.z - s.z, 2)) / segLen).clamp(0.01, 0.99)
              : 0.5;
        } else {
          ratio = 0.5;
        }
        final midNode = network.splitSegmentAtRatio(segId, ratio);
        targetNodeId = midNode?.id ??
            (() {
              final n = Node3D(id: 'node_${_uuid.v4()}', x: w.x, y: w.y, z: w.z);
              network.nodes[n.id] = n;
              return n.id;
            })();
      } else {
        final w = currentSnapResult!.worldPoint;
        final newNode = Node3D(
          id: 'node_${_uuid.v4()}',
          x: w.x,
          y: w.y,
          z: currentElevationZ,
        );
        network.nodes[newNode.id] = newNode;
        targetNodeId = newNode.id;
      }
    } else {
      final rawWorld = projector.unproject(endScreenPos, currentElevationZ);
      final dx = rawWorld.x - traceStartNode!.x;
      final dy = rawWorld.y - traceStartNode!.y;

      double endX = traceStartNode!.x;
      double endY = traceStartNode!.y;

      if (dx.abs() > dy.abs()) {
        endX = rawWorld.x;
        endY = traceStartNode!.y;
      } else {
        endX = traceStartNode!.x;
        endY = rawWorld.y;
      }

      final snapped = _snapToGrid(Node3D(id: '', x: endX, y: endY, z: currentElevationZ));
      final hitExistingNodeId = _findNodeAtScreenPos(endScreenPos);
      final hitExistingSegId = _findSegmentAtScreenPos(endScreenPos);
      final hitExistingEqId = _findEquipmentAtScreenPos(endScreenPos);

      if (hitExistingNodeId != null && hitExistingNodeId != traceStartNode!.id) {
        targetNodeId = hitExistingNodeId;
      } else if (hitExistingEqId != null && network.equipments.containsKey(hitExistingEqId)) {
        final eq = network.equipments[hitExistingEqId]!;
        final w = projector.unproject(endScreenPos, eq.z + eq.height);
        final nozzleNode = network.attachNozzleAtWorldPoint(
          hitExistingEqId,
          w,
          dn: activeDn,
          dirX: traceStartNode!.x - w.x,
          dirY: traceStartNode!.y - w.y,
          dirZ: traceStartNode!.z - w.z,
        );
        targetNodeId = nozzleNode.id;
      } else if (hitExistingSegId != null) {
        final ratio = _calcSegmentRatio(hitExistingSegId, endScreenPos);
        final midNode = network.splitSegmentAtRatio(hitExistingSegId, ratio);
        targetNodeId = midNode?.id ??
            (() {
              final fallback = Node3D(
                id: 'node_${_uuid.v4()}',
                x: snapped.x,
                y: snapped.y,
                z: currentElevationZ,
              );
              network.nodes[fallback.id] = fallback;
              return fallback.id;
            })();
      } else {
        final newNode = Node3D(
          id: 'node_${_uuid.v4()}',
          x: snapped.x,
          y: snapped.y,
          z: currentElevationZ,
        );
        network.nodes[newNode.id] = newNode;
        targetNodeId = newNode.id;
      }
    }

    final segId = 'seg_${_uuid.v4()}';
    final dim = network.pipeCatalog.getDimension(activeDn);
    final outerD = dim?.outerDiameterMm;
    final seg = PipeSegment(
      id: segId,
      startNodeId: traceStartNode!.id,
      endNodeId: targetNodeId,
      systemId: activeSystemId,
      dn: activeDn,
      outerDiameterMm: outerD,
      wallThicknessMm: activeWallThicknessMm,
      material: activeMaterial,
    );
    network.addSegment(seg);

    history.recordState(network);
    traceStartNode = network.nodes[targetNodeId];
    selectedNodeId = targetNodeId;
  }

  /// Вычисляет единичный направляющий 3D-вектор от startNode к текущей цели привязки или курсору
  ({double dirX, double dirY, double dirZ}) _computeTraceDirection(Node3D startNode) {
    return tracingController.computeTraceDirection(
      startNode: startNode,
      projector: projector,
      currentElevationZ: currentElevationZ,
      currentCursorScreenPos: currentCursorScreenPos,
      currentSnapResult: currentSnapResult,
      isSnapEnabled: isSnapEnabled,
    );
  }

  /// Фиксация конца трассировки трубы или строительной оси на заданном расстоянии (Direct Distance Entry / Touch UI)
  void commitTraceWithLength(double lengthMm, {double? dirX, double? dirY, double? dirZ}) {
    if (lengthMm <= 0 || lengthMm.isNaN || lengthMm.isInfinite) return;

    if (currentTool == CanvasTool.trace && traceStartNode != null) {
      final startNode = traceStartNode!;
      final end = tracingController.calculateEndPoint(
        startNode: startNode,
        lengthMm: lengthMm,
        projector: projector,
        currentElevationZ: currentElevationZ,
        currentCursorScreenPos: currentCursorScreenPos,
        currentSnapResult: currentSnapResult,
        isSnapEnabled: isSnapEnabled,
        dirX: dirX,
        dirY: dirY,
        dirZ: dirZ,
      );
      final endX = end.x;
      final endY = end.y;
      final endZ = end.z;

      String targetNodeId;
      final existingNode = network.nodes.values.cast<Node3D?>().firstWhere(
            (n) =>
                n != null &&
                n.id != startNode.id &&
                (n.x - endX).abs() < 1.0 &&
                (n.y - endY).abs() < 1.0 &&
                (n.z - endZ).abs() < 1.0,
            orElse: () => null,
          );

      if (existingNode != null) {
        targetNodeId = existingNode.id;
      } else {
        final newNode = Node3D(
          id: 'node_${_uuid.v4()}',
          x: endX,
          y: endY,
          z: endZ,
        );
        network.nodes[newNode.id] = newNode;
        targetNodeId = newNode.id;
      }

      final segId = 'seg_${_uuid.v4()}';
      final dim = network.pipeCatalog.getDimension(activeDn);
      final outerD = dim?.outerDiameterMm;
      final seg = PipeSegment(
        id: segId,
        startNodeId: startNode.id,
        endNodeId: targetNodeId,
        systemId: activeSystemId,
        dn: activeDn,
        outerDiameterMm: outerD,
        wallThicknessMm: activeWallThicknessMm,
        material: activeMaterial,
      );
      network.addSegment(seg);

      history.recordState(network);
      traceStartNode = network.nodes[targetNodeId];
      selectedNodeId = targetNodeId;

      currentSnapResult = null;
      if (currentCursorScreenPos != null) {
        _updateSnap(currentCursorScreenPos!);
      }
      notifyListeners();
    } else if (currentTool == CanvasTool.drawAxis && axisStartNode != null) {
      final startNode = axisStartNode!;
      final end = tracingController.calculateEndPoint(
        startNode: startNode,
        lengthMm: lengthMm,
        projector: projector,
        currentElevationZ: currentElevationZ,
        currentCursorScreenPos: currentCursorScreenPos,
        currentSnapResult: currentSnapResult,
        isSnapEnabled: isSnapEnabled,
        dirX: dirX,
        dirY: dirY,
        dirZ: dirZ,
      );
      final endX = end.x;
      final endY = end.y;

      final axisEndNode = Node3D(
        id: 'axis_end_${_uuid.v4()}',
        x: endX,
        y: endY,
        z: currentElevationZ,
      );
      final axisId = 'axis_${_uuid.v4()}';
      network.axes[axisId] = ConstructionAxis(
        id: axisId,
        label: isBuildingGridAxis ? currentAxisLabel : '',
        startPoint: axisStartNode!,
        endPoint: axisEndNode,
        isBuildingGrid: isBuildingGridAxis,
      );

      if (isBuildingGridAxis) {
        final num = int.tryParse(currentAxisLabel);
        if (num != null) {
          currentAxisLabel = '${num + 1}';
        }
      }
      axisStartNode = null;
      history.recordState(network);

      if (currentCursorScreenPos != null) {
        _updateSnap(currentCursorScreenPos!);
      }
      notifyListeners();
    } else if ((currentTool == CanvasTool.move || currentTool == CanvasTool.copy) && modifyBasePointWorld != null) {
      final startNode = modifyBasePointWorld!;
      final ({double dirX, double dirY, double dirZ}) dir;
      if (dirX != null || dirY != null || dirZ != null) {
        final dx = dirX ?? 0.0;
        final dy = dirY ?? 0.0;
        final dz = dirZ ?? 0.0;
        final mag = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (mag > 1e-6) {
          dir = (dirX: dx / mag, dirY: dy / mag, dirZ: dz / mag);
        } else {
          dir = _computeTraceDirection(startNode);
        }
      } else {
        dir = _computeTraceDirection(startNode);
      }

      final dx = double.parse((dir.dirX * lengthMm).toStringAsFixed(2));
      final dy = double.parse((dir.dirY * lengthMm).toStringAsFixed(2));
      final dz = double.parse((dir.dirZ * lengthMm).toStringAsFixed(2));

      if (currentTool == CanvasTool.move) {
        moveSelectedBy(dx: dx, dy: dy, dz: dz);
        modifyBasePointWorld = null;
        modifyBasePointScreen = null;
        modifyCurrentPointScreen = null;
        setTool(CanvasTool.select);
      } else if (currentTool == CanvasTool.copy) {
        duplicateSelection(dx: dx, dy: dy, dz: dz);
        modifyBasePointWorld = null;
        modifyBasePointScreen = null;
        modifyCurrentPointScreen = null;
        setTool(CanvasTool.select);
      }

      if (currentCursorScreenPos != null) {
        _updateSnap(currentCursorScreenPos!);
      }
      notifyListeners();
    }
  }


  /// Поиск арматуры по телу и каркасу в радиусе курсора
  String? _findValveAtScreenPos(Offset screenPos) {
    for (final valve in network.valves.values) {
      final seg = network.segments[valve.segmentId];
      if (seg == null) continue;
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;

      final worldPos = valve.calculatePosition(s, e);
      final p = projector.project(worldPos);
      if ((p - screenPos).distance <= 20.0) {
        return valve.id;
      }

      // Проверяем каркасные отрезки корпуса, штока, маховика и фланцев
      final wireSegments = Element3dGeometry.generateValveWireframe(
        valve,
        s,
        e,
        pipeOuterDiameter: seg.outerDiameterMm,
      );
      for (final wire in wireSegments) {
        final p1 = projector.project(wire.startNode);
        final p2 = projector.project(wire.endNode);
        if (_distanceToLineSegment(screenPos, p1, p2) <= 14.0) {
          return valve.id;
        }
      }
    }
    return null;
  }

  /// Поиск фасонного элемента (отвод, тройник, переход, фланец, заглушка) по его геометрическому телу на экране
  String? _findFittingAtScreenPos(Offset screenPos) {
    for (final fit in network.fittings.values) {
      final node = network.nodes[fit.nodeId];
      if (node == null) continue;
      final ptN = projector.project(node);

      // Быстрая проверка центра узла
      if ((ptN - screenPos).distance <= 18.0) {
        return fit.nodeId;
      }

      final connected = network.getConnectedSegments(fit.nodeId);

      switch (fit.fittingType) {
        case FittingType.elbow90:
        case FittingType.elbow45:
          if (connected.length == 2) {
            final s1 = connected[0];
            final s2 = connected[1];
            final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
            final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
            if (other1 == null || other2 == null) break;

            final ptO1 = projector.project(other1);
            final ptO2 = projector.project(other2);

            final pOut1 = PipePainter.calcPipeTrimmedPoint(
              network: network,
              nodeId: fit.nodeId,
              otherNodeId: other1.id,
              nodeScreen: ptN,
              otherScreen: ptO1,
              seg: s1,
            );
            final pOut2 = PipePainter.calcPipeTrimmedPoint(
              network: network,
              nodeId: fit.nodeId,
              otherNodeId: other2.id,
              nodeScreen: ptN,
              otherScreen: ptO2,
              seg: s2,
            );

            // Дискретизация квадратичной кривой Безье отвода (10 отрезков)
            Offset prev = pOut1;
            bool hit = false;
            for (int i = 1; i <= 10; i++) {
              final t = i / 10.0;
              final oneMinusT = 1.0 - t;
              final cur = pOut1 * (oneMinusT * oneMinusT) +
                  ptN * (2.0 * oneMinusT * t) +
                  pOut2 * (t * t);
              if (_distanceToLineSegment(screenPos, prev, cur) <= 15.0) {
                hit = true;
                break;
              }
              prev = cur;
            }
            if (hit) return fit.nodeId;
          }
          break;

        case FittingType.tee:
        case FittingType.cross:
          if (connected.length >= 3) {
            final branchSeg = fit.fittingType == FittingType.tee
                ? network.identifyBranchSegment(fit.nodeId, connected)
                : null;
            for (int i = 0; i < connected.length; i++) {
              final seg = connected[i];
              final otherId = seg.startNodeId == fit.nodeId ? seg.endNodeId : seg.startNodeId;
              final otherNode = network.nodes[otherId];
              if (otherNode == null) continue;

              final isBranch = branchSeg != null && seg.id == branchSeg.id;
              final armLenMm = isBranch
                  ? fit.effectiveBranchLengthMm
                  : (fit.buildingLengthMm != null && fit.buildingLengthMm! > 0
                      ? fit.buildingLengthMm! / 2.0
                      : fit.dn * 1.0);

              final vx = otherNode.x - node.x;
              final vy = otherNode.y - node.y;
              final vz = otherNode.z - node.z;
              final dist3d = math.sqrt(vx * vx + vy * vy + vz * vz);
              final uX = dist3d > 0 ? vx / dist3d : 0.0;
              final uY = dist3d > 0 ? vy / dist3d : 0.0;
              final uZ = dist3d > 0 ? vz / dist3d : 0.0;

              final effectiveArm = math.min(armLenMm, dist3d * 0.45);
              final pArmScreen = projector.projectCoordinates(
                node.x + uX * effectiveArm,
                node.y + uY * effectiveArm,
                node.z + uZ * effectiveArm,
              );

              if (_distanceToLineSegment(screenPos, ptN, pArmScreen) <= 15.0) {
                return fit.nodeId;
              }
            }
          }
          break;

        case FittingType.reducerConcentric:
        case FittingType.reducerEccentric:
          if (connected.length == 2) {
            final s1 = connected[0];
            final s2 = connected[1];
            final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
            final other2 = network.nodes[s2.startNodeId == fit.nodeId ? s2.endNodeId : s2.startNodeId];
            if (other1 != null && other2 != null) {
              final wireSegments = Element3dGeometry.generateReducerWireframe(
                fit,
                node,
                other1,
                other2,
                d1: s1.outerDiameterMm,
                d2: s2.outerDiameterMm,
              );
              for (final wire in wireSegments) {
                final p1 = projector.project(wire.startNode);
                final p2 = projector.project(wire.endNode);
                if (_distanceToLineSegment(screenPos, p1, p2) <= 15.0) {
                  return fit.nodeId;
                }
              }
            }
          }
          break;

        case FittingType.flange:
          if (connected.isNotEmpty) {
            final s1 = connected[0];
            final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
            if (other1 != null) {
              final wireSegments = Element3dGeometry.generateFlangeWireframe(
                fit,
                node,
                other1,
                pipeOuterDiameter: s1.outerDiameterMm,
              );
              for (final wire in wireSegments) {
                final p1 = projector.project(wire.startNode);
                final p2 = projector.project(wire.endNode);
                if (_distanceToLineSegment(screenPos, p1, p2) <= 15.0) {
                  return fit.nodeId;
                }
              }
            }
          }
          break;

        case FittingType.cap:
          if (connected.isNotEmpty) {
            final s1 = connected[0];
            final other1 = network.nodes[s1.startNodeId == fit.nodeId ? s1.endNodeId : s1.startNodeId];
            if (other1 != null) {
              final wireSegments = Element3dGeometry.generateCapWireframe(
                fit,
                node,
                other1,
                pipeOuterDiameter: s1.outerDiameterMm,
              );
              for (final wire in wireSegments) {
                final p1 = projector.project(wire.startNode);
                final p2 = projector.project(wire.endNode);
                if (_distanceToLineSegment(screenPos, p1, p2) <= 15.0) {
                  return fit.nodeId;
                }
              }
            }
          }
          break;

        case FittingType.directBranch:
          if ((ptN - screenPos).distance <= 20.0) {
            return fit.nodeId;
          }
          break;
      }
    }
    return null;
  }

  /// Поиск сварного стыка в радиусе 14 пикселей от курсора
  String? _findWeldAtScreenPos(Offset screenPos) {
    for (final weld in network.weldJoints.values) {
      final seg = network.segments[weld.segmentId];
      if (seg == null) continue;
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      final worldPos = weld.calculatePosition(s, e);
      final p = projector.project(worldPos);
      if ((p - screenPos).distance <= 14.0) {
        return weld.id;
      }
    }
    return null;
  }

  /// Поиск опоры в радиусе 16 пикселей от курсора
  String? _findSupportAtScreenPos(Offset screenPos) {
    for (final support in network.supports.values) {
      final seg = network.segments[support.segmentId];
      if (seg == null) continue;
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;
      final worldPos = support.calculatePosition(s, e);
      final p = projector.project(worldPos);
      if ((p - screenPos).distance <= 16.0) {
        return support.id;
      }
    }
    return null;
  }

  /// Публичные методы поиска элементов по экрану для тестов и контроллера
  String? findValveAtScreenPos(Offset screenPos) => _findValveAtScreenPos(screenPos);
  String? findFittingAtScreenPos(Offset screenPos) => _findFittingAtScreenPos(screenPos);
  String? findWeldAtScreenPos(Offset screenPos) => _findWeldAtScreenPos(screenPos);
  String? findSupportAtScreenPos(Offset screenPos) => _findSupportAtScreenPos(screenPos);

  /// Поиск узла в радиусе 18 пикселей от курсора
  String? _findNodeAtScreenPos(Offset screenPos) {
    for (final node in network.nodes.values) {
      final pos = projector.project(node);
      if ((pos - screenPos).distance < 18.0) {
        return node.id;
      }
    }
    return null;
  }

  /// Поиск сегмента в радиусе 14 пикселей от курсора
  String? _findSegmentAtScreenPos(Offset screenPos) {
    for (final seg in network.segments.values) {
      final s = network.nodes[seg.startNodeId];
      final e = network.nodes[seg.endNodeId];
      if (s == null || e == null) continue;

      final p1 = projector.project(s);
      final p2 = projector.project(e);

      final dist = _distanceToLineSegment(screenPos, p1, p2);
      if (dist < 14.0) {
        return seg.id;
      }
    }
    return null;
  }

  /// Поиск физической катушки под курсором в радиусе 14 пикселей
  PipeSpool? _findSpoolAtScreenPos(Offset screenPos) {
    if (network.spools.isEmpty) return null;

    for (final spool in network.spools.values) {
      final seg = network.segments[spool.segmentId];
      if (seg == null) continue;
      if (network.isElbowToElbowSegment(seg.id)) continue;

      final start = spool.startPoint ?? network.nodes[seg.startNodeId];
      final end = spool.endPoint ?? network.nodes[seg.endNodeId];
      if (start == null || end == null) continue;

      final p1 = projector.project(start);
      final p2 = projector.project(end);

      final dist = _distanceToLineSegment(screenPos, p1, p2);
      if (dist < 14.0) {
        return spool;
      }
    }
    return null;
  }

  /// Поиск оборудования под курсором
  String? _findEquipmentAtScreenPos(Offset screenPos) {
    for (final eq in network.equipments.values) {
      final rad = eq.rotationAngleDeg * math.pi / 180.0;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      Offset rot(double lx, double ly) {
        return Offset(
          eq.x + lx * cosA - ly * sinA,
          eq.y + lx * sinA + ly * cosA,
        );
      }

      final halfW = eq.width / 2.0;
      final halfL = eq.length / 2.0;
      final c1 = rot(-halfW, -halfL);
      final c2 = rot(halfW, -halfL);
      final c3 = rot(halfW, halfL);
      final c4 = rot(-halfW, halfL);

      final z1 = eq.z;
      final z2 = eq.z + eq.height;

      final pts = [
        projector.projectCoordinates(c1.dx, c1.dy, z1),
        projector.projectCoordinates(c2.dx, c2.dy, z1),
        projector.projectCoordinates(c3.dx, c3.dy, z1),
        projector.projectCoordinates(c4.dx, c4.dy, z1),
        projector.projectCoordinates(c1.dx, c1.dy, z2),
        projector.projectCoordinates(c2.dx, c2.dy, z2),
        projector.projectCoordinates(c3.dx, c3.dy, z2),
        projector.projectCoordinates(c4.dx, c4.dy, z2),
      ];

      double minX = pts[0].dx;
      double maxX = pts[0].dx;
      double minY = pts[0].dy;
      double maxY = pts[0].dy;

      for (final p in pts) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }

      final rect = Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10);
      if (rect.contains(screenPos)) {
        return eq.id;
      }
    }
    return null;
  }

  double _calcSegmentRatio(String segId, Offset screenPos) {
    final seg = network.segments[segId];
    if (seg == null) return 0.5;
    final s = network.nodes[seg.startNodeId];
    final e = network.nodes[seg.endNodeId];
    if (s == null || e == null) return 0.5;

    final p1 = projector.project(s);
    final p2 = projector.project(e);
    final len = (p2 - p1).distance;
    if (len < 1.0) return 0.5;

    final u = (p2 - p1) / len;
    final v = screenPos - p1;
    final proj = v.dx * u.dx + v.dy * u.dy;
    return (proj / len).clamp(0.05, 0.95);
  }

  double _distanceToLineSegment(Offset p, Offset a, Offset b) {
    final l2 = (b - a).distanceSquared;
    if (l2 == 0.0) return (p - a).distance;
    final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2).clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - projection).distance;
  }

  Node3D _snapToGrid(Node3D node, [double step = 100.0]) {
    final sx = (node.x / step).round() * step;
    final sy = (node.y / step).round() * step;
    return node.copyWith(x: sx, y: sy);
  }

  /// Панорамирование сцены
  void pan(Offset delta) {
    projector = projector.copyWith(panOffset: projector.panOffset + delta);
    notifyListeners();
  }

  /// Центрирует 3D орбиту вокруг выделенного объекта (или всей схемы)
  void prepareOrbit() {
    Node3D newCenter;
    if (selectedNodeId != null) {
      newCenter = network.nodes[selectedNodeId] ?? const Node3D(id: 'c', x: 0, y: 0, z: 0);
    } else if (selectedSegmentId != null) {
      final seg = network.segments[selectedSegmentId];
      if (seg != null) {
        final n1 = network.nodes[seg.startNodeId];
        final n2 = network.nodes[seg.endNodeId];
        if (n1 != null && n2 != null) {
          newCenter = Node3D(
            id: 'c',
            x: (n1.x + n2.x) / 2,
            y: (n1.y + n2.y) / 2,
            z: (n1.z + n2.z) / 2,
          );
        } else {
          newCenter = const Node3D(id: 'c', x: 0, y: 0, z: 0);
        }
      } else {
        newCenter = const Node3D(id: 'c', x: 0, y: 0, z: 0);
      }
    } else if (selectedEquipmentId != null) {
      final eq = network.equipments[selectedEquipmentId];
      if (eq != null) {
        newCenter = Node3D(id: 'c', x: eq.x, y: eq.y, z: eq.z + eq.height / 2);
      } else {
        newCenter = const Node3D(id: 'c', x: 0, y: 0, z: 0);
      }
    } else {
      // bounding box of all nodes
      if (network.nodes.isEmpty) {
        newCenter = const Node3D(id: 'c', x: 0, y: 0, z: 0);
      } else {
        double minX = double.infinity, maxX = -double.infinity;
        double minY = double.infinity, maxY = -double.infinity;
        double minZ = double.infinity, maxZ = -double.infinity;
        for (final n in network.nodes.values) {
          if (n.x < minX) minX = n.x;
          if (n.x > maxX) maxX = n.x;
          if (n.y < minY) minY = n.y;
          if (n.y > maxY) maxY = n.y;
          if (n.z < minZ) minZ = n.z;
          if (n.z > maxZ) maxZ = n.z;
        }
        newCenter = Node3D(
          id: 'c',
          x: (minX + maxX) / 2,
          y: (minY + maxY) / 2,
          z: (minZ + maxZ) / 2,
        );
      }
    }

    // Узнаем, где этот центр находится на экране СЕЙЧАС (до изменения targetCenter)
    final currentScreenPos = projector.project(newCenter);
    
    // Меняем targetCenter и корректируем panOffset, чтобы центр не дернулся
    projector = projector.copyWith(
      targetCenter: newCenter,
      panOffset: currentScreenPos,
    );
  }

  /// Свободное 3D-вращение сцены (Орбита)
  void orbit(Offset delta) {
    final newAzimuth = projector.orbitAzimuth + delta.dx * 0.01;
    final newElevation = (projector.orbitElevation + delta.dy * 0.01).clamp(0.05, math.pi / 2 - 0.05);
    projector = projector.copyWith(
      projectionType: ProjectionType.orbit3d,
      orbitAzimuth: newAzimuth,
      orbitElevation: newElevation,
    );
    notifyListeners();
  }

  /// Актуальный размер рабочей области холста
  Size lastViewportSize = const Size(1200, 800);

  /// Центр рабочей области холста
  Offset get viewportCenter => Offset(lastViewportSize.width / 2, lastViewportSize.height / 2);

  /// Текущий процент масштабирования (100% соответствует 0.25 px/мм)
  int get zoomPercentage => (projector.scale / 0.25 * 100).round();

  /// Масштабирование сцены с удержанием точки focalPoint под курсором/пальцами
  void zoom(double factor, Offset focalPoint) {
    if (factor.isNaN || factor <= 0.0) return;
    final oldScale = projector.scale;
    // Диапазон: от 0.002 (1м = 2px, крупный генплан) до 10.0 (1мм = 10px, детальные стыки)
    final newScale = (oldScale * factor).clamp(0.002, 10.0);
    if ((newScale - oldScale).abs() < 1e-6) return;

    // Векторная компенсация panOffset, чтобы точка focalPoint осталась на том же месте экрана
    final ratio = newScale / oldScale;
    final newPan = focalPoint - (focalPoint - projector.panOffset) * ratio;

    projector = projector.copyWith(scale: newScale, panOffset: newPan);
    notifyListeners();
  }

  /// Быстрое приближение (+25%)
  void zoomIn([Offset? focalPoint]) {
    zoom(1.25, focalPoint ?? viewportCenter);
  }

  /// Быстрое отдаление (-20%)
  void zoomOut([Offset? focalPoint]) {
    zoom(0.8, focalPoint ?? viewportCenter);
  }

  /// Сброс масштаба к 100% (1:1 standard scale = 0.25 px/мм)
  void zoom100([Offset? focalPoint]) {
    final targetScale = 0.25;
    final factor = targetScale / projector.scale;
    zoom(factor, focalPoint ?? viewportCenter);
  }

  /// Вписать всю геометрию сети и строительных осей в экран (Zoom to Fit / Zoom Extents)
  void zoomToFit({Size? viewportSize, EdgeInsets padding = const EdgeInsets.all(72.0)}) {
    final vp = viewportSize ?? lastViewportSize;
    if (vp.width <= 0 || vp.height <= 0) return;

    // Собираем все точки сети (узлы труб, арматуры, фитингов и концы осей)
    final allNodes = <Node3D>[
      ...network.nodes.values,
      ...network.axes.values.expand((a) => [a.startPoint, a.endPoint]),
    ];

    if (allNodes.isEmpty) {
      // Сеть пуста: центрируем (0,0) по центру экрана
      projector = projector.copyWith(
        scale: 0.25,
        panOffset: Offset(vp.width / 2, vp.height / 2),
      );
      notifyListeners();
      return;
    }

    final rawBounds = projector.computeRawBoundingBox(allNodes);
    if (rawBounds == null) return;

    final contentWidth = math.max(rawBounds.width, 200.0);
    final contentHeight = math.max(rawBounds.height, 200.0);

    final availWidth = math.max(vp.width - padding.horizontal, 100.0);
    final availHeight = math.max(vp.height - padding.vertical, 100.0);

    final fitScaleX = availWidth / contentWidth;
    final fitScaleY = availHeight / contentHeight;
    final newScale = math.min(fitScaleX, fitScaleY).clamp(0.005, 2.5);

    // Центрируем bounding box по центру viewport
    final centerRaw = rawBounds.center;
    final centerScreen = Offset(vp.width / 2, vp.height / 2);

    final newPanX = centerScreen.dx - centerRaw.dx * newScale;
    final newPanY = centerScreen.dy + centerRaw.dy * newScale;

    projector = projector.copyWith(
      scale: newScale,
      panOffset: Offset(newPanX, newPanY),
    );
    notifyListeners();
  }

  /// Сброс панорамирования и масштаба (интеллектуальный zoomToFit)
  void resetView() {
    zoomToFit();
  }

  /// Геометрическая длина выбранного сегмента (мм)
  double? get selectedSegmentLength {
    if (selectedSegmentId == null) return null;
    final seg = network.segments[selectedSegmentId];
    if (seg == null) return null;
    final s = network.nodes[seg.startNodeId];
    final e = network.nodes[seg.endNodeId];
    if (s == null || e == null) return null;
    return s.distanceTo(e);
  }

  /// Изменение длины выбранного сегмента трубы
  void changeSelectedSegmentLength(double newLengthMm) {
    if (selectedSegmentId == null || newLengthMm <= 0.0) return;
    network.changeSegmentLength(selectedSegmentId!, newLengthMm);
    history.recordState(network);
    notifyListeners();
  }

  /// Получение выбранной катушки
  PipeSpool? get selectedSpool {
    if (selectedSpoolId == null) return null;
    return network.spools[selectedSpoolId!];
  }

  /// Изменение длины выбранной катушки трубы
  void changeSelectedSpoolLength(double newLengthMm) {
    if (selectedSpoolId == null || newLengthMm <= 0.0) return;
    network.changeSpoolLength(selectedSpoolId!, newLengthMm);
    history.recordState(network);
    notifyListeners();
  }

  /// Обновление пользовательских метаданных выбранной катушки
  void setSelectedSpoolMetadata({String? name, String? serialNumber}) {
    if (selectedSpoolId == null) return;
    network.setSpoolMetadata(selectedSpoolId!, name: name, serialNumber: serialNumber);
    history.recordState(network);
    notifyListeners();
  }

  /// Проверка, соединяет ли выбранный сегмент два отвода
  bool get isSelectedSegmentElbowToElbow {
    if (selectedSegmentId == null) return false;
    return network.isElbowToElbowSegment(selectedSegmentId!);
  }

  /// Проверка, соединены ли отводы выбранного сегмента встык
  bool get isSelectedSegmentButtJoint {
    if (selectedSegmentId == null) return false;
    return network.isButtJoint(selectedSegmentId!);
  }

  /// Рекомендуемая длина для стыковки встык (T1 + T2) для выбранного сегмента
  double? get selectedSegmentButtJointLength {
    if (selectedSegmentId == null) return null;
    return network.getElbowToElbowTargetLength(selectedSegmentId!);
  }

  /// Схлопнуть зазор между отводами выбранного сегмента встык в 1 клик
  void collapseSelectedSegmentToButtJoint() {
    if (selectedSegmentId == null) return;
    final changed = network.collapseElbowToElbow(selectedSegmentId!);
    if (changed) {
      history.recordState(network);
      notifyListeners();
    }
  }

  /// Изменение диаметра DN выбранного сегмента трубы
  void changeSelectedSegmentDn(int newDn) {
    if (selectedSegmentId == null || newDn <= 0) return;
    network.updateSegmentProperties(selectedSegmentId!, dn: newDn);
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение толщины стенки S выбранного сегмента трубы
  void changeSelectedSegmentWallThickness(double wallThicknessMm) {
    if (selectedSegmentId == null || wallThicknessMm <= 0.0) return;
    network.updateSegmentProperties(selectedSegmentId!, wallThicknessMm: wallThicknessMm);
    history.recordState(network);
    notifyListeners();
  }

  /// Комплексное изменение типоразмера трубы (DN, Dн, S)
  void changeSelectedSegmentSize({
    required int dn,
    required double outerDiameterMm,
    required double wallThicknessMm,
  }) {
    if (selectedSegmentId == null) return;
    network.updateSegmentProperties(
      selectedSegmentId!,
      dn: dn,
      outerDiameterMm: outerDiameterMm,
      wallThicknessMm: wallThicknessMm,
    );
    history.recordState(network);
    notifyListeners();
  }

  /// Добавление пользовательского типоразмера в каталог сети
  void addCustomPipeDimension(PipeDimension dim) {
    network.pipeCatalog.addCustomDimension(dim);
    notifyListeners();
  }

  /// Добавление толщины стенки к DN
  void addWallThicknessToDn(int dn, double thicknessMm) {
    network.pipeCatalog.addWallThickness(dn, thicknessMm);
    notifyListeners();
  }

  /// Изменение марки стали выбранного сегмента трубы
  void changeSelectedSegmentMaterial(String material) {
    if (selectedSegmentId == null) return;
    network.updateSegmentProperties(selectedSegmentId!, material: material);
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение пользовательской маркировки/наименования выбранного сегмента трубы
  void changeSelectedSegmentName(String? name) {
    if (selectedSegmentId == null) return;
    network.updateSegmentProperties(
      selectedSegmentId!,
      name: name,
      clearName: name == null || name.trim().isEmpty,
    );
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение заводского номера / номера партии выбранного сегмента трубы
  void changeSelectedSegmentSerialNumber(String? serialNumber) {
    if (selectedSegmentId == null) return;
    network.updateSegmentProperties(
      selectedSegmentId!,
      serialNumber: serialNumber,
      clearSerialNumber: serialNumber == null || serialNumber.trim().isEmpty,
    );
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение системы для выбранного сегмента или группы выбранных сегментов
  void changeSelectedSegmentSystem(String newSystemId) {
    final ids = selectedSegmentIds.isNotEmpty
        ? selectedSegmentIds
        : (selectedSegmentId != null ? [selectedSegmentId!] : <String>[]);
    if (ids.isEmpty) return;

    network.changeSegmentsSystem(ids, newSystemId);
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение высотной отметки (Z в метрах) для выбранного сегмента
  void changeSelectedSegmentElevation(double newZMeters) {
    if (selectedSegmentId == null) return;
    network.changeSegmentElevation(selectedSegmentId!, newZMeters);
    history.recordState(network);
    notifyListeners();
  }

  /// Сдвиг высотной отметки (дельта Z в метрах) для группы выбранных сегментов
  void shiftSelectedSegmentsElevation(double deltaZMeters) {
    final ids = selectedSegmentIds.isNotEmpty
        ? selectedSegmentIds
        : (selectedSegmentId != null ? [selectedSegmentId!] : <String>[]);
    if (ids.isEmpty || deltaZMeters.abs() < 0.0001) return;

    network.shiftSegmentsElevation(ids, deltaZMeters);
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение системы для выбранной катушки
  void changeSelectedSpoolSystem(String newSystemId) {
    if (selectedSpoolId == null) return;
    final spool = network.spools[selectedSpoolId!];
    if (spool == null) return;
    network.changeSegmentSystem(spool.segmentId, newSystemId);
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение высотной отметки (Z в метрах) для выбранной катушки
  void changeSelectedSpoolElevation(double newZMeters) {
    if (selectedSpoolId == null) return;
    final spool = network.spools[selectedSpoolId!];
    if (spool == null) return;
    network.changeSegmentElevation(spool.segmentId, newZMeters);
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение высотной отметки (Z в метрах) для выбранного узла
  void changeSelectedNodeElevation(double newZMeters) {
    if (selectedNodeId == null) return;
    network.setNodeElevation(selectedNodeId!, newZMeters);
    history.recordState(network);
    notifyListeners();
  }

  /// Изменение высотной отметки (Z в метрах) для выбранного оборудования
  void changeSelectedEquipmentElevation(double newZMeters) {
    if (selectedEquipmentId == null) return;
    network.changeEquipmentElevation(selectedEquipmentId!, newZMeters);
    history.recordState(network);
    notifyListeners();
  }

  /// Удаление выбранного узла, оборудования, сегмента, размера или выноски с каскадной очисткой связей
  void deleteSelected() {
    if (selectedCalloutId != null) {
      network.callouts.remove(selectedCalloutId);
      selectedCalloutId = null;
      history.recordState(network);
      notifyListeners();
      return;
    }

    if (selectedDimensionId != null) {
      network.removeDimension(selectedDimensionId!);
      selectedDimensionId = null;
      history.recordState(network);
      notifyListeners();
      return;
    }

    if (selectedAxisId != null) {
      network.axes.remove(selectedAxisId);
      selectedAxisId = null;
      history.recordState(network);
      notifyListeners();
      return;
    }

    if (selectedValveId != null) {
      final vId = selectedValveId!;
      network.valves.remove(vId);
      network.callouts.removeWhere((_, c) => c.targetId == vId);
      selectedValveId = null;
      network.recalculateSpools();
      history.recordState(network);
      notifyListeners();
      return;
    }

    if (selectedSupportId != null) {
      final sId = selectedSupportId!;
      network.supports.remove(sId);
      network.callouts.removeWhere((_, c) => c.targetId == sId);
      selectedSupportId = null;
      history.recordState(network);
      notifyListeners();
      return;
    }

    if (selectedWeldId != null) {
      final wId = selectedWeldId!;
      network.weldJoints.remove(wId);
      network.callouts.removeWhere((_, c) => c.targetId == wId);
      selectedWeldId = null;
      network.recalculateSpools();
      history.recordState(network);
      notifyListeners();
      return;
    }

    // Множественное удаление
    if (selectedNodeIds.length > 1 ||
        selectedSegmentIds.length > 1 ||
        selectedEquipmentIds.isNotEmpty ||
        selectedAxisIds.isNotEmpty ||
        selectedDimensionIds.isNotEmpty ||
        (selectedNodeIds.isNotEmpty && selectedSegmentIds.isNotEmpty)) {
      history.recordState(network);
      for (final eqId in selectedEquipmentIds.toList()) {
        network.removeEquipment(eqId);
        network.callouts.removeWhere((_, c) => c.targetId == eqId);
      }
      for (final axisId in selectedAxisIds.toList()) {
        network.axes.remove(axisId);
      }
      for (final dimId in selectedDimensionIds.toList()) {
        network.removeDimension(dimId);
      }
      for (final segId in selectedSegmentIds.toList()) {
        network.segments.remove(segId);
        network.valves.removeWhere((_, v) => v.segmentId == segId);
        network.weldJoints.removeWhere((_, w) => w.segmentId == segId);
        network.supports.removeWhere((_, s) => s.segmentId == segId);
        network.callouts.removeWhere((_, c) => c.targetId == segId);
      }
      for (final nodeId in selectedNodeIds.toList()) {
        final segs = network.segments.values
            .where((s) => s.startNodeId == nodeId || s.endNodeId == nodeId)
            .map((s) => s.id)
            .toList();
        for (final sid in segs) {
          network.segments.remove(sid);
          network.valves.removeWhere((_, v) => v.segmentId == sid);
          network.weldJoints.removeWhere((_, w) => w.segmentId == sid);
          network.supports.removeWhere((_, s) => s.segmentId == sid);
          network.callouts.removeWhere((_, c) => c.targetId == sid);
        }
        network.fittings.remove(nodeId);
        network.nodes.remove(nodeId);
        network.callouts.removeWhere((_, c) => c.targetId == nodeId);
      }
      selectedNodeIds.clear();
      selectedSegmentIds.clear();
      selectedEquipmentIds.clear();
      selectedAxisIds.clear();
      selectedDimensionIds.clear();
      selectedNodeId = null;
      selectedSegmentId = null;
      selectedEquipmentId = null;
      selectedAxisId = null;
      selectedDimensionId = null;
      selectedValveId = null;
      selectedSupportId = null;
      selectedWeldId = null;
      network.autoDetectAllFittings();
      network.cleanupUnusedEquipmentNozzles();
      network.recalculateSpools();
      notifyListeners();
      return;
    }

    final selectedNode = selectedNodeId != null ? network.nodes[selectedNodeId] : null;
    final eqToDelete = selectedEquipmentId ?? (selectedSegmentId == null ? selectedNode?.equipmentId : null);
    if (eqToDelete != null && (selectedSegmentId == null || selectedEquipmentId != null)) {
      network.removeEquipment(eqToDelete);
      network.callouts.removeWhere((_, c) => c.targetId == eqToDelete);
      selectedEquipmentId = null;
      selectedNodeId = null;
      selectedSegmentId = null;
      history.recordState(network);
      notifyListeners();
      return;
    }

    if (selectedNodeId != null) {
      final nodeId = selectedNodeId!;
      history.recordState(network);
      network.dissolveNode(nodeId);
      network.cleanupUnusedEquipmentNozzles();

      selectedNodeIds.remove(nodeId);
      selectedNodeId = null;
      selectedSegmentId = null;
      notifyListeners();
    } else if (selectedSegmentId != null) {
      final segId = selectedSegmentId!;
      final seg = network.segments[segId];
      final startNodeId = seg?.startNodeId;
      final endNodeId = seg?.endNodeId;

      network.segments.remove(segId);
      network.valves.removeWhere((_, v) => v.segmentId == segId);
      network.weldJoints.removeWhere((_, w) => w.segmentId == segId);
      network.supports.removeWhere((_, s) => s.segmentId == segId);
      network.callouts.removeWhere((_, c) => c.targetId == segId);

      if (startNodeId != null && network.getConnectedSegments(startNodeId).isEmpty) {
        network.fittings.remove(startNodeId);
      }
      if (endNodeId != null && network.getConnectedSegments(endNodeId).isEmpty) {
        network.fittings.remove(endNodeId);
      }
      network.cleanupUnusedEquipmentNozzles();

      selectedSegmentIds.remove(segId);
      selectedSegmentId = null;
      network.recalculateSpools();
      history.recordState(network);
      notifyListeners();
    }
  }

  /// Перемещение всех выделенных элементов на вектор (dx, dy, dz)
  bool moveSelectedBy({required double dx, required double dy, required double dz}) {
    if (dx == 0 && dy == 0 && dz == 0) return false;

    final nodeIdsToMove = <String>{...selectedNodeIds};
    for (final segId in selectedSegmentIds) {
      final seg = network.segments[segId];
      if (seg != null) {
        nodeIdsToMove.add(seg.startNodeId);
        nodeIdsToMove.add(seg.endNodeId);
      }
    }
    if (nodeIdsToMove.isEmpty && selectedNodeId != null) {
      nodeIdsToMove.add(selectedNodeId!);
    }

    // Перемещение узлов
    for (final nid in nodeIdsToMove) {
      final n = network.nodes[nid];
      if (n != null) {
        network.moveNode(nid, n.x + dx, n.y + dy, n.z + dz);
      }
    }

    // Перемещение оборудования
    final eqIdsToMove = <String>{...selectedEquipmentIds};
    if (selectedEquipmentId != null) eqIdsToMove.add(selectedEquipmentId!);
    for (final eqId in eqIdsToMove) {
      final eq = network.equipments[eqId];
      if (eq != null) {
        network.equipments[eqId] = eq.copyWith(
          x: eq.x + dx,
          y: eq.y + dy,
          z: eq.z + dz,
        );
      }
    }

    // Перемещение строительных осей
    final axisIdsToMove = <String>{...selectedAxisIds};
    if (selectedAxisId != null) axisIdsToMove.add(selectedAxisId!);
    for (final axId in axisIdsToMove) {
      final ax = network.axes[axId];
      if (ax != null) {
        network.axes[axId] = ax.copyWith(
          startPoint: ax.startPoint.copyWith(x: ax.startPoint.x + dx, y: ax.startPoint.y + dy, z: ax.startPoint.z + dz),
          endPoint: ax.endPoint.copyWith(x: ax.endPoint.x + dx, y: ax.endPoint.y + dy, z: ax.endPoint.z + dz),
        );
      }
    }

    // Перемещение размеров
    final dimIdsToMove = <String>{...selectedDimensionIds};
    if (selectedDimensionId != null) dimIdsToMove.add(selectedDimensionId!);
    for (final dimId in dimIdsToMove) {
      final dim = network.dimensions[dimId];
      if (dim != null) {
        network.dimensions[dimId] = dim.copyWith(
          startPoint: dim.startPoint.copyWith(x: dim.startPoint.x + dx, y: dim.startPoint.y + dy, z: dim.startPoint.z + dz),
          endPoint: dim.endPoint.copyWith(x: dim.endPoint.x + dx, y: dim.endPoint.y + dy, z: dim.endPoint.z + dz),
        );
      }
    }

    network.autoDetectAllFittings();
    network.recalculateSpools();
    history.recordState(network);
    notifyListeners();
    return true;
  }

  /// Дублирование выделенного подграфа со сдвигом (dx, dy, dz)
  bool duplicateSelection({
    double dx = 500.0,
    double dy = 500.0,
    double dz = 0.0,
    bool updateSelection = true,
  }) {
    final nodeIdsToCopy = <String>{...selectedNodeIds};
    for (final segId in selectedSegmentIds) {
      final seg = network.segments[segId];
      if (seg != null) {
        nodeIdsToCopy.add(seg.startNodeId);
        nodeIdsToCopy.add(seg.endNodeId);
      }
    }
    if (nodeIdsToCopy.isEmpty && selectedNodeId != null) {
      nodeIdsToCopy.add(selectedNodeId!);
    }

    final eqIdsToCopy = <String>{...selectedEquipmentIds};
    if (selectedEquipmentId != null) eqIdsToCopy.add(selectedEquipmentId!);

    final axisIdsToCopy = <String>{...selectedAxisIds};
    if (selectedAxisId != null) axisIdsToCopy.add(selectedAxisId!);

    final dimIdsToCopy = <String>{...selectedDimensionIds};
    if (selectedDimensionId != null) dimIdsToCopy.add(selectedDimensionId!);

    if (nodeIdsToCopy.isEmpty && eqIdsToCopy.isEmpty && axisIdsToCopy.isEmpty && dimIdsToCopy.isEmpty) {
      return false;
    }

    final oldToNewNodeId = <String, String>{};
    for (final oldId in nodeIdsToCopy) {
      final oldNode = network.nodes[oldId];
      if (oldNode == null) continue;
      final newId = 'node_${_uuid.v4()}';
      final newNode = Node3D(
        id: newId,
        x: oldNode.x + dx,
        y: oldNode.y + dy,
        z: oldNode.z + dz,
      );
      network.nodes[newId] = newNode;
      oldToNewNodeId[oldId] = newId;
    }

    final newSegmentIds = <String>{};
    for (final seg in network.segments.values.toList()) {
      if (oldToNewNodeId.containsKey(seg.startNodeId) && oldToNewNodeId.containsKey(seg.endNodeId)) {
        final newSegId = 'seg_${_uuid.v4()}';
        final newStartId = oldToNewNodeId[seg.startNodeId]!;
        final newEndId = oldToNewNodeId[seg.endNodeId]!;
        final newSeg = seg.copyWith(
          id: newSegId,
          startNodeId: newStartId,
          endNodeId: newEndId,
        );
        network.segments[newSegId] = newSeg;
        newSegmentIds.add(newSegId);

        // Копируем арматуру
        for (final v in network.valves.values.where((val) => val.segmentId == seg.id).toList()) {
          final newValveId = 'valve_${_uuid.v4()}';
          network.valves[newValveId] = v.copyWith(id: newValveId, segmentId: newSegId);
        }

        // Копируем сварные стыки
        for (final w in network.weldJoints.values.where((wj) => wj.segmentId == seg.id).toList()) {
          final newWeldId = 'weld_${_uuid.v4()}';
          final newWeldNum = network.weldJoints.length + 1;
          network.weldJoints[newWeldId] = w.copyWith(
            id: newWeldId,
            segmentId: newSegId,
            number: newWeldNum,
          );
        }

        // Копируем опоры
        for (final s in network.supports.values.where((sup) => sup.segmentId == seg.id).toList()) {
          final newSupId = 'sup_${_uuid.v4()}';
          network.supports[newSupId] = s.copyWith(id: newSupId, segmentId: newSegId);
        }
      }
    }

    // Копируем оборудование
    final oldToNewEqId = <String, String>{};
    for (final oldEqId in eqIdsToCopy) {
      final oldEq = network.equipments[oldEqId];
      if (oldEq == null) continue;
      final newEqId = 'eq_${_uuid.v4()}';
      network.equipments[newEqId] = oldEq.copyWith(
        id: newEqId,
        x: oldEq.x + dx,
        y: oldEq.y + dy,
        z: oldEq.z + dz,
      );
      oldToNewEqId[oldEqId] = newEqId;
    }

    // Копируем строительные оси
    final newAxisIds = <String>{};
    for (final oldAxId in axisIdsToCopy) {
      final oldAx = network.axes[oldAxId];
      if (oldAx == null) continue;
      final newAxId = 'axis_${_uuid.v4()}';
      network.axes[newAxId] = oldAx.copyWith(
        id: newAxId,
        startPoint: oldAx.startPoint.copyWith(x: oldAx.startPoint.x + dx, y: oldAx.startPoint.y + dy, z: oldAx.startPoint.z + dz),
        endPoint: oldAx.endPoint.copyWith(x: oldAx.endPoint.x + dx, y: oldAx.endPoint.y + dy, z: oldAx.endPoint.z + dz),
      );
      newAxisIds.add(newAxId);
    }

    // Копируем размеры
    final newDimIds = <String>{};
    for (final oldDimId in dimIdsToCopy) {
      final oldDim = network.dimensions[oldDimId];
      if (oldDim == null) continue;
      final newDimId = 'dim_${_uuid.v4()}';
      network.dimensions[newDimId] = oldDim.copyWith(
        id: newDimId,
        startPoint: oldDim.startPoint.copyWith(x: oldDim.startPoint.x + dx, y: oldDim.startPoint.y + dy, z: oldDim.startPoint.z + dz),
        endPoint: oldDim.endPoint.copyWith(x: oldDim.endPoint.x + dx, y: oldDim.endPoint.y + dy, z: oldDim.endPoint.z + dz),
      );
      newDimIds.add(newDimId);
    }

    network.autoDetectAllFittings();
    network.recalculateSpools();

    // Выбираем скопированные элементы
    if (updateSelection) {
      selectedNodeIds.clear();
      selectedNodeIds.addAll(oldToNewNodeId.values);
      selectedSegmentIds.clear();
      selectedSegmentIds.addAll(newSegmentIds);
      selectedEquipmentIds.clear();
      selectedEquipmentIds.addAll(oldToNewEqId.values);
      selectedAxisIds.clear();
      selectedAxisIds.addAll(newAxisIds);
      selectedDimensionIds.clear();
      selectedDimensionIds.addAll(newDimIds);

      selectedNodeId = selectedNodeIds.isNotEmpty ? selectedNodeIds.first : null;
      selectedSegmentId = selectedSegmentIds.isNotEmpty ? selectedSegmentIds.first : null;
      selectedEquipmentId = selectedEquipmentIds.isNotEmpty ? selectedEquipmentIds.first : null;
      selectedAxisId = selectedAxisIds.isNotEmpty ? selectedAxisIds.first : null;
      selectedDimensionId = selectedDimensionIds.isNotEmpty ? selectedDimensionIds.first : null;
    }

    history.recordState(network);
    notifyListeners();
    return true;
  }

  /// Поворот выделенных элементов вокруг оси Z на angleDegrees (по часовой стрелке)
  bool rotateSelectionAroundZ(double angleDegrees, {Node3D? customCenter}) {
    final nodeIdsToRotate = <String>{...selectedNodeIds};
    for (final segId in selectedSegmentIds) {
      final seg = network.segments[segId];
      if (seg != null) {
        nodeIdsToRotate.add(seg.startNodeId);
        nodeIdsToRotate.add(seg.endNodeId);
      }
    }
    if (nodeIdsToRotate.isEmpty && selectedNodeId != null) {
      nodeIdsToRotate.add(selectedNodeId!);
    }

    final eqIdsToRotate = <String>{...selectedEquipmentIds};
    if (selectedEquipmentId != null) eqIdsToRotate.add(selectedEquipmentId!);

    final axisIdsToRotate = <String>{...selectedAxisIds};
    if (selectedAxisId != null) axisIdsToRotate.add(selectedAxisId!);

    final dimIdsToRotate = <String>{...selectedDimensionIds};
    if (selectedDimensionId != null) dimIdsToRotate.add(selectedDimensionId!);

    if (nodeIdsToRotate.isEmpty && eqIdsToRotate.isEmpty && axisIdsToRotate.isEmpty && dimIdsToRotate.isEmpty) {
      return false;
    }

    history.recordState(network);

    double centerX = 0.0;
    double centerY = 0.0;

    if (customCenter != null) {
      centerX = customCenter.x;
      centerY = customCenter.y;
    } else {
      double sumX = 0.0;
      double sumY = 0.0;
      int count = 0;
      for (final id in nodeIdsToRotate) {
        final n = network.nodes[id];
        if (n != null) {
          sumX += n.x;
          sumY += n.y;
          count++;
        }
      }
      for (final id in eqIdsToRotate) {
        final eq = network.equipments[id];
        if (eq != null) {
          sumX += eq.x;
          sumY += eq.y;
          count++;
        }
      }
      for (final id in axisIdsToRotate) {
        final ax = network.axes[id];
        if (ax != null) {
          sumX += (ax.startPoint.x + ax.endPoint.x) / 2;
          sumY += (ax.startPoint.y + ax.endPoint.y) / 2;
          count++;
        }
      }
      if (count == 0) return false;
      centerX = sumX / count;
      centerY = sumY / count;
    }

    final rad = angleDegrees * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);

    for (final id in nodeIdsToRotate) {
      final n = network.nodes[id];
      if (n == null) continue;
      final relX = n.x - centerX;
      final relY = n.y - centerY;
      final rotX = (centerX + relX * cosA - relY * sinA).roundToDouble();
      final rotY = (centerY + relX * sinA + relY * cosA).roundToDouble();
      network.moveNode(id, rotX, rotY, n.z);
    }

    for (final id in eqIdsToRotate) {
      final eq = network.equipments[id];
      if (eq == null) continue;
      final relX = eq.x - centerX;
      final relY = eq.y - centerY;
      final rotX = (centerX + relX * cosA - relY * sinA).roundToDouble();
      final rotY = (centerY + relX * sinA + relY * cosA).roundToDouble();
      network.equipments[id] = eq.copyWith(x: rotX, y: rotY);
    }

    for (final id in axisIdsToRotate) {
      final ax = network.axes[id];
      if (ax == null) continue;
      final sRelX = ax.startPoint.x - centerX;
      final sRelY = ax.startPoint.y - centerY;
      final sRotX = (centerX + sRelX * cosA - sRelY * sinA).roundToDouble();
      final sRotY = (centerY + sRelX * sinA + sRelY * cosA).roundToDouble();

      final eRelX = ax.endPoint.x - centerX;
      final eRelY = ax.endPoint.y - centerY;
      final eRotX = (centerX + eRelX * cosA - eRelY * sinA).roundToDouble();
      final eRotY = (centerY + eRelX * sinA + eRelY * cosA).roundToDouble();

      network.axes[id] = ax.copyWith(
        startPoint: ax.startPoint.copyWith(x: sRotX, y: sRotY),
        endPoint: ax.endPoint.copyWith(x: eRotX, y: eRotY),
      );
    }

    network.autoDetectAllFittings();
    network.recalculateSpools();
    history.recordState(network);
    notifyListeners();
    return true;
  }

  void _updateDimensionOffset(Offset screenPos) {
    if (dimensionStartNode == null || dimensionEndNode == null) return;
    final p1 = projector.project(dimensionStartNode!);
    final p2 = projector.project(dimensionEndNode!);
    final delta = p2 - p1;
    final dist = delta.distance;
    if (dist < 1.0) return;
    final u = delta / dist;
    final n = Offset(-u.dy, u.dx);
    final offset = (screenPos.dx - p1.dx) * n.dx + (screenPos.dy - p1.dy) * n.dy;
    dimensionOffset = offset.abs() < 5.0 ? (offset >= 0 ? 35.0 : -35.0) : offset;
  }

  String? _findDimensionAtScreenPos(Offset screenPos) {
    for (final dim in network.dimensions.values) {
      final p1 = projector.project(dim.startPoint);
      final p2 = projector.project(dim.endPoint);
      final delta = p2 - p1;
      final dist = delta.distance;
      if (dist < 1.0) continue;
      final u = delta / dist;
      final n = Offset(-u.dy, u.dx);
      final offsetDist = dim.offsetDistance == 0.0 ? 35.0 : dim.offsetDistance;
      final d1 = p1 + n * offsetDist;
      final d2 = p2 + n * offsetDist;
      final lineVec = d2 - d1;
      final lenSq = lineVec.dx * lineVec.dx + lineVec.dy * lineVec.dy;
      final t = lenSq == 0 ? 0.0 : (((screenPos.dx - d1.dx) * lineVec.dx + (screenPos.dy - d1.dy) * lineVec.dy) / lenSq).clamp(0.0, 1.0);
      final proj = d1 + lineVec * t;
      if ((screenPos - proj).distance <= 12.0) {
        return dim.id;
      }
    }
    return null;
  }

  /// Поиск оси или опорной линии под курсором (с проверкой кружков марок, краев и отрезка)
  String? _findAxisAtScreenPos(Offset screenPos) {
    const clickDistanceThreshold = 14.0;
    const endPointRadiusThreshold = 18.0;

    for (final axis in network.axes.values) {
      final p1 = projector.project(axis.startPoint);
      final p2 = projector.project(axis.endPoint);

      // Проверка клика в концы осей (кружки марок или края линий)
      if ((screenPos - p1).distance <= endPointRadiusThreshold ||
          (screenPos - p2).distance <= endPointRadiusThreshold) {
        return axis.id;
      }

      // Также проверяем концы на currentElevationZ, если ось на другой высоте Z
      if ((axis.startPoint.z - currentElevationZ).abs() > 1.0) {
        final p1z = projector.projectCoordinates(axis.startPoint.x, axis.startPoint.y, currentElevationZ);
        final p2z = projector.projectCoordinates(axis.endPoint.x, axis.endPoint.y, currentElevationZ);
        if ((screenPos - p1z).distance <= endPointRadiusThreshold ||
            (screenPos - p2z).distance <= endPointRadiusThreshold) {
          return axis.id;
        }
      }

      // Проверка клика по отрезку оси
      final dist = _distanceToLineSegment(screenPos, p1, p2);
      if (dist <= clickDistanceThreshold) {
        return axis.id;
      }

      // Также проверяем отрезок оси на currentElevationZ
      if ((axis.startPoint.z - currentElevationZ).abs() > 1.0) {
        final p1z = projector.projectCoordinates(axis.startPoint.x, axis.startPoint.y, currentElevationZ);
        final p2z = projector.projectCoordinates(axis.endPoint.x, axis.endPoint.y, currentElevationZ);
        final distZ = _distanceToLineSegment(screenPos, p1z, p2z);
        if (distZ <= clickDistanceThreshold) {
          return axis.id;
        }
      }
    }
    return null;
  }

  bool _segmentIntersectsRect(Offset p1, Offset p2, Rect rect) =>
      SelectionController.segmentIntersectsRect(p1, p2, rect);

  void _checkAndMergeOpenNodes() {
    if (selectedNodeId == null) return;
    final movedNodes = selectedNodeIds.isNotEmpty ? selectedNodeIds.toList() : [selectedNodeId!];
    for (final mId in movedNodes) {
      final nodeA = network.nodes[mId];
      if (nodeA == null) continue;
      final connsA = network.getConnectedSegments(mId);
      if (connsA.length != 1) continue;

      for (final otherNode in network.nodes.values) {
        if (movedNodes.contains(otherNode.id)) continue;
        final connsOther = network.getConnectedSegments(otherNode.id);
        if (connsOther.length != 1) continue;

        if (nodeA.distanceTo(otherNode) <= 35.0) {
          final seg = connsA.first;
          if (seg.startNodeId == mId) {
            network.segments[seg.id] = seg.copyWith(startNodeId: otherNode.id);
          } else {
            network.segments[seg.id] = seg.copyWith(endNodeId: otherNode.id);
          }
          network.nodes.remove(mId);
          network.fittings.remove(mId);
          selectedNodeIds.remove(mId);
          selectedNodeIds.add(otherNode.id);
          if (selectedNodeId == mId) selectedNodeId = otherNode.id;
          network.autoDetectAllFittings();
          network.recalculateSpools();
          break;
        }
      }
    }
  }

  // ==========================================
  // Callouts (Умные выноски)
  // ==========================================

  /// Генерация технологических сварных стыков по ГОСТ 16037 для всех элементов сети
  int generateElementWeldJoints() {
    final count = network.generateElementWeldJoints();
    if (count > 0) {
      history.recordState(network);
      notifyListeners();
    }
    return count;
  }

  /// Проверка топологической связности сварных стыков, удаление невалидных и перенумерация
  int validateAndCleanWeldJoints() {
    final removed = network.validateAndCleanWeldJoints();
    if (removed > 0) {
      history.recordState(network);
      notifyListeners();
    }
    return removed;
  }

  /// Генерация недостающих выносок для сегментов, арматуры и стыков
  int generateMissingCallouts({
    Set<CalloutTargetType>? targetTypes,
    double offsetX = 50.0,
    double offsetY = -50.0,
  }) {
    final count = network.generateMissingCallouts(
      targetTypes: targetTypes,
      offsetX: offsetX,
      offsetY: offsetY,
    );
    if (count > 0) {
      history.recordState(network);
      notifyListeners();
    }
    return count;
  }

  /// Генерация выносок конкретно для элементов сети (арматура, фитинги, оборудование, опоры)
  int generateElementCallouts({double offsetX = 50.0, double offsetY = -50.0}) {
    return generateMissingCallouts(
      targetTypes: const {
        CalloutTargetType.valve,
        CalloutTargetType.fitting,
        CalloutTargetType.equipment,
        CalloutTargetType.support,
      },
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  /// Генерация выносок высотных отметок для стояков и свободных концов (ГОСТ 21.101)
  int generateElevationCallouts({double offsetX = 50.0, double offsetY = -50.0}) {
    return generateMissingCallouts(
      targetTypes: const {CalloutTargetType.node},
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  /// Добавление или удаление выноски высотной отметки ГОСТ 21.101 для конкретного узла
  bool toggleNodeElevationCallout(
    String nodeId, {
    double offsetX = 50.0,
    double offsetY = -50.0,
    ElevationMarkStyle? style,
    ShelfDirection? direction,
    bool? arrowOnNode,
  }) {
    if (!network.nodes.containsKey(nodeId)) return false;
    final existingCallout = network.callouts.values
        .where((c) => c.targetType == CalloutTargetType.node && c.targetId == nodeId)
        .firstOrNull;
    if (existingCallout != null) {
      network.callouts.remove(existingCallout.id);
      history.recordState(network);
      notifyListeners();
      return false;
    } else {
      final id = 'callout_elev_${DateTime.now().millisecondsSinceEpoch}_$nodeId';
      final defaultArrowOnNode = currentProject.calloutTemplates['elevation_arrow_on_node'] != 'false';
      network.callouts[id] = Callout(
        id: id,
        targetId: nodeId,
        targetType: CalloutTargetType.node,
        screenOffsetX: offsetX,
        screenOffsetY: offsetY,
        elevationStyle: style,
        shelfDirection: direction ?? ShelfDirection.auto,
        arrowOnNode: arrowOnNode ?? defaultArrowOnNode,
      );
      history.recordState(network);
      notifyListeners();
      return true;
    }
  }

  /// Проверка, имеет ли узел выноску высотной отметки
  bool nodeHasElevationCallout(String nodeId) {
    return network.callouts.values.any((c) => c.targetType == CalloutTargetType.node && c.targetId == nodeId);
  }

  /// Получить выноску высотной отметки узла (если есть)
  Callout? getNodeElevationCallout(String nodeId) {
    return network.callouts.values
        .where((c) => c.targetType == CalloutTargetType.node && c.targetId == nodeId)
        .firstOrNull;
  }

  /// Обновление стиля, стороны полки или положения стрелки высотной отметки узла
  void updateNodeElevationCallout(
    String nodeId, {
    ElevationMarkStyle? style,
    ShelfDirection? direction,
    bool? arrowOnNode,
  }) {
    final existing = getNodeElevationCallout(nodeId);
    if (existing == null) return;
    network.callouts[existing.id] = existing.copyWith(
      elevationStyle: style,
      shelfDirection: direction ?? existing.shelfDirection,
      arrowOnNode: arrowOnNode ?? existing.arrowOnNode,
    );
    history.recordState(network);
    notifyListeners();
  }

  /// Генерация сварных стыков для элементов сети и создание выносок для них
  Map<String, int> generateWeldsAndCallouts({double offsetX = 50.0, double offsetY = -50.0}) {
    final weldsAdded = network.generateElementWeldJoints();
    final calloutsAdded = network.generateMissingCallouts(
      targetTypes: const {CalloutTargetType.weld},
      offsetX: offsetX,
      offsetY: offsetY,
    );
    if (weldsAdded > 0 || calloutsAdded > 0) {
      history.recordState(network);
      notifyListeners();
    }
    return {
      'welds': weldsAdded,
      'callouts': calloutsAdded,
    };
  }

  /// Обновление выноски
  void updateCallout(Callout callout) {
    network.callouts[callout.id] = callout;
    history.recordState(network);
    notifyListeners();
  }

  /// Удаление выноски
  void removeCallout(String id) {
    if (network.callouts.containsKey(id)) {
      network.callouts.remove(id);
      history.recordState(network);
      notifyListeners();
    }
  }

  /// Переключение выноски между режимом "по шаблону" и "свой текст"
  void toggleCalloutMode(String id, bool isCustom) {
    final callout = network.callouts[id];
    if (callout == null) return;
    if (isCustom) {
      // Инициализируем пользовательский текст текущим сгенерированным по шаблону
      final currentText = network.generateCalloutText(callout, currentProject.calloutTemplates);
      network.callouts[id] = callout.copyWith(customText: currentText);
    } else {
      network.callouts[id] = callout.copyWith(clearCustomText: true);
    }
    history.recordState(network);
    notifyListeners();
  }

  /// Обновление пользовательского текста выноски (над полкой)
  void updateCalloutCustomText(String id, String customText) {
    final callout = network.callouts[id];
    if (callout == null) return;
    network.callouts[id] = callout.copyWith(customText: customText);
    history.recordState(network);
    notifyListeners();
  }

  /// Обновление пользовательского текста выноски под полкой
  void updateCalloutCustomBottomText(String id, String? customBottomText) {
    final callout = network.callouts[id];
    if (callout == null) return;
    network.callouts[id] = callout.copyWith(customBottomText: customBottomText);
    history.recordState(network);
    notifyListeners();
  }

  /// Получение итогового текста выноски для отображения над полкой
  String getCalloutText(Callout callout) {
    return network.generateCalloutText(callout, currentProject.calloutTemplates);
  }

  /// Получение итогового текста выноски для отображения под полкой
  String? getCalloutBottomText(Callout callout) {
    return network.generateCalloutBottomText(callout, currentProject.calloutTemplates);
  }

  /// Обновление глобального шаблона выносок в текущем проекте
  void updateCalloutTemplate(String key, String template) {
    currentProject.calloutTemplates[key] = template;
    history.recordState(network);
    notifyListeners();
  }

  /// Поиск выноски под курсором (hit-test по тексту и полочке)
  String? _findCalloutAtScreenPos(Offset screenPos) {
    return CalloutPainter.hitTest(
      screenPos,
      network,
      projector,
      templates: currentProject.calloutTemplates,
      project: currentProject,
    );
  }

  /// Явный выбор выноски по ID
  void selectCallout(String? calloutId) {
    selectedCalloutId = calloutId;
    if (calloutId != null) {
      selectedNodeId = null;
      selectedSegmentId = null;
      selectedEquipmentId = null;
    }
    notifyListeners();
  }

  /// Сохранение текущего проекта. Если файл еще не имеет пути на диске — вызывает saveProjectAs()
  Future<bool> saveProject() async {
    if (currentFilePath == null) {
      return await saveProjectAs();
    }
    isSaving = true;
    notifyListeners();
    try {
      currentProject = currentProject.copyWith(
        network: network,
        lastModifiedDate: DateTime.now().toIso8601String(),
      );
      final savedPath = await projectRepository.saveProject(
        currentProject,
        targetPath: currentFilePath,
      );
      if (savedPath != null) {
        currentFilePath = savedPath;
        hasUnsavedChanges = false;
        await recentProjectsManager.addRecentProject(RecentProjectEntry(
          title: currentProject.title,
          filePath: savedPath,
          projectCode: currentProject.projectCode,
          lastOpened: DateTime.now(),
        ));
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error saving project: $e');
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  /// Сохранение проекта в новый файл (Диалог выбора папки и имени)
  Future<bool> saveProjectAs() async {
    isSaving = true;
    notifyListeners();
    try {
      currentProject = currentProject.copyWith(
        network: network,
        lastModifiedDate: DateTime.now().toIso8601String(),
      );
      final savedPath = await projectRepository.saveProject(
        currentProject,
        targetPath: null,
      );
      if (savedPath != null) {
        currentFilePath = savedPath;
        hasUnsavedChanges = false;
        await recentProjectsManager.addRecentProject(RecentProjectEntry(
          title: currentProject.title,
          filePath: savedPath,
          projectCode: currentProject.projectCode,
          lastOpened: DateTime.now(),
        ));
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error saving project as: $e');
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  /// Открытие проекта (по указанному пути или через диалог выбора файлов)
  Future<bool> openProject({String? filePath}) async {
    isLoading = true;
    notifyListeners();
    try {
      final result = await projectRepository.loadProject(filePath: filePath);
      if (result != null) {
        currentProject = result.project;
        network = result.project.network;
        currentFilePath = result.filePath.isNotEmpty ? result.filePath : null;
        history.clear();
        history.recordState(network);
        hasUnsavedChanges = false;

        if (currentFilePath != null) {
          await recentProjectsManager.addRecentProject(RecentProjectEntry(
            title: currentProject.title,
            filePath: currentFilePath!,
            projectCode: currentProject.projectCode,
            lastOpened: DateTime.now(),
          ));
        }

        cancelCurrentOperation(keepTool: true);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error opening project: $e');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Загрузка проекта (совместимость со старыми вызовами)
  Future<void> loadProject() async {
    await openProject();
  }

  /// Создание нового чистого проекта
  bool newProject({bool force = false}) {
    network = PipingNetwork();
    currentProject = ProjectModel(
      id: _uuid.v4(),
      title: 'Новый проект',
      network: network,
    );
    currentFilePath = null;
    history.clear();
    history.recordState(network);
    hasUnsavedChanges = false;
    cancelCurrentOperation(keepTool: false);
    notifyListeners();
    return true;
  }

  /// Обновление метаданных проекта (название, шифр, адрес, инженер, примечания)
  void updateProjectMetadata({
    String? title,
    String? projectCode,
    String? objectAddress,
    String? engineerName,
    String? notes,
  }) {
    currentProject = currentProject.copyWith(
      title: title,
      projectCode: projectCode,
      objectAddress: objectAddress,
      engineerName: engineerName,
      notes: notes,
      lastModifiedDate: DateTime.now().toIso8601String(),
    );
    hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Системный экспорт/передача проекта через SharePlus
  Future<void> shareCurrentProject() async {
    currentProject = currentProject.copyWith(
      network: network,
      lastModifiedDate: DateTime.now().toIso8601String(),
    );
    await projectRepository.shareProjectFile(currentProject);
  }
}
