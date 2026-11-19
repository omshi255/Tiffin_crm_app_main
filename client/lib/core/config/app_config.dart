import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  // Set to true for local backend (e.g. http://localhost:5000), false for Render.
  static const bool useLocalApi = false;

  static const String apiUrlLocal = 'http://localhost:5000/api/v1';

  /// Phone and emulator cannot use localhost. This is this computer's Wi-Fi address.
  static const String apiUrlLan = 'http://10.28.100.92:5000/api/v1';
  static const String apiUrlProduction =
      'https://tiffin-crm-app-main-4g70.onrender.com/api/v1';

  static String get baseUrl {
    if (!useLocalApi) return apiUrlProduction;
    if (kIsWeb) return apiUrlLocal;
    return apiUrlLan;
  }

  // Origin for Socket.IO (no `/api/v1` path). Used by `DeliveryTrackingSocket`.
  static String get socketOrigin {
    final u = Uri.parse(baseUrl);
    if (u.hasPort) {
      return '${u.scheme}://${u.host}:${u.port}';
    }
    return '${u.scheme}://${u.host}';
  }

  static const String fcmSenderId = String.fromEnvironment(
    'FCM_SENDER_ID',
    defaultValue: '',
  );

  static const String razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'YOUR_RAZORPAY_KEY_ID',
  );
}
