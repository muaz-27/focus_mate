import 'package:flutter/services.dart';
import 'dart:typed_data';

class ScreenCaptureService {
  static const platform = MethodChannel('com.example.focus_mate/blocker');

  static Future<bool> requestPermission() async {
    try {
      final bool result = await platform.invokeMethod('requestScreenCapturePermission');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request permission: '${e.message}'.");
      return false;
    }
  }

  static Future<Uint8List?> captureScreen() async {
    try {
      final Uint8List result = await platform.invokeMethod('captureScreen');
      return result;
    } on PlatformException catch (e) {
      print("Failed to capture screen: '${e.message}'.");
      return null;
    }
  }

  static Future<void> stopService() async {
    try {
      await platform.invokeMethod('stopScreenCaptureService');
    } on PlatformException catch (e) {
      print("Failed to stop service: '${e.message}'.");
    }
  }
}
