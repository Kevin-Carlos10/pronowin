import 'package:pronowin/l10n/app_strings.dart';
abstract class Failure {
  final String _sourceMessage;
  final List<Object?> _arguments;
  String get message => trCurrent(_sourceMessage, _arguments);
  const Failure(String message, [List<Object?> arguments = const []])
      : _sourceMessage = message, _arguments = arguments;
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, [super.arguments]);
}

/// 404 : la ressource n'existe pas. Seul cas où « introuvable » est vrai —
/// une panne réseau n'en dit rien.
class NotFoundFailure extends ServerFailure {
  const NotFoundFailure() : super('Ressource introuvable.');
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Pas de connexion internet. Vérifie ton réseau.']);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure() : super('Session expirée. Veuillez te reconnecter.');
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure() : super('Une erreur inattendue est survenue.');
}
