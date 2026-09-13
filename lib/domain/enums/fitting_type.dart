/// Типы соединительных деталей трубопроводов (фитингов)
enum FittingType {
  /// Отвод 90° (крутоизогнутый R=1.5DN или гнутый)
  elbow90,

  /// Отвод 45°
  elbow45,

  /// Тройник (равнопроходный или переходный)
  tee,

  /// Крестовина
  cross,

  /// Переход концентрический (сужение/расширение по центральной оси)
  reducerConcentric,

  /// Переход эксцентрический (по нижней образующей для предотвращения скопления воздуха/осадка)
  reducerEccentric,

  /// Фланец (стальной воротниковый по ГОСТ 33259 или плоский)
  flange,

  /// Заглушка (эллиптическая или фланцевая глухая)
  cap,

  /// Прямая врезка (труба в трубу без тройника, шов У18 по ГОСТ 16037)
  directBranch,
}

extension FittingTypeExt on FittingType {
  String get displayName {
    switch (this) {
      case FittingType.elbow90:
        return 'Отвод 90°';
      case FittingType.elbow45:
        return 'Отвод 45°';
      case FittingType.tee:
        return 'Тройник';
      case FittingType.cross:
        return 'Крестовина';
      case FittingType.reducerConcentric:
        return 'Переход концентрический';
      case FittingType.reducerEccentric:
        return 'Переход эксцентрический';
      case FittingType.flange:
        return 'Фланец';
      case FittingType.cap:
        return 'Заглушка (Днище)';
      case FittingType.directBranch:
        return 'Прямая врезка (У18)';
    }
  }

  /// Стандартный радиус гиба или длина для расчета строительной длины
  double defaultDeductionMm(int dn) {
    switch (this) {
      case FittingType.elbow90:
        return dn * 1.5; // Крутоизогнутый отвод по ГОСТ 17375
      case FittingType.elbow45:
        return dn * 0.625;
      case FittingType.tee:
        return dn * 1.0;
      case FittingType.cross:
        return dn * 1.0;
      case FittingType.reducerConcentric:
      case FittingType.reducerEccentric:
        return dn * 1.5;
      case FittingType.flange:
        return dn <= 50 ? 35.0 : 45.0;
      case FittingType.cap:
        return dn * 0.5;
      case FittingType.directBranch:
        return 0.0; // Прямая врезка не имеет строительного вычета из магистрали
    }
  }
}

/// Исполнение / режим фланцевого соединения
enum FlangeConnectionType {
  /// К оборудованию или арматуре с заводским фланцем (1 ответный фланец на трубе, 1 сварной стык)
  toEquipment,

  /// Межтрубное соединение (2 ответных фланца, 2 сварных стыка к трубам, прокладка)
  pipeToPipe,

  /// Фланцевая заглушка (1 фланец на трубе со стыком + глухой фланец на болтах)
  blindFlange,

  /// Одиночный фланец под приварку (1 стык)
  singleFlange,
}

extension FlangeConnectionTypeExt on FlangeConnectionType {
  String get displayName {
    switch (this) {
      case FlangeConnectionType.toEquipment:
        return 'К оборудованию (1 стык)';
      case FlangeConnectionType.pipeToPipe:
        return 'Межтрубное (2 стыка)';
      case FlangeConnectionType.blindFlange:
        return 'Фланцевая заглушка (1 стык)';
      case FlangeConnectionType.singleFlange:
        return 'Одиночный фланец (1 стык)';
    }
  }

  int get defaultWeldCount {
    switch (this) {
      case FlangeConnectionType.toEquipment:
      case FlangeConnectionType.blindFlange:
      case FlangeConnectionType.singleFlange:
        return 1;
      case FlangeConnectionType.pipeToPipe:
        return 2;
    }
  }
}
