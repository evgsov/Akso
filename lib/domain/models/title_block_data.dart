/// Формы основной надписи по ГОСТ 21.101-2020
enum TitleBlockForm {
  /// Форма 3 — для листов основных комплектов рабочих чертежей (185 x 55 мм)
  form3,

  /// Форма 4 — для чертежей строительных изделий (последующие листы, 185 x 15 мм)
  form4,

  /// Форма 5 — для текстовых проектных документов и спецификаций (185 x 40 мм)
  form5,
}

/// Режим отображения блока в правом верхнем углу листа
enum TopRightCornerMode {
  /// Приложение к акту (АОСР, гидроиспытания, ВИК, паспорт)
  actAttachment,

  /// Повернутое на 180° обозначение документа (Графа 26 ГОСТ 21.101)
  documentCodeRotated,

  /// Произвольный многострочный текст
  customText,

  /// Пусто (отключено)
  none,
}

/// Блок в правом верхнем углу чертежа (приложение к акту или графа 26)
class TopRightCornerBlock {
  final TopRightCornerMode mode;
  final String text;
  final String actNumber;
  final String actDate;
  final String actType;
  final double? xMm;
  final double? yMm;
  final double widthMm;
  final double heightMm;
  final bool hasBorder;

  const TopRightCornerBlock({
    this.mode = TopRightCornerMode.actAttachment,
    this.text = 'Приложение к акту №{act_number}\nот {act_date} г.',
    this.actNumber = '',
    this.actDate = '',
    this.actType = 'АОСР',
    this.xMm,
    this.yMm,
    this.widthMm = 80.0,
    this.heightMm = 14.0,
    this.hasBorder = true,
  });

  /// Формирование итоговой строки для вывода на лист
  String get formattedText {
    switch (mode) {
      case TopRightCornerMode.actAttachment:
        if (text.isNotEmpty && (actNumber.isNotEmpty || actDate.isNotEmpty)) {
          var res = text;
          if (actNumber.isNotEmpty) {
            res = res.replaceAll('№__', '№$actNumber').replaceAll('{act_number}', actNumber);
          }
          if (actDate.isNotEmpty) {
            res = res.replaceAll('{act_date}', actDate);
          }
          return res;
        }
        return text;
      case TopRightCornerMode.documentCodeRotated:
        return '';
      case TopRightCornerMode.customText:
        return text;
      case TopRightCornerMode.none:
        return '';
    }
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'text': text,
        'actNumber': actNumber,
        'actDate': actDate,
        'actType': actType,
        if (xMm != null) 'xMm': xMm,
        if (yMm != null) 'yMm': yMm,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'hasBorder': hasBorder,
      };

  factory TopRightCornerBlock.fromJson(Map<String, dynamic> json) => TopRightCornerBlock(
        mode: TopRightCornerMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => TopRightCornerMode.actAttachment,
        ),
        text: json['text'] as String? ?? 'Приложение к акту №{act_number}\nот {act_date} г.',
        actNumber: json['actNumber'] as String? ?? '',
        actDate: json['actDate'] as String? ?? '',
        actType: json['actType'] as String? ?? 'АОСР',
        xMm: (json['xMm'] as num?)?.toDouble(),
        yMm: (json['yMm'] as num?)?.toDouble(),
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 80.0,
        heightMm: (json['heightMm'] as num?)?.toDouble() ?? 14.0,
        hasBorder: json['hasBorder'] as bool? ?? true,
      );

  TopRightCornerBlock copyWith({
    TopRightCornerMode? mode,
    String? text,
    String? actNumber,
    String? actDate,
    String? actType,
    double? xMm,
    double? yMm,
    double? widthMm,
    double? heightMm,
    bool? hasBorder,
  }) {
    return TopRightCornerBlock(
      mode: mode ?? this.mode,
      text: text ?? this.text,
      actNumber: actNumber ?? this.actNumber,
      actDate: actDate ?? this.actDate,
      actType: actType ?? this.actType,
      xMm: xMm ?? this.xMm,
      yMm: yMm ?? this.yMm,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      hasBorder: hasBorder ?? this.hasBorder,
    );
  }
}

/// Строка согласования в штампе (Разработал, Проверил, ГИП...)
class TitleBlockApproval {
  final String role;
  final String name;
  final String date;

