// Web entry for docs/screenshots/chat-*.png (not part of the app):
//   flutter build web -t test_screens/web_shots_main.dart --no-web-resources-cdn
//   cp <NotoSansSC.ttf> build/web/assets/shots/NotoSansSC.ttf
//   serve build/web, open ?shot=<name>, screenshot (tools/shots/chat_shots.py).
// Each shot seeds an in-memory store and scripts the conversation.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

class _Memory implements LocalStateStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final font = FontLoader('NotoSansSC')..addFont(rootBundle.load('shots/NotoSansSC.ttf'));
    await font.load();
  } on Object {
    // No font copied in: the browser falls back to its own.
  }
  final (lib, catalog, _) = await AppServices.loadContent();
  final store = AppStore(_Memory());
  final shot = Uri.base.queryParameters['shot'] ?? 'shell';
  final services = AppServices(
    library: lib,
    catalog: catalog,
    store: store,
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    chatReplyDelay: Duration.zero,
  );
  if (!shot.startsWith('opening')) await store.acceptSafety(blocked: false);
  final chat = services.chat..start();
  switch (shot) {
    case 'shell':
      await chat.send('你好');
    case 'opening-q':
      await chat.choose(chat.messages.last, 0); // 我已了解
      await chat.choose(chat.messages.last, 0); // 1/4 否
    case 'ask':
      await chat.send('想在家练练，有点犯懒');
      await chat.choose(chat.messages.last, 1); // 力量塑形
    case 'card':
      await chat.send('在家 15 分钟练核心，徒手');
    case 'card-slow':
      // The card → player move at 1/40 speed, for a mid-transition frame
      // (chat_shots.py clicks 开始训练 and shoots part-way through).
      // Slowed only once the card has settled (its own entrance would be
      // slowed too); the click comes after SHOT_WAIT ≥ 12 s.
      await chat.send('在家 15 分钟练核心，徒手');
      unawaited(Future<void>.delayed(const Duration(seconds: 8), () => timeDilation = 40));
    case 'drawer':
      for (final t in ['在办公室午休 10 分钟，肩颈很僵', '在家 15 分钟练核心，徒手', '睡前放松一下，15 分钟']) {
        await chat.send(t);
        final saved = await chat.save(chat.currentPlan!);
        if (t.contains('办公室')) {
          await store.renamePlan(saved.id, '午休肩颈放松');
          await chat.started(saved.plan);
        }
      }
      await chat.send('我的计划');
    case 'edit':
      await chat.send('在办公室午休 10 分钟，肩颈很僵');
      await chat.send('再短一点');
  }
  runApp(SmartFitApp(services: services, fontFamily: 'NotoSansSC'));
  if (shot == 'drawer') {
    await Future<void>.delayed(const Duration(seconds: 2));
    chat.command('@drawer');
  }
}
