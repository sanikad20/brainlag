import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }

    if (Platform.isAndroid) {
      // Emulator
      return 'http://10.0.2.2:8000';

      // Real phone:
      // return 'http://192.168.1.5:8000';
    }

    return 'http://127.0.0.1:8000';
  }
}