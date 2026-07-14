import 'package:equatable/equatable.dart';

class LeagueEntity extends Equatable {
  final String id;
  final String name;
  final String country;
  final String? logo;
  final int matchCount;

  const LeagueEntity({
    required this.id, required this.name, required this.country,
    this.logo, required this.matchCount,
  });

  @override
  List<Object?> get props => [id];
}