  const TitleBlockApproval({
    required this.role,
    required this.name,
    this.date = '',
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'name': name,
        'date': date,
      };

  factory TitleBlockApproval.fromJson(Map<String, dynamic> json) => TitleBlockApproval(
        role: json['role'] as String? ?? '',
        name: json['name'] as String? ?? '',
        date: json['date'] as String? ?? '',
      );

  TitleBlockApproval copyWith({String? role, String? name, String? date}) {
    return TitleBlockApproval(
      role: role ?? this.role,
      name: name ?? this.name,
      date: date ?? this.date,
    );
  }
}

/// Строка таблицы регистрации изменений над штампом
class TitleBlockRevision {
  final String changeIndex;
  final String changeCount;
  final String sheetNum;
  final String docNum;
  final String signature;
  final String date;

  const TitleBlockRevision({
    this.changeIndex = '1',
    this.changeCount = '1',
    this.sheetNum = '1',
    this.docNum = '',
    this.signature = '',
    this.date = '',
  });

  Map<String, dynamic> toJson() => {
        'changeIndex': changeIndex,
        'changeCount': changeCount,
        'sheetNum': sheetNum,
        'docNum': docNum,
        'signature': signature,
        'date': date,
      };

  factory TitleBlockRevision.fromJson(Map<String, dynamic> json) => TitleBlockRevision(
        changeIndex: json['changeIndex'] as String? ?? '1',
        changeCount: json['changeCount'] as String? ?? '1',
        sheetNum: json['sheetNum'] as String? ?? '1',
        docNum: json['docNum'] as String? ?? '',
        signature: json['signature'] as String? ?? '',
        date: json['date'] as String? ?? '',
      );
}

/// Архивные графы в левом поле подшивки (Графы 19-23 ГОСТ 21.101)
class TitleBlockArchive {
  final String invNumberPrimary;
  final String invDatePrimary;
  final String invNumberReplaced;
  final String invNumberDuplicate;
  final String invDateDuplicate;

  const TitleBlockArchive({
    this.invNumberPrimary = '',
    this.invDatePrimary = '',
    this.invNumberReplaced = '',
    this.invNumberDuplicate = '',
    this.invDateDuplicate = '',
  });

  Map<String, dynamic> toJson() => {
        'invNumberPrimary': invNumberPrimary,
        'invDatePrimary': invDatePrimary,
        'invNumberReplaced': invNumberReplaced,
        'invNumberDuplicate': invNumberDuplicate,
        'invDateDuplicate': invDateDuplicate,
      };

  factory TitleBlockArchive.fromJson(Map<String, dynamic> json) => TitleBlockArchive(
        invNumberPrimary: json['invNumberPrimary'] as String? ?? '',
        invDatePrimary: json['invDatePrimary'] as String? ?? '',
        invNumberReplaced: json['invNumberReplaced'] as String? ?? '',
        invNumberDuplicate: json['invNumberDuplicate'] as String? ?? '',
        invDateDuplicate: json['invDateDuplicate'] as String? ?? '',
      );

  TitleBlockArchive copyWith({
    String? invNumberPrimary,
    String? invDatePrimary,
    String? invNumberReplaced,
    String? invNumberDuplicate,
    String? invDateDuplicate,
  }) {
    return TitleBlockArchive(
      invNumberPrimary: invNumberPrimary ?? this.invNumberPrimary,
      invDatePrimary: invDatePrimary ?? this.invDatePrimary,
      invNumberReplaced: invNumberReplaced ?? this.invNumberReplaced,
      invNumberDuplicate: invNumberDuplicate ?? this.invNumberDuplicate,
      invDateDuplicate: invDateDuplicate ?? this.invDateDuplicate,
    );
  }
}

/// Полный набор атрибутов основной надписи (штампа) по ГОСТ 21.101-2020
class TitleBlockData {
  /// Графа 1: Наименование предприятия / объекта строительства
  final String projectName;

  /// Графа 2: Наименование здания / сооружения
  final String buildingName;

  /// Графа 3: Наименование схемы / чертежа
  final String drawingTitle;

  /// Графа 4: Обозначение документа (шифр проекта)
  final String documentCode;

  /// Графа 5: Наименование организации-разработчика / монтажной организации
  final String organization;

  /// Графа 6: Стадия проектирования (И — исполнительная, Р — рабочая, П — проектная)
  final String stage;

  /// Графа 7: Номер листа
  final int sheetNumber;

  /// Графа 8: Всего листов
  final int totalSheets;

  /// Графа 9: Масштаб схемы (напр. "—", "М 1:50", "М 1:100")
  final String scaleText;

