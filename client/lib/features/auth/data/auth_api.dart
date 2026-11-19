import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../models/auth_response_model.dart';
import '../models/user_model.dart';

abstract final class AuthApi {
  /// Sends an OTP, unless the server is in OTP bypass mode.
  /// Returns a session when bypass login succeeded, otherwise null.
  static Future<AuthResponseModel?> sendOtp(String phone, {String? role}) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: DioClient.instance.options.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final response = await dio.post(
        ApiEndpoints.sendOtp,
        data: {
          'phone': phone,
          if (role != null) 'role': role,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      throwIfNotSuccess(response);
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final payload = data['data'];
        if (payload is Map<String, dynamic> && payload['accessToken'] != null) {
          return AuthResponseModel.fromJson(payload);
        }
      }
      return null;
    } on DioException catch (e) {
      String? message;
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        message = data['message'] as String? ?? data['error'] as String?;
      }
      throw ApiException(
        message ?? e.message ?? 'Failed to send OTP',
        e.response?.statusCode,
      );
    }
  }

  static Future<AuthResponseModel> verifyOtp(String phone, String otp, {String? role}) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: DioClient.instance.options.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final response = await dio.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phone': phone,
          'otp': otp,
          if (role != null) 'role': role,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) throw ApiException('Invalid response');
      // Support both { success, data: { accessToken, user } } and direct { accessToken, refreshToken, user }
      Map<String, dynamic>? payload = data['data'] is Map<String, dynamic>
          ? data['data'] as Map<String, dynamic>
          : null;
      if (payload == null && data['accessToken'] != null) {
        payload = data;
      }
      if (payload == null) {
        final success = data['success'] as bool? ?? false;
        if (!success) {
          final msg = data['message'] as String? ?? 'Verification failed';
          throw ApiException(msg, response.statusCode);
        }
        throw ApiException('Invalid response');
      }
      return AuthResponseModel.fromJson(payload);
    } on DioException catch (e) {
      String? message;
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        message = data['message'] as String? ?? data['error'] as String?;
      }
      throw ApiException(
        message ?? e.message ?? 'Verification failed',
        e.response?.statusCode,
      );
    }
  }

  static Future<AuthResponseModel?> refreshToken(String refreshToken) async {
    try {
      final dio = Dio(BaseOptions(baseUrl: DioClient.instance.options.baseUrl));
      final response = await dio.post(
        ApiEndpoints.refreshToken,
        data: {'refreshToken': refreshToken},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final success = data['success'] as bool? ?? false;
      final payload = data['data'];
      if (!success || payload is! Map<String, dynamic>) return null;
      return AuthResponseModel.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

  static Future<UserModel> getProfile() async {
    final response = await DioClient.instance.get(ApiEndpoints.authMe);
    final data = parseData(response);
    if (data is! Map<String, dynamic>) throw ApiException('Invalid response');
    return UserModel.fromJson(data);
  }

  /// Persists FCM token for vendor/admin/delivery_staff (customers use the same route; server updates [Customer] when role is customer).
  static Future<void> saveFcmToken(String token) async {
    await DioClient.instance.put(
      ApiEndpoints.usersFcmToken,
      data: <String, dynamic>{'fcmToken': token},
    );
  }

  static Future<UserModel> updateProfile(Map<String, dynamic> body) async {
    final response = await DioClient.instance.put(
      ApiEndpoints.authMe,
      data: body,
    );
    final data = parseData(response);
    if (data is! Map<String, dynamic>) throw ApiException('Invalid response');
    final nested = data['user'];
    if (nested is Map<String, dynamic>) {
      return UserModel.fromJson(nested);
    }
    return UserModel.fromJson(data);
  }

  /// Idempotent vendor onboarding (POST). Prefer over PUT /me for first-time setup.
  static Future<UserModel> submitVendorOnboarding({
    required String businessName,
    required String ownerName,
    required String address,
  }) async {
    final response = await DioClient.instance.post(
      ApiEndpoints.vendorOnboarding,
      data: {
        'businessName': businessName,
        'ownerName': ownerName,
        'address': address,
      },
    );
    final data = parseData(response);
    if (data is! Map<String, dynamic>) throw ApiException('Invalid response');
    final nested = data['user'];
    if (nested is Map<String, dynamic>) {
      return UserModel.fromJson(nested);
    }
    throw ApiException('Invalid response');
  }

  static Future<void> logout() async {
    try {
      await DioClient.instance.post(ApiEndpoints.logout);
    } catch (_) {}
  }
}
