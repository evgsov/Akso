import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/math/axonometry_projector.dart';
import '../../core/math/snap_engine.dart';
import '../../domain/enums/projection_type.dart';
import '../../domain/enums/valve_type.dart';
import '../../domain/enums/weld_type.dart';
import '../../domain/models/construction_axis.dart';
import '../../domain/models/network_history_manager.dart';
import '../../domain/models/node_3d.dart';
import '../../domain/models/pipe_dimension.dart';
import '../../domain/models/pipe_segment.dart';
import '../../domain/models/piping_network.dart';
import '../../domain/models/project_model.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/recovery_repository.dart';

const _uuid = Uuid();

enum CanvasTool {
  trace, // Черчение труб
  select, // Выбор и перемещение узлов/стояков
  insertValve, // Врезка арматуры
  insertReducer, // Врезка перехода диаметров
  insertWeld, // Врезка сварного стыка
  insertFlange, // Врезка фланцев
  drawAxis, // Черчение строительных осей
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

  String activeSystemId = 'sys_b1';
  int activeDn = 25;
  double activeWallThicknessMm = 3.2;
  double currentElevationZ = 0.0; // Текущая рабочая отметка в мм

  // Режим компоновки UI
  UiLayoutMode layoutMode = UiLayoutMode.auto;

  bool isSaving = false;
  bool isLoading = false;

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
  String? hoveredNodeId;

  Node3D? traceStartNode;
  Node3D? axisStartNode;
  String currentAxisLabel = '1';
  Offset? currentCursorScreenPos;

  // Режим перетаскивания
  bool isDraggingNode = false;

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

  /// Отмена текущей операции (по клавише Esc, ПКМ или кнопке на экране)
  void cancelCurrentOperation({bool keepTool = false}) {
    traceStartNode = null;
    axisStartNode = null;
    currentCursorScreenPos = null;
    currentSnapResult = null;
    selectedNodeId = null;
    selectedSegmentId = null;
    isDraggingNode = false;
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
      cancelCurrentOperation(keepTool: true);
      currentTool = tool;
      notifyListeners();
    }
  }

  void setSelectedValveType(ValveType type) {
    selectedValveType = type;
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

  bool get useDirectBranch => network.catalog.defaultBranchId == 'branch_direct_u18';
  set useDirectBranch(bool val) {
    network.catalog.defaultBranchId = val ? 'branch_direct_u18' : 'branch_tee_gost17376';
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

  void refresh() {
    notifyListeners();
  }

  /// Смена типа проекции (ГОСТ 45°, ISO 30°, Орбита 3D)
  void setProjectionType(ProjectionType type) {
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

    final hitSegId = currentSnapResult?.type == SnapType.segmentAxis
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
            label: currentAxisLabel,
            startPoint: axisStartNode!,
            endPoint: axisEndNode,
            isBuildingGrid: true,
          );

          // Инкремент марки, если это число
          final num = int.tryParse(currentAxisLabel);
          if (num != null) {
            currentAxisLabel = '${num + 1}';
          }
          axisStartNode = null;
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
          final ratio = _calcSegmentRatio(hitSegId, screenPos);
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
        selectedNodeId = hitNodeId;
        selectedSegmentId = hitSegId;
        if (hitNodeId != null) {
          isDraggingNode = true;
        }
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

    if (isDraggingNode && selectedNodeId != null) {
      final unproj = projector.unproject(screenPos, currentElevationZ);
      final snapped = _snapToGrid(unproj);
      network.moveNode(selectedNodeId!, snapped.x, snapped.y, snapped.z);
      notifyListeners();
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
        traceStartNode: traceStartNode ?? axisStartNode,
        angleMode: angleSnapMode,
        customAngleStepDegrees: customAngleDegrees,
      );
    } else {
      currentSnapResult = SnapResult.none(screenPos, projector.unproject(screenPos, currentElevationZ));
    }
  }

  /// Обработка отпускания стилуса / пальца / кнопки мыши
  void handlePointerUp() {
    if (isDraggingNode) {
      history.recordState(network);
      isDraggingNode = false;
      notifyListeners();
      return;
    }
    isDraggingNode = false;

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
            label: currentAxisLabel,
            startPoint: axisStartNode!,
            endPoint: axisEndNode,
            isBuildingGrid: true,
          );
          final num = int.tryParse(currentAxisLabel);
          if (num != null) {
            currentAxisLabel = '${num + 1}';
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
      } else if (currentSnapResult!.type == SnapType.segmentAxis && currentSnapResult!.snappedSegmentId != null) {
        final ratio = _calcSegmentRatio(currentSnapResult!.snappedSegmentId!, endScreenPos);
        final midNode = network.splitSegmentAtRatio(currentSnapResult!.snappedSegmentId!, ratio);
        targetNodeId = midNode?.id ??
            (() {
              final w = currentSnapResult!.worldPoint;
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

  /// Фиксация конца трассировки трубы или строительной оси на заданном расстоянии (Direct Distance Entry)
  void commitTraceWithLength(double lengthMm) {
    if (lengthMm <= 0 || lengthMm.isNaN || lengthMm.isInfinite) return;

    if (currentTool == CanvasTool.trace && traceStartNode != null) {
      final startNode = traceStartNode!;
      final dir = _computeTraceDirection(startNode);

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
      final dir = _computeTraceDirection(startNode);

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
        label: currentAxisLabel,
        startPoint: axisStartNode!,
        endPoint: axisEndNode,
        isBuildingGrid: true,
      );

      final num = int.tryParse(currentAxisLabel);
      if (num != null) {
        currentAxisLabel = '${num + 1}';
      }
      axisStartNode = null;
      history.recordState(network);

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

  /// Удаление выбранного узла или сегмента с каскадной очисткой связей
  void deleteSelected() {
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
      }
      network.fittings.remove(nodeId);
      network.nodes.remove(nodeId);

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

      if (startNodeId != null && network.getConnectedSegments(startNodeId).isEmpty) {
        network.fittings.remove(startNodeId);
      }
      if (endNodeId != null && network.getConnectedSegments(endNodeId).isEmpty) {
        network.fittings.remove(endNodeId);
      }

      selectedSegmentId = null;
      network.recalculateSpools();
      history.recordState(network);
      notifyListeners();
    }
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
