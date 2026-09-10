import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/network/dio_exception_handler.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<void> sendOtp(String phoneNumber);
  Future<Map<String, dynamic>> verifyOtp({required String phoneNumber, required String otp});
  /// Retourne `true` si l'email ne correspond à aucun compte existant.
  Future<bool> sendEmailOtp(String email);
  Future<Map<String, dynamic>> verifyEmailOtp({required String email, required String otp});
  Future<Map<String, dynamic>> googleLogin(String idToken);
  Future<UserModel> getProfile();
  Future<void> logout();
  Future<void> deleteAccount();
  Future<DateTime> acceptTerms();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final Dio _dio;
  AuthRemoteDataSourceImpl(this._dio);

  @override
  Future<void> sendOtp(String phoneNumber) async {
    try {
      await _dio.post(
        ApiEndpoints.sendOtp,
        data: {'phone_number': phoneNumber},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<Map<String, dynamic>> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.verifyOtp,
        data: {'phone_number': phoneNumber, 'otp': otp},
      );
      // Retourne { user, access_token, refresh_token }
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<bool> sendEmailOtp(String email) async {
    try {
      final response = await _dio.post(ApiEndpoints.sendEmailOtp, data: {'email': email});
      return (response.data as Map<String, dynamic>)['isNewUser'] as bool? ?? false;
    } on DioException catch (e) { throw _handleError(e); }
  }

  @override
  Future<Map<String, dynamic>> verifyEmailOtp({required String email, required String otp}) async {
    try {
      final response = await _dio.post(ApiEndpoints.verifyEmailOtp, data: {'email': email, 'otp': otp});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) { throw _handleError(e); }
  }

  @override
  Future<Map<String, dynamic>> googleLogin(String idToken) async {
    try {
      final response =
          await _dio.post(ApiEndpoints.googleLogin, data: {'id_token': idToken});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) { throw _handleError(e); }
  }

  @override
  Future<UserModel> getProfile() async {
    try {
      final response = await _dio.get(ApiEndpoints.profile);
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _dio.post(ApiEndpoints.logout);
    } on DioException catch (_) {
      // On ignore l'erreur réseau au logout
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _dio.delete(ApiEndpoints.deleteAccount);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<DateTime> acceptTerms() async {
    try {
      final response = await _dio.patch(ApiEndpoints.acceptTerms);
      return DateTime.parse(response.data['accepted_terms_at'] as String).toLocal();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Failure _handleError(DioException e, [String? context]) =>
      handleDioException(e, context: context);
}
