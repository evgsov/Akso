import 'dart:math' as math;
import '../../core/math/axonometry_projector.dart';

/// Тип представления выносок при экспорте в AutoCAD
enum DxfCalloutType {
  /// Монолитный блок: полочка и текст сгруппированы в единый блок.
  /// Ручка находится в точке излома (начало полочки). Полочка не отрывается от текста.
  /// 100% совместимость со всеми CAD-системами (AutoCAD, nanoCAD, ZWCAD, Компас).
  monolithicBlock,

  /// Нативная размерная выноска AutoCAD (сущности LEADER + MTEXT).
  /// Динамическое растяжение ножки за текстом в AutoCAD.
  nativeLeader,

  /// Нативная мультивыноска AutoCAD (MLEADER через скрипт-команду .scr).
  /// Создает 100% настоящие AcDbMLeader с тремя интерактивными ручками.
  mleaderScript,
}

extension DxfCalloutTypeExt on DxfCalloutType {
  String get displayName {
    switch (this) {
      case DxfCalloutType.monolithicBlock:
        return 'Монолитный блок (Полочка + Текст)';
      case DxfCalloutType.nativeLeader:
        return 'Размерная выноска (LEADER + MTEXT)';
      case DxfCalloutType.mleaderScript:
        return 'Нативная МВЫНОСКА (MLEADER через .scr)';
    }
  }

  String get description {
    switch (this) {
      case DxfCalloutType.monolithicBlock:
        return 'Полочка и текст двигаются строго вместе. Ручка в месте излома. Универсальная совместимость со всеми CAD-системами.';
      case DxfCalloutType.nativeLeader:
        return 'Родной объект AutoCAD LEADER. Стрелка и ножка тянутся за текстом при перемещении.';
      case DxfCalloutType.mleaderScript:
        return 'Генерирует DXF + скрипт .scr. При перетаскивании скрипта в AutoCAD создаются истинные современные МВЫНОСКИ с 3 ручками.';
    }
  }
}

/// Пространственная 3D-ориентация выносок («ракурс с какой стороны»)
enum DxfCalloutOrientation {
  /// Автоматически разворачивать лицом к активному ракурсу 3D-орбиты камеры Akso
  cameraFacing,

  /// Юго-Западная изометрия (спереди-слева, классический SW Iso в AutoCAD)
  isoSouthWest,

  /// Юго-Восточная изометрия (спереди-справа, стандартная ГОСТ 21.602 / SE Iso)
  isoSouthEast,

  /// Северо-Восточная изометрия (сзади-справа, NE Iso)
  isoNorthEast,

  /// Северо-Западная изометрия (сзади-слева, NW Iso)
  isoNorthWest,

  /// Вид спереди (фасад XZ, вертикально)
  viewFront,

  /// Вид сбоку (фасад YZ, вертикально)
  viewSide,

  /// Вид сверху (план XY, горизонтально «на полу»)
  horizontalTop,
}

extension DxfCalloutOrientationExt on DxfCalloutOrientation {
  String get displayName {
    switch (this) {
      case DxfCalloutOrientation.cameraFacing:
        return 'По текущей камере (активный ракурс)';
      case DxfCalloutOrientation.isoSouthWest:
        return 'Юго-Запад (спереди-слева, AutoCAD SW)';
      case DxfCalloutOrientation.isoSouthEast:
        return 'Юго-Восток (спереди-справа, ГОСТ SE)';
      case DxfCalloutOrientation.isoNorthEast:
        return 'Северо-Восток (сзади-справа, NE)';
      case DxfCalloutOrientation.isoNorthWest:
        return 'Северо-Запад (сзади-слева, NW)';
      case DxfCalloutOrientation.viewFront:
        return 'Вид спереди (фасад XZ, вертикально)';
      case DxfCalloutOrientation.viewSide:
        return 'Вид сбоку (фасад YZ, вертикально)';
      case DxfCalloutOrientation.horizontalTop:
        return 'Вид сверху (план XY, горизонтально)';
    }
  }

  /// Вычисление 3D вектора нормали выдавливания (Extrusion Vector) для AutoCAD
  ({double nx, double ny, double nz}) getExtrusionVector([AxonometryProjector? projector]) {
    const invSqrt2 = 0.7071067811865475;

    switch (this) {
      case DxfCalloutOrientation.cameraFacing:
        final azimuth = projector?.orbitAzimuth ?? (-math.pi / 4);
        // Нормаль в плоскости XY навстречу взгляду камеры
        final nx = -math.sin(azimuth);
        final ny = -math.cos(azimuth);
        return (nx: nx, ny: ny, nz: 0.0);

      case DxfCalloutOrientation.isoSouthWest:
        return (nx: -invSqrt2, ny: -invSqrt2, nz: 0.0);

      case DxfCalloutOrientation.isoSouthEast:
        return (nx: invSqrt2, ny: -invSqrt2, nz: 0.0);

      case DxfCalloutOrientation.isoNorthEast:
        return (nx: invSqrt2, ny: invSqrt2, nz: 0.0);

      case DxfCalloutOrientation.isoNorthWest:
        return (nx: -invSqrt2, ny: invSqrt2, nz: 0.0);

      case DxfCalloutOrientation.viewFront:
        return (nx: 0.0, ny: -1.0, nz: 0.0);

      case DxfCalloutOrientation.viewSide:
        return (nx: 1.0, ny: 0.0, nz: 0.0);

      case DxfCalloutOrientation.horizontalTop:
        return (nx: 0.0, ny: 0.0, nz: 1.0);
    }
  }
}
