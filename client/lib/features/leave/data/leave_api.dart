import '../../../../core/network/dio_client.dart';
import '../models/leave_request_model.dart';

class LeaveApi {
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
    required String status,
    required int page,
    required int limit,
  }) async {
    final response = await DioClient.instance.get(
      '/leave/customer',
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
        if (notes != null) 'notes': notes,
      },
    );
    throwIfNotSuccess(response);
  }

  // Vendor: Declare Holiday/Leave
  static Future<void> requestVendorLeave({
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
  }
}
