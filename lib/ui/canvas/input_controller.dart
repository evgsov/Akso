import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/math/axonometry_projector.dart';
import '../../core/math/snap_engine.dart';
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
import '../../domain/models/pipe_support.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/project_model.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/recovery_repository.dart';
import 'painters/callout_painter.dart';

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

  void setVolumeMode(bool value) {
    if (isVolumeMode == value) return;
    isVolumeMode = value;
    notifyListeners();
  }

  // История и отмена (Undo / Redo)
  final NetworkHistoryManager history = NetworkHistoryManager(maxSnapshots: 50);

  // Движок магнитных привязок и полярных углов
  final SnapEngine snapEngine = const SnapEngine();
  SnapResult? currentSnapResult;
  AngleSnapMode angleSnapMode = AngleSnapMode.ortho90;
  double customAngleDegrees = 15.0;
  bool isSnapEnabled = true;
  bool showGrid = true;

  // Интерактивное состояние
  String? selectedNodeId;
  String? selectedSegmentId;
  String? selectedEquipmentId;
  String? selectedCalloutId;
  String? hoveredNodeId;

  // Мультиселекция и рамочный выбор
  final Set<String> selectedNodeIds = {};
  final Set<String> selectedSegmentIds = {};
  final Set<String> selectedEquipmentIds = {};
  final Set<String> selectedAxisIds = {};
  final Set<String> selectedDimensionIds = {};
  Rect? selectionBoxRect;
  Offset? boxSelectStart;
  bool isCrossingSelection = false;

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
  String? selectedDimensionId;
  String? selectedAxisId;

  Node3D? traceStartNode;
  Node3D? axisStartNode;
  String currentAxisLabel = '1';
  bool isBuildingGridAxis = true;
  Offset? currentCursorScreenPos;

  // Режим перетаскивания
  bool isDraggingNode = false;
  bool isDraggingEquipment = false;
  bool isDraggingCallout = false;
  Node3D? _dragEquipmentStartPos;
  Offset? _dragCalloutStartScreenPos;
  double _dragCalloutInitialOffsetX = 0.0;
  double _dragCalloutInitialOffsetY = 0.0;

  late ProjectModel currentProject;
  final IProjectRepository projectRepository;

  Timer? _recoveryTimer;

  PipingInputController({
    PipingNetwork? network,
    PipingNetwork? initialNetwork,
    AxonometryProjector? projector,
    IProjectRepository? projectRepository,
    IProjectRepository? repository,
  })  : network = network ?? initialNetwork ?? PipingNetwork(),
        projector = projector ??
            const AxonometryProjector(
              projectionType: ProjectionType.gostFrontal45,
            ),
        projectRepository = repository ?? projectRepository ?? ProjectRepository() {
    currentProject = ProjectModel(
      id: _uuid.v4(),
      title: 'Новый проект',
      network: this.network,
    );
    history.recordState(this.network);

    _recoveryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      RecoveryRepository().saveRecovery(currentProject.copyWith(network: this.network));
    });
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
    _recoveryTimer?.cancel();
    super.dispose();
  }

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  void undo() {
    if (history.undo(network)) {
      cancelCurrentOperation(keepTool: true);
      notifyListeners();
    }
  }

  void redo() {
    if (history.redo(network)) {
      cancelCurrentOperation(keepTool: true);
      notifyListeners();
    }
  }

  void recordSnapshot() {
    history.recordState(network);
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
    isDraggingEquipment = false;
    isDraggingCallout = false;
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
      if (!isModifyTool) {
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

    // Если чертим или выбран узел — строим подъем/опуск от базовой точки
    history.recordState(network);
    final dim = network.pipeCatalog.getDimension(activeDn);
    final outerD = dim?.outerDiameterMm;

    final newNode = Node3D(
      id: 'node_${_uuid.v4()}',
      x: baseNode.x,
      y: baseNode.y,
      z: targetElevationZ,
    );
    network.nodes[newNode.id] = newNode;

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

    traceStartNode = newNode;
    selectedNodeId = newNode.id;
    currentElevationZ = targetElevationZ;
    notifyListeners();
  }

  /// Обработка нажатия на холст
  void handlePointerDown(Offset screenPos) {
    currentCursorScreenPos = screenPos;

    // Обновляем привязку
    _updateSnap(screenPos);

    final hitNodeId = currentSnapResult?.type == SnapType.node
        ? currentSnapResult!.snappedNodeId
        : _findNodeAtScreenPos(screenPos);

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
          history.recordState(network);
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
            : (hitNodeId != null ? network.nodes[hitNodeId]! : projector.unproject(screenPos, currentElevationZ));
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
          history.recordState(network);
          network.addDimension(newDim);
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
        } else if (hitSegId != null) {
          history.recordState(network);
          // Начало ответвления от существующей трубы: делим сегмент в точке касания
          final double ratio;
          if (currentSnapResult != null &&
              (currentSnapResult!.type == SnapType.midpoint || currentSnapResult!.type == SnapType.perpendicular) &&
              currentSnapResult!.snappedSegmentId == hitSegId &&
              network.segments.containsKey(hitSegId)) {
            final seg = network.segments[hitSegId]!;
            final s = network.nodes[seg.startNodeId]!;
            final e = network.nodes[seg.endNodeId]!;
            final w = currentSnapResult!.worldPoint;
            final segLen = math.sqrt(math.pow(e.x - s.x, 2) + math.pow(e.y - s.y, 2) + math.pow(e.z - s.z, 2));
            ratio = segLen > 0.001
                ? (math.sqrt(math.pow(w.x - s.x, 2) + math.pow(w.y - s.y, 2) + math.pow(w.z - s.z, 2)) / segLen).clamp(0.01, 0.99)
                : 0.5;
          } else {
            ratio = _calcSegmentRatio(hitSegId, screenPos);
          }
          final midNode = network.splitSegmentAtRatio(hitSegId, ratio);
          if (midNode != null) {
            traceStartNode = midNode;
            selectedNodeId = midNode.id;
          }
        } else {
          history.recordState(network);
          // Начинаем трассировку из новой точки на текущей отметке Z
          final worldNode = _snapToGrid(projector.unproject(screenPos, currentElevationZ));
          final newNode = Node3D(
            id: 'node_${_uuid.v4()}',
            x: worldNode.x,
            y: worldNode.y,
            z: currentElevationZ,
          );
          network.nodes[newNode.id] = newNode;
          traceStartNode = newNode;
          selectedNodeId = newNode.id;
        }
        break;

      case CanvasTool.select:
        final hitCalloutId = _findCalloutAtScreenPos(screenPos);
        if (hitCalloutId != null) {
          selectedCalloutId = hitCalloutId;
          selectedNodeId = null;
          selectedSegmentId = null;
          selectedEquipmentId = null;
          selectedDimensionId = null;
          selectedAxisId = null;
          selectedNodeIds.clear();
          selectedSegmentIds.clear();
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
        selectedEquipmentId = _findEquipmentAtScreenPos(screenPos);

        if (hitNodeId != null) {
          final n = network.nodes[hitNodeId];
          if (n?.equipmentId != null) {
            selectedEquipmentId = n!.equipmentId;
            selectedEquipmentIds.add(n.equipmentId!);
          }
          selectedNodeId = hitNodeId;
          selectedAxisId = null;
          if (!selectedNodeIds.contains(hitNodeId)) {
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedNodeIds.add(hitNodeId);
          }
          isDraggingNode = true;
        } else if (hitSegId != null) {
          selectedSegmentId = hitSegId;
          selectedAxisId = null;
          if (!selectedSegmentIds.contains(hitSegId)) {
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedSegmentIds.add(hitSegId);
          }
        } else if (selectedEquipmentId != null) {
          isDraggingEquipment = true;
          selectedAxisId = null;
          if (!selectedEquipmentIds.contains(selectedEquipmentId)) {
            selectedNodeIds.clear();
            selectedSegmentIds.clear();
            selectedEquipmentIds.clear();
            selectedAxisIds.clear();
            selectedDimensionIds.clear();
            selectedEquipmentIds.add(selectedEquipmentId!);
          }
          final eq = network.equipments[selectedEquipmentId!];
          if (eq != null) {
            final unproj = projector.unproject(screenPos, eq.z);
            _dragEquipmentStartPos = Node3D(id: 'drag', x: unproj.x, y: unproj.y, z: eq.z);
          }
        } else {
          final hitDimId = _findDimensionAtScreenPos(screenPos);
          if (hitDimId != null) {
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
          } else {
            final hitAxisId = ((currentSnapResult?.type == SnapType.midpoint ||
                        currentSnapResult?.type == SnapType.perpendicular ||
                        currentSnapResult?.type == SnapType.gridAxis ||
                        currentSnapResult?.type == SnapType.endpoint) &&
                    network.axes.containsKey(currentSnapResult?.snappedSegmentId))
                ? currentSnapResult!.snappedSegmentId
                : _findAxisAtScreenPos(screenPos);
            if (hitAxisId != null) {
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
            } else {
              selectedAxisId = null;
              selectedNodeId = null;
              selectedSegmentId = null;
              selectedEquipmentId = null;
              selectedDimensionId = null;
              selectedNodeIds.clear();
              selectedSegmentIds.clear();
              selectedEquipmentIds.clear();
              selectedAxisIds.clear();
              selectedDimensionIds.clear();
              boxSelectStart = screenPos;
              selectionBoxRect = Rect.fromPoints(screenPos, screenPos);
            }
          }
        }
        break;

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
          duplicateSelection(dx: dx, dy: dy, dz: dz);
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
        final nozzleId = 'noz_${_uuid.v4()}';
        final nozzle = Nozzle(
          id: nozzleId,
          equipmentId: eqId,
          name: 'Ш-1',
          localX: 0,
          localY: 0,
          localZ: 2000,
          dirX: 0,
          dirY: 0,
          dirZ: 1,
          dn: 50,
        );
        final eq = Equipment(
          id: eqId,
          name: 'Емкость Е-1',
          type: EquipmentType.box,
          x: snapped.x,
          y: snapped.y,
          z: currentElevationZ,
          width: 1000,
          length: 1000,
          height: 2000,
          nozzles: [nozzle],
        );

        history.recordState(network);
        network.addEquipment(eq);
        selectedEquipmentId = eq.id;
        selectedNodeId = nozzleId;
        break;

      case CanvasTool.insertValve:
        if (hitSegId != null) {
          final seg = network.segments[hitSegId];
          if (seg != null) {
            history.recordState(network);
            final ratio = _calcSegmentRatio(hitSegId, screenPos);
            network.addValve(
              segmentId: hitSegId,
              ratio: ratio,
              valveType: selectedValveType,
              dn: seg.dn,
            );
          }
        }
        break;

      case CanvasTool.insertWeld:
        if (hitSegId != null) {
          history.recordState(network);
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.addWeldJoint(
            segmentId: hitSegId,
            ratio: ratio,
            stamp: currentWelderStamp,
            weldType: currentWeldType,
          );
        }
        break;

      case CanvasTool.insertReducer:
        if (hitSegId != null) {
          history.recordState(network);
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.insertReducer(
            segmentId: hitSegId,
            ratio: ratio,
            newDn: targetReducerDn,
            isEccentric: isEccentricReducer,
          );
        }
        break;

      case CanvasTool.insertFlange:
        if (hitSegId != null) {
          history.recordState(network);
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.insertFlange(
            segmentId: hitSegId,
            ratio: ratio,
            isPair: isFlangePair,
            pressurePn: flangePressurePn,
            material: activeMaterial,
          );
        }
        break;

      case CanvasTool.insertSupport:
        if (hitSegId != null) {
          history.recordState(network);
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
          network.addSupport(
            segmentId: hitSegId,
            distanceRatio: ratio,
            type: selectedSupportType,
          );
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

    if (boxSelectStart != null) {
      selectionBoxRect = Rect.fromPoints(boxSelectStart!, screenPos);
      isCrossingSelection = screenPos.dx < boxSelectStart!.dx;
      notifyListeners();
      return;
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

    notifyListeners();
  }

  void _updateSnap(Offset screenPos) {
    if (isSnapEnabled) {
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
        angleMode: angleSnapMode,
        customAngleStepDegrees: customAngleDegrees,
      );
    } else {
      currentSnapResult = SnapResult.none(screenPos, projector.unproject(screenPos, currentElevationZ));
    }
  }

  /// Обработка отпускания стилуса / пальца / кнопки мыши
  void handlePointerUp() {
    if (selectionBoxRect != null && boxSelectStart != null) {
      final rect = selectionBoxRect!;
      if (rect.width > 6.0 || rect.height > 6.0) {
        final isCrossing = isCrossingSelection;
        for (final node in network.nodes.values) {
          final p = projector.project(node);
          if (rect.contains(p)) {
            selectedNodeIds.add(node.id);
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
              selectedSegmentIds.add(seg.id);
              selectedNodeIds.add(n1.id);
              selectedNodeIds.add(n2.id);
            }
          } else {
            if (rect.contains(p1) && rect.contains(p2)) {
              selectedSegmentIds.add(seg.id);
              selectedNodeIds.add(n1.id);
              selectedNodeIds.add(n2.id);
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
              selectedEquipmentIds.add(eq.id);
            }
          } else {
            if (rect.contains(eqBounds.topLeft) && rect.contains(eqBounds.bottomRight)) {
              selectedEquipmentIds.add(eq.id);
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
            selectedAxisIds.add(axis.id);
          }
        }

        // Выбор линейных размеров
        for (final dim in network.dimensions.values) {
          final p1 = projector.project(dim.startPoint);
          final p2 = projector.project(dim.endPoint);
          if (isCrossing) {
            if (rect.contains(p1) || rect.contains(p2) || _segmentIntersectsRect(p1, p2, rect)) {
              selectedDimensionIds.add(dim.id);
            }
          } else {
            if (rect.contains(p1) && rect.contains(p2)) {
              selectedDimensionIds.add(dim.id);
            }
          }
        }

        if (selectedNodeIds.isNotEmpty) {
          selectedNodeId = selectedNodeIds.first;
        }
        if (selectedSegmentIds.isNotEmpty && selectedNodeId == null) {
          selectedSegmentId = selectedSegmentIds.first;
        }
        if (selectedEquipmentIds.isNotEmpty && selectedNodeId == null && selectedSegmentId == null) {
          selectedEquipmentId = selectedEquipmentIds.first;
        }
        if (selectedAxisIds.isNotEmpty && selectedNodeId == null && selectedSegmentId == null && selectedEquipmentId == null) {
          selectedAxisId = selectedAxisIds.first;
        }
        if (selectedDimensionIds.isNotEmpty && selectedNodeId == null && selectedSegmentId == null && selectedEquipmentId == null && selectedAxisId == null) {
          selectedDimensionId = selectedDimensionIds.first;
        }
      }
      boxSelectStart = null;
      selectionBoxRect = null;
      notifyListeners();
      return;
    }

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
      } else if ((currentSnapResult!.type == SnapType.segmentAxis ||
                  currentSnapResult!.type == SnapType.midpoint ||
                  currentSnapResult!.type == SnapType.perpendicular) &&
                 currentSnapResult!.snappedSegmentId != null &&
                 network.segments.containsKey(currentSnapResult!.snappedSegmentId)) {
        final segId = currentSnapResult!.snappedSegmentId!;
        final seg = network.segments[segId]!;
        final s = network.nodes[seg.startNodeId]!;
        final e = network.nodes[seg.endNodeId]!;
        final w = currentSnapResult!.worldPoint;
        final segLen = math.sqrt(math.pow(e.x - s.x, 2) + math.pow(e.y - s.y, 2) + math.pow(e.z - s.z, 2));
        final ratio = segLen > 0.001
            ? (math.sqrt(math.pow(w.x - s.x, 2) + math.pow(w.y - s.y, 2) + math.pow(w.z - s.z, 2)) / segLen).clamp(0.01, 0.99)
            : 0.5;
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

      if (hitExistingNodeId != null && hitExistingNodeId != traceStartNode!.id) {
        targetNodeId = hitExistingNodeId;
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
    double dirX = 1.0;
    double dirY = 0.0;
    double dirZ = 0.0;

    if (isSnapEnabled && currentSnapResult != null && currentSnapResult!.type != SnapType.none) {
      final snapWorld = currentSnapResult!.worldPoint;
      final dx = snapWorld.x - startNode.x;
      final dy = snapWorld.y - startNode.y;
      final dz = snapWorld.z - startNode.z;
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (dist > 1e-6) {
        dirX = dx / dist;
        dirY = dy / dist;
        dirZ = dz / dist;
      }
    } else if (currentCursorScreenPos != null) {
      final rawWorld = projector.unproject(currentCursorScreenPos!, currentElevationZ);
      final rawDx = rawWorld.x - startNode.x;
      final rawDy = rawWorld.y - startNode.y;
      final rawDz = rawWorld.z - startNode.z;

      if (angleSnapMode == AngleSnapMode.ortho90) {
        if (rawDx.abs() >= rawDy.abs()) {
          dirX = rawDx >= 0 ? 1.0 : -1.0;
          dirY = 0.0;
          dirZ = 0.0;
        } else {
          dirX = 0.0;
          dirY = rawDy >= 0 ? 1.0 : -1.0;
          dirZ = 0.0;
        }
      } else {
        final dist = math.sqrt(rawDx * rawDx + rawDy * rawDy + rawDz * rawDz);
        if (dist > 1e-6) {
          dirX = rawDx / dist;
          dirY = rawDy / dist;
          dirZ = rawDz / dist;
        }
      }
    }

    return (dirX: dirX, dirY: dirY, dirZ: dirZ);
  }

  /// Фиксация конца трассировки трубы или строительной оси на заданном расстоянии (Direct Distance Entry / Touch UI)
  void commitTraceWithLength(double lengthMm, {double? dirX, double? dirY, double? dirZ}) {
    if (lengthMm <= 0 || lengthMm.isNaN || lengthMm.isInfinite) return;

    if (currentTool == CanvasTool.trace && traceStartNode != null) {
      final startNode = traceStartNode!;
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

      final endX = double.parse((startNode.x + dir.dirX * lengthMm).toStringAsFixed(2));
      final endY = double.parse((startNode.y + dir.dirY * lengthMm).toStringAsFixed(2));
      final endZ = double.parse((startNode.z + dir.dirZ * lengthMm).toStringAsFixed(2));

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

      final endX = double.parse((startNode.x + dir.dirX * lengthMm).toStringAsFixed(2));
      final endY = double.parse((startNode.y + dir.dirY * lengthMm).toStringAsFixed(2));

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
      }

      if (currentCursorScreenPos != null) {
        _updateSnap(currentCursorScreenPos!);
      }
      notifyListeners();
    }
  }


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

  /// Поиск оборудования под курсором
  String? _findEquipmentAtScreenPos(Offset screenPos) {
    for (final eq in network.equipments.values) {
      final x1 = eq.x - eq.width / 2;
      final x2 = eq.x + eq.width / 2;
      final y1 = eq.y - eq.length / 2;
      final y2 = eq.y + eq.length / 2;
      final z1 = eq.z;
      final z2 = eq.z + eq.height;

      final pts = [
        projector.projectCoordinates(x1, y1, z1),
        projector.projectCoordinates(x2, y1, z1),
        projector.projectCoordinates(x2, y2, z1),
        projector.projectCoordinates(x1, y2, z1),
        projector.projectCoordinates(x1, y1, z2),
        projector.projectCoordinates(x2, y1, z2),
        projector.projectCoordinates(x2, y2, z2),
        projector.projectCoordinates(x1, y2, z2),
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
      network.autoDetectAllFittings();
      network.recalculateSpools();
      notifyListeners();
      return;
    }

    final selectedNode = selectedNodeId != null ? network.nodes[selectedNodeId] : null;
    final eqToDelete = selectedEquipmentId ?? selectedNode?.equipmentId;
    if (eqToDelete != null && (selectedSegmentId == null || selectedEquipmentId != null || selectedNode?.equipmentId != null)) {
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
      final segsToRemove = network.segments.values
          .where((s) => s.startNodeId == nodeId || s.endNodeId == nodeId)
          .map((s) => s.id)
          .toList();

      for (final segId in segsToRemove) {
        network.segments.remove(segId);
        network.valves.removeWhere((_, v) => v.segmentId == segId);
        network.weldJoints.removeWhere((_, w) => w.segmentId == segId);
        network.supports.removeWhere((_, s) => s.segmentId == segId);
        network.callouts.removeWhere((_, c) => c.targetId == segId);
      }
      network.fittings.remove(nodeId);
      network.nodes.remove(nodeId);
      network.callouts.removeWhere((_, c) => c.targetId == nodeId);

      selectedNodeIds.remove(nodeId);
      selectedNodeId = null;
      selectedSegmentId = null;
      network.recalculateSpools();
      history.recordState(network);
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
  bool duplicateSelection({double dx = 500.0, double dy = 500.0, double dz = 0.0}) {
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

    history.recordState(network);

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

  bool _segmentIntersectsRect(Offset p1, Offset p2, Rect rect) {
    if (rect.contains(p1) || rect.contains(p2)) return true;
    final rLeft = rect.left, rRight = rect.right, rTop = rect.top, rBottom = rect.bottom;
    return _linesIntersect(p1, p2, Offset(rLeft, rTop), Offset(rRight, rTop)) ||
        _linesIntersect(p1, p2, Offset(rRight, rTop), Offset(rRight, rBottom)) ||
        _linesIntersect(p1, p2, Offset(rRight, rBottom), Offset(rLeft, rBottom)) ||
        _linesIntersect(p1, p2, Offset(rLeft, rBottom), Offset(rLeft, rTop));
  }

  bool _linesIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
    double ccw(Offset a, Offset b, Offset c) =>
        (c.dy - a.dy) * (b.dx - a.dx) - (b.dy - a.dy) * (c.dx - a.dx);
    return (ccw(a1, b1, b2) * ccw(a2, b1, b2) <= 0) &&
        (ccw(a1, a2, b1) * ccw(a1, a2, b2) <= 0);
  }

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

  /// Генерация недостающих выносок для сегментов, арматуры и стыков
  int generateMissingCallouts({double offsetX = 50.0, double offsetY = -50.0}) {
    final count = network.generateMissingCallouts(offsetX: offsetX, offsetY: offsetY);
    if (count > 0) {
      history.recordState(network);
      notifyListeners();
    }
    return count;
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

  /// Обновление пользовательского текста выноски
  void updateCalloutCustomText(String id, String customText) {
    final callout = network.callouts[id];
    if (callout == null) return;
    network.callouts[id] = callout.copyWith(customText: customText);
    history.recordState(network);
    notifyListeners();
  }

  /// Получение итогового текста выноски для отображения
  String getCalloutText(Callout callout) {
    return network.generateCalloutText(callout, currentProject.calloutTemplates);
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

  Future<void> saveProject() async {
    isSaving = true;
    notifyListeners();
    try {
      currentProject = currentProject.copyWith(network: network);
      await projectRepository.saveProject(currentProject);
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<void> loadProject() async {
    isLoading = true;
    notifyListeners();
    try {
      final proj = await projectRepository.loadProject();
      if (proj != null) {
        currentProject = proj;
        network = proj.network;
        // Обязательно обновить историю и уведомить слушателей
        history.recordState(network);
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