  /// Графы 10-13: Таблица лиц, согласующих документ
  final List<TitleBlockApproval> approvals;

  /// Графы 19-23: Поле подшивки архива
  final TitleBlockArchive archive;

  /// Правый верхний угол (приложение к акту или повернутый шифр)
  final TopRightCornerBlock topRightCorner;

  /// Таблица регистрации изменений над штампом
  final List<TitleBlockRevision> revisions;

  const TitleBlockData({
    this.projectName = '',
    this.buildingName = '',
    this.drawingTitle = 'Исполнительная схема трубопроводов',
    this.documentCode = '',
    this.organization = '',
    this.stage = 'И',
    this.sheetNumber = 1,
    this.totalSheets = 1,
    this.scaleText = '—',
    this.approvals = const [
      TitleBlockApproval(role: 'Разраб.', name: ''),
      TitleBlockApproval(role: 'Пров.', name: ''),
      TitleBlockApproval(role: 'Гидрогеол.', name: ''),
      TitleBlockApproval(role: 'ГИП', name: ''),
      TitleBlockApproval(role: 'Н.контр.', name: ''),
      TitleBlockApproval(role: 'Утв.', name: ''),
    ],
    this.archive = const TitleBlockArchive(),
    this.topRightCorner = const TopRightCornerBlock(),
    this.revisions = const [],
  });

  Map<String, dynamic> toJson() => {
        'projectName': projectName,
        'buildingName': buildingName,
        'drawingTitle': drawingTitle,
        'documentCode': documentCode,
        'organization': organization,
        'stage': stage,
        'sheetNumber': sheetNumber,
        'totalSheets': totalSheets,
        'scaleText': scaleText,
        'approvals': approvals.map((a) => a.toJson()).toList(),
        'archive': archive.toJson(),
        'topRightCorner': topRightCorner.toJson(),
        'revisions': revisions.map((r) => r.toJson()).toList(),
      };

  factory TitleBlockData.fromJson(Map<String, dynamic> json) => TitleBlockData(
        projectName: json['projectName'] as String? ?? '',
        buildingName: json['buildingName'] as String? ?? '',
        drawingTitle: json['drawingTitle'] as String? ?? 'Исполнительная схема трубопроводов',
        documentCode: json['documentCode'] as String? ?? '',
        organization: json['organization'] as String? ?? '',
        stage: json['stage'] as String? ?? 'И',
        sheetNumber: json['sheetNumber'] as int? ?? 1,
        totalSheets: json['totalSheets'] as int? ?? 1,
        scaleText: json['scaleText'] as String? ?? '—',
        approvals: json['approvals'] is List
            ? (json['approvals'] as List)
                .map((e) => TitleBlockApproval.fromJson(e as Map<String, dynamic>))
                .toList()
            : const [],
        archive: json['archive'] != null
            ? TitleBlockArchive.fromJson(json['archive'] as Map<String, dynamic>)
            : const TitleBlockArchive(),
        topRightCorner: json['topRightCorner'] != null
            ? TopRightCornerBlock.fromJson(json['topRightCorner'] as Map<String, dynamic>)
            : const TopRightCornerBlock(),
        revisions: json['revisions'] is List
            ? (json['revisions'] as List)
                .map((e) => TitleBlockRevision.fromJson(e as Map<String, dynamic>))
                .toList()
            : const [],
      );

  TitleBlockData copyWith({
    String? projectName,
    String? buildingName,
    String? drawingTitle,
    String? documentCode,
    String? organization,
    String? stage,
    int? sheetNumber,
    int? totalSheets,
    String? scaleText,
    List<TitleBlockApproval>? approvals,
    TitleBlockArchive? archive,
    TopRightCornerBlock? topRightCorner,
    List<TitleBlockRevision>? revisions,
  }) {
    return TitleBlockData(
      projectName: projectName ?? this.projectName,
      buildingName: buildingName ?? this.buildingName,
      drawingTitle: drawingTitle ?? this.drawingTitle,
      documentCode: documentCode ?? this.documentCode,
      organization: organization ?? this.organization,
      stage: stage ?? this.stage,
      sheetNumber: sheetNumber ?? this.sheetNumber,
      totalSheets: totalSheets ?? this.totalSheets,
      scaleText: scaleText ?? this.scaleText,
      approvals: approvals ?? this.approvals,
      archive: archive ?? this.archive,
      topRightCorner: topRightCorner ?? this.topRightCorner,
      revisions: revisions ?? this.revisions,
    );
  }
}
