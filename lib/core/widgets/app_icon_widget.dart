import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';

class AppIconWidget extends StatefulWidget {
  final String? packageName;
  final String? appName;
  final Uint8List? iconBytes;
  final String? iconBase64;
  final double size;
  final double fallbackFontSize;

  const AppIconWidget({
    super.key,
    this.packageName,
    this.appName,
    this.iconBytes,
    this.iconBase64,
    this.size = 36,
    this.fallbackFontSize = 16,
  });

  @override
  State<AppIconWidget> createState() => _AppIconWidgetState();
}

class _AppIconWidgetState extends State<AppIconWidget> {
  Uint8List? _resolvedBytes;

  @override
  void initState() {
    super.initState();
    _resolveIcon();
  }

  @override
  void didUpdateWidget(covariant AppIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconBytes != widget.iconBytes ||
        oldWidget.iconBase64 != widget.iconBase64 ||
        oldWidget.packageName != widget.packageName) {
      _resolveIcon();
    }
  }

  Future<void> _resolveIcon() async {
    // 1. Direct byte provision
    if (widget.iconBytes != null) {
      if (mounted) setState(() => _resolvedBytes = widget.iconBytes);
      return;
    }

    // 2. Base64 encoded string
    if (widget.iconBase64 != null && widget.iconBase64!.isNotEmpty) {
      try {
        final decoded = base64Decode(widget.iconBase64!);
        if (mounted) setState(() => _resolvedBytes = decoded);
      } catch (_) {}
      return;
    }

    // 3. Dynamic lookup via DeviceApps (for native device apps)
    if (widget.packageName != null && widget.packageName!.isNotEmpty) {
      try {
        final app = await DeviceApps.getApp(widget.packageName!, true);
        if (app is ApplicationWithIcon && mounted) {
          setState(() => _resolvedBytes = app.icon);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedBytes != null && _resolvedBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _resolvedBytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: widget.size,
          height: widget.size,
          errorBuilder: (_, __, ___) => _buildFallback(),
        ),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    final letter = (widget.appName != null && widget.appName!.trim().isNotEmpty)
        ? widget.appName!.trim().substring(0, 1).toUpperCase()
        : "?";
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: widget.fallbackFontSize,
          ),
        ),
      ),
    );
  }
}
