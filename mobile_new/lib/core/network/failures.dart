abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Pas de connexion internet. Vérifiez votre réseau.']);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure() : super('Session expirée. Veuillez vous reconnecter.');
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure() : super('Une erreur inattendue est survenue.');
}
