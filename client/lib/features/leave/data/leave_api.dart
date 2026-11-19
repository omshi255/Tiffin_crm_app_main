import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/dio_client.dart';
import '../models/leave_request_model.dart';

class LeaveApi {
  static int get _offsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  // Vendor: Get leave requests
  static Future<Map<String, dynamic>> getLeavesForVendor({
    required String status,
    required int page,
    required int limit,
  }) async {
    final response = await DioClient.instance.get(
      '/leave/vendor',
      queryParameters: {
        'status': status,
        'page': page,
        'limit': limit,
      },
    );
    final data = parseData(response);
    final list = (data['leaves'] as List? ?? [])
        .map((x) => LeaveRequestModel.fromJson(x as Map<String, dynamic>))
        .toList();
    return {
      'leaves': list,
      'total': data['pagination']?['total'] ?? list.length,
    };
  }

  // Vendor: Approve / Reject Leave
  static Future<void> updateLeaveStatus({
    required String leaveId,
    required String status,
    String? rejectReason,
  }) async {
    final endpoint = status == 'approved'
        ? '/leave/$leaveId/approve'
        : '/leave/$leaveId/reject';
    
    final response = await DioClient.instance.put(
      endpoint,
      data: rejectReason != null ? {'notes': rejectReason} : null,
    );
    throwIfNotSuccess(response);
  }

  // Customer: Get leaves
  static Future<Map<String, dynamic>> getLeavesForCustomer({
    String? status,
    int page = 1,
    int limit = 100,
  }) async {
    final response = await DioClient.instance.get(
      '/leave/customer',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
        'limit': limit,
      },
    );
    final data = parseData(response);
    final list = (data['leaves'] as List? ?? [])
        .map((x) => LeaveRequestModel.fromJson(x as Map<String, dynamic>))
        .toList();
    return {
      'leaves': list,
      'total': data['pagination']?['total'] ?? list.length,
    };
  }

  static Future<Map<String, dynamic>> getMonthlySummary(String month) async {
    final response = await DioClient.instance.get(
      '/leave/summary',
      queryParameters: {
        'month': month,
        'timezoneOffsetMinutes': _offsetMinutes,
      },
    );
    return Map<String, dynamic>.from(parseData(response) as Map);
  }

  static Future<Map<String, dynamic>> getMonthlyBill(String month) async {
    final response = await DioClient.instance.get(
      '/customer/me/monthly-bill',
      queryParameters: {
        'month': month,
        'timezoneOffsetMinutes': _offsetMinutes,
      },
    );
    return Map<String, dynamic>.from(parseData(response) as Map);
  }

  static Future<Uint8List> downloadMonthlyBill(String month) async {
    final response = await DioClient.instance.get(
      '/customer/me/monthly-bill/pdf',
      queryParameters: {
        'month': month,
        'timezoneOffsetMinutes': _offsetMinutes,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data is Uint8List) return data;
    return Uint8List.fromList(List<int>.from(data as List));
  }

  // Customer: Request Leave
  static Future<void> requestLeave({
    required DateTime leaveDate,
    required String mealType,
    required String reason,
    String? notes,
  }) async {
    final response = await DioClient.instance.post(
      '/leave/request',
      data: {
        'leaveDate': leaveDate.toIso8601String().split('T')[0],
        'mealType': mealType,
        'reason': reason,
        'timezoneOffsetMinutes': _offsetMinutes,
        if (notes != null) 'notes': notes,
      },
    );
    throwIfNotSuccess(response);
  }

  // Vendor: Declare Holiday/Leave
  static Future<String> requestVendorLeave({
    required DateTime leaveDate,
    required String mealType,
    required String reason,
    String? notes,
  }) async {
    final response = await DioClient.instance.post(
      '/leave/vendor/request',
      data: {
        'leaveDate': leaveDate.toIso8601String().split('T')[0],
        'mealType': mealType,
        'reason': reason,
        if (notes != null) 'notes': notes,
      },
    );
    throwIfNotSuccess(response);
    final body = response.data;
    if (body is Map && body['message'] != null) {
      return body['message'].toString();
    }
    return 'Vendor holiday declared successfully';
  }
}
