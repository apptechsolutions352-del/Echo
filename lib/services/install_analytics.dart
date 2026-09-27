import 'dart:io';

import '../data/library_database.dart';

/// Sends one anonymous first-launch report per local app data installation.
///
/// The local flag is saved before sending so later launches never retry or
/// accidentally double count when a response is lost. If offline, that report
/// can be missed; analytics must never prevent the player from opening.
class InstallAnalytics {
  InstallAnalytics._();

  static const _settingKey = 'install_report_attempted_v1';
  static final _endpoint = Uri.parse(
    'https://echo-2ve.pages.dev/api/install',
  );

  static Future<void> reportFirstLaunch(LibraryDatabase database) async {
    try {
      if (await database.setting(_settingKey) != null) return;

      await database.saveSetting(_settingKey, '1');

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      try {
        final request = await client.postUrl(_endpoint).timeout(
          const Duration(seconds: 4),
        );
        request.contentLength = 0;
        final response = await request.close().timeout(
          const Duration(seconds: 4),
        );
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // Analytics is best effort. Do not block or disrupt playback on failure.
    }
  }
}
