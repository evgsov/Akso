import '../enums/projection_type.dart';
import 'callout.dart';
import 'piping_network.dart';
import 'report_template.dart';

/// Корневой проект исполнительной схемы трубопроводов (.akso)
class ProjectModel {
  final String id;
  final String title;
  final String projectCode;
  final String objectAddress;
  final String engineerName;
  final String notes;
  final String creationDate;
  final String lastModifiedDate;
  final ProjectionType projectionType;
  final String activeSystemId;
  final int activeDn;
  final double currentElevationZ;
  final PipingNetwork network;
  final Map<String, String> calloutTemplates;
  final Map<String, ReportTemplate>? reportTemplates;

  ProjectModel({
    required this.id,
    required this.title,
    this.projectCode = '',
    this.objectAddress = '',
    this.engineerName = '',
    this.notes = '',
    String? creationDate,
    String? lastModifiedDate,
    this.projectionType = ProjectionType.gostFrontal45,
    this.activeSystemId = 'sys_b1',
    this.activeDn = 25,
    this.currentElevationZ = 0.0,
    PipingNetwork? network,
    Map<String, String>? calloutTemplates,
    this.reportTemplates,
  })  : creationDate = creationDate ?? DateTime.now().toIso8601String().substring(0, 10),
        lastModifiedDate = lastModifiedDate ?? (creationDate ?? DateTime.now().toIso8601String()),
        network = network ?? PipingNetwork(),
        calloutTemplates = calloutTemplates != null
            ? Map.from(calloutTemplates)
            : Map.from(defaultCalloutTemplates);

  ProjectModel copyWith({
    String? id,
    String? title,
    String? projectCode,
    String? objectAddress,
    String? engineerName,
    String? notes,
    String? creationDate,
    String? lastModifiedDate,
    ProjectionType? projectionType,
    String? activeSystemId,
    int? activeDn,
    double? currentElevationZ,
    PipingNetwork? network,
    Map<String, String>? calloutTemplates,
    Map<String, ReportTemplate>? reportTemplates,
    bool clearReportTemplates = false,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      title: title ?? this.title,
      projectCode: projectCode ?? this.projectCode,
      objectAddress: objectAddress ?? this.objectAddress,
      engineerName: engineerName ?? this.engineerName,
      notes: notes ?? this.notes,
      creationDate: creationDate ?? this.creationDate,
      lastModifiedDate: lastModifiedDate ?? this.lastModifiedDate,
      projectionType: projectionType ?? this.projectionType,
      activeSystemId: activeSystemId ?? this.activeSystemId,
      activeDn: activeDn ?? this.activeDn,
      currentElevationZ: currentElevationZ ?? this.currentElevationZ,
      network: network ?? this.network,
      calloutTemplates: calloutTemplates ?? this.calloutTemplates,
      reportTemplates: clearReportTemplates ? null : (reportTemplates ?? this.reportTemplates),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'projectCode': projectCode,
        'objectAddress': objectAddress,
        'engineerName': engineerName,
        'notes': notes,
        'creationDate': creationDate,
        'lastModifiedDate': lastModifiedDate,
        'projectionType': projectionType.index,
        'activeSystemId': activeSystemId,
        'activeDn': activeDn,
        'currentElevationZ': currentElevationZ,
        'network': network.toJson(),
        'calloutTemplates': calloutTemplates,
        if (reportTemplates != null)
          'reportTemplates': reportTemplates!.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    final created = json['creationDate'] as String?;
    final lastMod = json['lastModifiedDate'] as String? ?? created;
    return ProjectModel(
      id: json['id'] as String,
      title: json['title'] as String,
      projectCode: json['projectCode'] as String? ?? '',
      objectAddress: json['objectAddress'] as String? ?? '',
      engineerName: json['engineerName'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      creationDate: created,
      lastModifiedDate: lastMod,
      projectionType: ProjectionType.values[json['projectionType'] as int? ?? 0],
      activeSystemId: json['activeSystemId'] as String? ?? 'sys_b1',
      activeDn: json['activeDn'] as int? ?? 25,
      currentElevationZ: (json['currentElevationZ'] as num?)?.toDouble() ?? 0.0,
      network: PipingNetwork.fromJson(Map<String, dynamic>.from(json['network'] as Map)),
      calloutTemplates: json['calloutTemplates'] != null
          ? Map<String, String>.from(json['calloutTemplates'] as Map)
          : null,
      reportTemplates: json['reportTemplates'] != null
          ? (json['reportTemplates'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                ReportTemplate.fromJson(Map<String, dynamic>.from(v as Map)),
              ),
            )
          : null,
    );
  }
}
