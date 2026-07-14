import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../repositories/auth_repository.dart';

class SendOtpUseCase {
  final AuthRepository _repository;
  SendOtpUseCase(this._repository);

  Future<Either<Failure, void>> call(String phoneNumber) {
    if (phoneNumber.length < 8) {
      return Future.value(const Left(ValidationFailure('Numéro de téléphone invalide.')));
    }
    return _repository.sendOtp(phoneNumber);
  }
}
