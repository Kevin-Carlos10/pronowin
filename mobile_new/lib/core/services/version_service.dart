import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import 'remote_config_service.dart';

class VersionService {
  static Future<void> check(BuildContext context) async {
    try {
      final pkg     = await PackageInfo.fromPlatform();
      final current = _parse(pkg.version);
      final min     = _parse(RemoteConfigService.minVersion);
      final latest  = _parse(RemoteConfigService.latestVersion);

      if (!context.mounted) return;

      final isForced  = _compare(current, min) < 0;
      final hasUpdate = _compare(current, latest) < 0;

      if (RemoteConfigService.maintenanceMode) {
        await _showDialog(context,
          message:  RemoteConfigService.maintenanceMsg,
          isForced: true,
          title:    '🔧 Maintenance en cours');
        return;
      }

      if (isForced || hasUpdate) {
        await _showDialog(context,
          message:  RemoteConfigService.updateMessage,
          isForced: isForced || RemoteConfigService.forceUpdate,
        );
      }
    } catch (_) {
      // Silencieux — le check de version ne doit jamais bloquer l'app
    }
  }

  static Future<void> _showDialog(
    BuildContext context, {
    required String message,
    required bool   isForced,
    String? title,
  }) async {
    await showDialog(
      context:            context,
      barrierDismissible: !isForced,
      builder: (ctx) => PopScope(
        canPop: !isForced,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Text(title != null ? '' : '🚀 ',
              style: const TextStyle(fontSize: 22)),
            Text(title ?? (isForced ? 'Mise à jour requise' : 'Mise à jour disponible'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          content: Text(message,
            style: const TextStyle(fontSize: 14, height: 1.5)),
          actions: [
            if (!isForced)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Plus tard')),
            FilledButton(
              onPressed: () async {
                if (title == null) {
                  final url = Platform.isIOS
                      ? AppConstants.appStoreUrl
                      : AppConstants.playStoreUrl;
                  try {
                    await launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  } catch (_) {}
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(title != null ? 'OK' : 'Mettre à jour')),
          ],
        ),
      ),
    );
  }

  static List<int> _parse(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) { parts.add(0); }
    return parts;
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }
}
