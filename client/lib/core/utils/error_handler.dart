import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import 'app_snackbar.dart';

abstract final class ErrorHandler {
  static void show(BuildContext context, dynamic error) {
    String message = 'Something went wrong';
    if (error is ApiException) {
      message = error.message ?? message;
    } else if (error is DioException) {
      final resData = error.response?.data;
      if (resData is Map<String, dynamic>) {
        message = resData['message'] as String? ?? resData['error'] as String? ?? message;
      } else if (error.message != null && error.message!.isNotEmpty) {
        message = error.message!;
      }
    } else if (error.toString().contains('timeout')) {
      message = 'Connection timeout. Try again.';
    } else if (error.toString().contains('connection') ||
        error.toString().contains('SocketException')) {
      message = 'No internet connection.';
    }
    AppSnackbar.error(context, message);
  }
}

