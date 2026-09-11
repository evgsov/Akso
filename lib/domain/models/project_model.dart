import '../enums/projection_type.dart';
import 'piping_network.dart';

/// Корневой проект исполнительной схемы трубопроводов (.akso)
class ProjectModel {
  final String id;
  final String title;
  final String objectAddress;
  final String engineerName;
  final String creationDate;
  final ProjectionType projectionType;
  final String activeSystemId;
  final int activeDn;
  final double currentElevationZ;
  final PipingNetwork network;

  ProjectModel({
    required this.id,
    required this.title,
    this.objectAddress = '',
    this.engineerName = '',
    String? creationDate,
    this.projectionType = ProjectionType.gostFrontal45,
    this.activeSystemId = 'sys_b1',
    this.activeDn = 25,
    this.currentElevationZ = 0.0,
    PipingNetwork? network,
  })  : creationDate = creationDate ?? DateTime.now().toIso8601String().substring(0, 10),
        network = network ?? PipingNetwork();

  ProjectModel copyWith({
    String? id,
    String? title,
    String? objectAddress,
    String? engineerName,
    String? creationDate,
    ProjectionType? projectionType,
    String? activeSystemId,
    int? activeDn,
    double? currentElevationZ,
    PipingNetwork? network,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      title: title ?? this.title,
      objectAddress: objectAddress ?? this.objectAddress,
      engineerName: engineerName ?? this.engineerName,
      creationDate: creationDate ?? this.creationDate,
      projectionType: projectionType ?? this.projectionType,
      activeSystemId: activeSystemId ?? this.activeSystemId,
      activeDn: activeDn ?? this.activeDn,
      currentElevationZ: currentElevationZ ?? this.currentElevationZ,
      network: network ?? this.network,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'objectAddress': objectAddress,
        'engineerName': engineerName,
        'creationDate': creationDate,
        'projectionType': projectionType.index,
        'activeSystemId': activeSystemId,
        'activeDn': activeDn,
        'currentElevationZ': currentElevationZ,
        'network': network.toJson(),
      };

  factory ProjectModel.fromJson(Map<String, dynamic> json) => ProjectModel(
        id: json['id'] as String,
        title: json['title'] as String,
        objectAddress: json['objectAddress'] as String? ?? '',
        engineerName: json['engineerName'] as String? ?? '',
        creationDate: json['creationDate'] as String?,
        projectionType: ProjectionType.values[json['projectionType'] as int? ?? 0],
        activeSystemId: json['activeSystemId'] as String? ?? 'sys_b1',
        activeDn: json['activeDn'] as int? ?? 25,
        currentElevationZ: (json['currentElevationZ'] as num?)?.toDouble() ?? 0.0,
        network: PipingNetwork.fromJson(json['network'] as Map<String, dynamic>),
      );
}
