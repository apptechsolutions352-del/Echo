import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import 'data/library_database.dart';
import 'services/audio_controller.dart';
import 'services/install_analytics.dart';
import 'services/library_scanner.dart';
import 'ui/echo_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  MediaKit.ensureInitialized();
  await MetadataGod.initialize();
  final database = await LibraryDatabase.open();
  unawaited(InstallAnalytics.reportFirstLaunch(database));
  runApp(
    EchoApp(
      database: database,
      scanner: LibraryScanner(database),
      audio: AudioController(),
      initialFiles: args
          .map(
            (arg) => arg.startsWith('file:')
                ? Uri.parse(arg).toFilePath()
                : p.absolute(arg),
          )
          .toList(),
    ),
  );
}
