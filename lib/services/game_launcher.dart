import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/window_service.dart';

class GameLauncher {
  static Future<void> launch(BuildContext context, GameEntry game) async {
    final messenger = ScaffoldMessenger.of(context);
    final exe = game.executable;
    if (exe == null || exe.trim().isEmpty) {
      _showError(messenger, 'Nenhum executável configurado para "${game.title}".');
      return;
    }

    await BgmPlayer.instance.stop();

    // If the value is an existing file, run it directly from its own folder
    // (many games need the working directory to find their assets).
    final file = File(exe);
    final command = file.existsSync() ? _quote(file.absolute.path) : exe;
    final workingDirectory = file.existsSync() ? file.absolute.parent.path : null;

    try {
      final process = await Process.start(
        'sh',
        ['-c', command],
        workingDirectory: workingDirectory,
      );

      // Drain output so a chatty game never blocks on a full pipe.
      final stderr = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderr.write);
      process.stdout.drain<void>();

      // Hide the launcher while the game is running, then bring it back
      // when the game closes.
      GameRunState.instance.setRunning(true);
      unawaited(WindowService.hide());
      unawaited(
        process.exitCode.then((_) async {
          GameRunState.instance.setRunning(false);
          await WindowService.show();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }),
      );

      // Report very quick startup failures (wrong path, missing command).
      unawaited(_reportEarlyExit(messenger, game, process, stderr));
    } on ProcessException catch (e) {
      _showError(
        messenger,
        'Não foi possível iniciar "${game.title}".\n${e.message}',
      );
    }
  }

  static Future<void> _reportEarlyExit(
    ScaffoldMessengerState messenger,
    GameEntry game,
    Process process,
    StringBuffer stderr,
  ) async {
    final exitCode = await process.exitCode
        .timeout(const Duration(seconds: 3), onTimeout: () => -1);
    if (exitCode == 0 || exitCode == -1) return;

    final detail = stderr.toString().trim().isEmpty
        ? 'código de saída $exitCode'
        : stderr.toString().trim();
    _showError(messenger, 'Não foi possível iniciar "${game.title}".\n$detail');
  }

  static String _quote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}