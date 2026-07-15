import 'dart:async';

class LeaveApi {
  static Future<Map<String, dynamic>> getLeavesForVendor({
    required String status,
    required int page,
    required int limit,
  }) async {
    // Stub implementation returning empty leaves list
    return {
      'leaves': [],
      'total': 0,
    };
  }

  static Future<void> updateLeaveStatus({
    required String leaveId,
    required String status,
    String? rejectReason,
  }) async {
    // Stub implementation
  }
}
