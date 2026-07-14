import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class VerifyOtpUseCase {
  final AuthRepository _repository;
  VerifyOtpUseCase(this._repository);

  Future<Either<Failure, UserEntity>> call({
    required String phoneNumber,
    required String otp,
  }) {
    if (otp.length != 6) {
      return Future.value(const Left(ValidationFailure('Le code OTP doit contenir 6 chiffres.')));
    }
    return _repository.verifyOtp(phoneNumber: phoneNumber, otp: otp);
  }
}
