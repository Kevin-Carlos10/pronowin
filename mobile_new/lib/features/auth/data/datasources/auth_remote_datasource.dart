import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/network/dio_exception_handler.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<Map<String, dynamic>> quickRegister({String? phoneNumber, String? email});
  Future<void> sendOtp(String phoneNumber);
  Future<Map<String, dynamic>> verifyOtp({required String phoneNumber, required String otp});
  Future<Map<String, dynamic>> registerEmail({required String email, required String password, required String pseudo});
  Future<Map<String, dynamic>> loginEmail({required String email, required String password});
  Future<void> sendEmailOtp(String email);
  Future<Map<String, dynamic>> verifyEmailOtp({required String email, required String otp});
  Future<UserModel> getProfile();
  Future<void> logout();
  Future<void> deleteAccount();
  Future<DateTime> acceptTerms();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final Dio _dio;
  AuthRemoteDataSourceImpl(this._dio);

  @override
  Future<Map<String, dynamic>> quickRegister({String? phoneNumber, String? email}) async {
    try {
      final data = <String, dynamic>{};
      if (phoneNumber != null) data['phone_number'] = phoneNumber;
      if (email != null) data['email'] = email;
      final response = await _dio.post(ApiEndpoints.quickRegister, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) { throw _handleError(e); }
  }

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
  Future<Map<String, dynamic>> registerEmail({required String email, required String password, required String pseudo}) async {
    try {
      final response = await _dio.post(ApiEndpoints.registerEmail, data: {'email': email, 'password': password, 'pseudo': pseudo});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) { throw _handleError(e); }
  }

  @override
  Future<Map<String, dynamic>> loginEmail({required String email, required String password}) async {
    try {
      final response = await _dio.post(ApiEndpoints.loginEmail, data: {'email': email, 'password': password});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) { throw _handleError(e); }
  }

  @override
  Future<void> sendEmailOtp(String email) async {
    try {
      await _dio.post(ApiEndpoints.sendEmailOtp, data: {'email': email});
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
      return DateTime.parse(response.data['accepted_terms_at'] as String);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Failure _handleError(DioException e, [String? context]) =>
      handleDioException(e, context: context);
}
