import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/domain/session.dart';
import 'package:smartfit/voice/session_runner.dart';
import 'package:smartfit/voice/session_script.dart';
import 'package:smartfit/voice/voice_cue.dart';
import 'package:smartfit/voice/voice_queue.dart';

import 'support.dart';

class RecordingVoiceOutput implements VoiceOutput {
  final spoken = <List<String>>[];
  final chimes = <String>[];
  int stops = 0;

  @override
  Future<void> begin() async {}
  @override
  Future<void> end() async {}
  @override
  Future<void> speak(List<String> assets) async => spoken.add([...assets]);
  @override
  Future<void> stopSpeech() async => stops++;
  @override
  Future<void> chime(String asset) async => chimes.add(asset);
  @override
  set volume(double value) {}
}

void main() {
  final exercises = loadLibrary();
  final catalog = loadCatalog();
  final voices = loadVoices();
  final script = SessionScript(source: voices);

  group('App voice preference adapter', () {
    test('saved follow-App settings resolve to the trainer clip language', () {
      final saved = {
        'voice': false,
        'chimes': true,
        'language': 'app',
        'volume': .4,
      };
      final settings = VoiceSettings.fromJson(saved);
      final trainer = settings.toTrainerSettings();
      expect(settings.toJson(), saved);
      expect(trainer.language, 'zh');
      expect(trainer.voice, isFalse);
      expect(trainer.chimes, isTrue);
      expect(trainer.volume, .4);
    });

    test('unavailable selected voice keeps chimes without partial speech', () {
      final output = RecordingVoiceOutput();
      final settings = const VoiceSettings(language: VoiceLanguage.en);
      expect(settings.toTrainerSettings().language, 'en');
      final queue = VoiceQueue(
        output: output,
        lib: voices,
        settings: settings.toTrainerSettings(),
      );
      queue.submit(
        const VoiceCue(0, ['chime.tick', 'n.3'], CuePriority.count),
        0,
      );
      expect(output.chimes, [voices.asset('chime.tick')]);
      expect(output.spoken, isEmpty);
    });
  });

  SessionRunner runner() {
    const first = coach.PlanItem(
      exerciseId: 'h-squat',
      mode: coach.DoseMode.time,
      sets: 1,
      workSeconds: 30,
      perSide: false,
      restSeconds: 10,
    );
    const second = coach.PlanItem(
      exerciseId: 'w-dead-bug',
      mode: coach.DoseMode.time,
      sets: 1,
      workSeconds: 30,
      perSide: false,
      restSeconds: 10,
    );
    return SessionRunner(
      SessionEngine(const [
        SessionPhase(
          kind: PhaseKind.prep,
          seconds: 10,
          exerciseId: 'h-squat',
          item: first,
          itemIndex: 0,
        ),
        SessionPhase(
          kind: PhaseKind.work,
          seconds: 30,
          exerciseId: 'h-squat',
          item: first,
          itemIndex: 0,
        ),
        SessionPhase(
          kind: PhaseKind.rest,
          seconds: 10,
          exerciseId: 'w-dead-bug',
          item: second,
          itemIndex: 1,
          nextExerciseId: 'w-dead-bug',
          nextItem: second,
        ),
        SessionPhase(
          kind: PhaseKind.work,
          seconds: 30,
          exerciseId: 'w-dead-bug',
          item: second,
          itemIndex: 1,
        ),
        SessionPhase(kind: PhaseKind.done, seconds: 0, itemIndex: 2),
      ]),
      script,
    );
  }

  List<String> clips(List<FiredCue> cues) => [
    for (final fired in cues) ...fired.cue.clips,
  ];

  test(
    'early end preserves progress and suppresses full completion speech',
    () {
      for (final (time, completed) in [(0.0, 0), (11.0, 0), (41.0, 1)]) {
        final session = runner()..finish(time);
        expect(session.engine.done, isTrue);
        expect(session.engine.completedExercises, completed);
        expect(session.update(time), isEmpty);
      }
      final session = runner();
      expect(clips(session.update(80)), contains('p.finish'));
      expect(session.engine.endedEarly, isFalse);
      expect(session.engine.completedExercises, 2);
    },
  );

  group('real drill-pack voice', () {
    test('every default template cue has a recorded asset', () async {
      final generator = TemplatePlanGenerator(lib: exercises, catalog: catalog);
      final checked = <String>{};
      for (final template in catalog.templates) {
        final result = await generator.generate(
          ScenarioRequest(
            templateId: template.id,
            scene: template.scenes.first,
            equipment: template.equipment.map(Equipment.byName).toSet(),
            minutes: template.minutes,
            level: 2,
          ),
        );
        expect(result.issues, isEmpty, reason: template.id);
        final builder = SessionBuilder(exercises);
        final phases = builder.phases(result.plan!);
        for (final phase in phases) {
          for (final cue in script.cues(
            phase,
            planSeconds: builder.planSeconds(result.plan!),
          )) {
            expect(cue.at, greaterThanOrEqualTo(0), reason: template.id);
            if (phase.kind != PhaseKind.done) {
              expect(cue.at, lessThan(phase.seconds), reason: template.id);
            }
            for (final key in cue.clips) {
              expect(
                voices.has(key),
                isTrue,
                reason: '${template.id}: missing pack clip $key',
              );
              expect(
                File(voices.asset(key)).existsSync(),
                isTrue,
                reason: '${template.id}: missing audio asset $key',
              );
              if (!key.startsWith('chime.')) {
                expect(voices.seconds(key), greaterThan(0), reason: key);
              }
              checked.add(key);
            }
          }
        }
      }
      expect(
        checked,
        containsAll(['p.welcome', 'p.finish', 'n.1', 'chime.start']),
      );
    });
  });

  group('drill-pack timelines', () {
    /// Lines of one phase never overlap, flexible lines end before the
    /// countdown (with margin), and nothing runs past the phase.
    void checkPhase(String where, SessionPhase phase, List<VoiceCue> cues) {
      final spans = [
        for (final c in cues) (c, c.at, c.at + voices.total(c.clips)),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      for (var i = 1; i < spans.length; i++) {
        expect(
          spans[i].$2,
          greaterThanOrEqualTo(spans[i - 1].$3 - 1e-9),
          reason: '$where: ${spans[i - 1].$1} overlaps ${spans[i].$1}',
        );
      }
      if (phase.kind == PhaseKind.done) return;
      final countdown = cues
          .where(
            (c) =>
                c.priority == CuePriority.count &&
                c.clips.contains('chime.tick'),
          )
          .map((c) => c.at)
          .fold<double?>(null, (m, t) => m == null || t < m ? t : m);
      for (final (c, _, end) in spans) {
        expect(
          end,
          lessThanOrEqualTo(phase.seconds + 1e-9),
          reason: '$where: $c runs past the phase',
        );
        if (countdown != null &&
            !c.clips.contains('chime.tick') &&
            (c.priority == CuePriority.coach ||
                c.priority == CuePriority.info)) {
          expect(
            end,
            lessThanOrEqualTo(countdown - countdownMargin + 1e-9),
            reason: '$where: $c would be cut by the countdown',
          );
        }
      }
    }

    test(
      'every template at every level: no overlap, no cut, pack lines used',
      () async {
        final generator = TemplatePlanGenerator(
          lib: exercises,
          catalog: catalog,
        );
        final used = <String>{};
        for (final template in catalog.templates) {
          for (final level in [1, 2, 3]) {
            final result = await generator.generate(
              ScenarioRequest(
                templateId: template.id,
                scene: template.scenes.first,
                equipment: template.equipment.map(Equipment.byName).toSet(),
                minutes: template.minutes,
                level: level,
              ),
            );
            if (result.plan == null) continue;
            final builder = SessionBuilder(exercises);
            final phases = builder.phases(result.plan!);
            for (var i = 0; i < phases.length; i++) {
              for (final bySkip in [false, true]) {
                final cues = script.cues(
                  phases[i],
                  planSeconds: builder.planSeconds(result.plan!),
                  bySkip: bySkip,
                );
                checkPhase(
                  '${template.id} L$level #$i ${phases[i]}',
                  phases[i],
                  cues,
                );
                for (final c in cues) {
                  for (final k in c.clips) {
                    expect(
                      File(voices.asset(k)).existsSync(),
                      isTrue,
                      reason: k,
                    );
                    if (k.contains('/')) {
                      used.add(k.substring(k.indexOf('/') + 1));
                    }
                  }
                }
              }
            }
          }
        }
        expect(
          used,
          containsAll([
            'intro',
            'cue1',
            'cue2',
            'rest',
            'finish',
            'side_switch',
          ]),
        );
      },
    );

    test('second side of a timed move speaks its side_switch line', () {
      const item = coach.PlanItem(
        exerciseId: 'h-couch-stretch',
        mode: coach.DoseMode.time,
        sets: 1,
        workSeconds: 30,
        perSide: true,
        restSeconds: 10,
      );
      List<String> said(Side side) => [
        for (final c in script.cues(
          SessionPhase(
            kind: PhaseKind.work,
            seconds: 30,
            exerciseId: item.exerciseId,
            item: item,
            set: 1,
            sets: 1,
            side: side,
          ),
          planSeconds: 300,
        ))
          ...c.clips,
      ];
      expect(said(Side.right), contains('h-couch-stretch/cue1'));
      expect(said(Side.right), isNot(contains('h-couch-stretch/side_switch')));
      expect(said(Side.left), contains('h-couch-stretch/side_switch'));
      expect(said(Side.left).first, 'chime.start');
    });

    test(
      'the rest after a move names it as finished, unless it was skipped',
      () {
        const next = coach.PlanItem(
          exerciseId: 'w-dead-bug',
          mode: coach.DoseMode.time,
          sets: 1,
          workSeconds: 30,
          perSide: false,
          restSeconds: 10,
        );
        const rest = SessionPhase(
          kind: PhaseKind.rest,
          seconds: 15,
          exerciseId: 'w-dead-bug',
          item: next,
          nextExerciseId: 'w-dead-bug',
          nextItem: next,
          doneExerciseId: 'h-squat',
          sets: 1,
          set: 1,
        );
        List<String> said({required bool bySkip}) => [
          for (final c in script.cues(rest, planSeconds: 300, bySkip: bySkip))
            ...c.clips,
        ];
        expect(said(bySkip: false), contains('h-squat/finish'));
        expect(said(bySkip: false), contains('p.next'));
        expect(said(bySkip: true), isNot(contains('h-squat/finish')));
        expect(said(bySkip: true), contains('p.rest'));
      },
    );
  });

  group('session runner', () {
    test('phase boundaries speak once at their absolute scheduled time', () {
      final r = runner();
      expect(clips(r.update(0)), contains('p.welcome'));
      expect(r.update(0), isEmpty);
      expect(clips(r.update(7)), contains('n.3'));
      expect(clips(r.update(8)), contains('n.2'));
      expect(clips(r.update(9)), contains('n.1'));
      final work = r.update(10);
      expect(r.engine.phase.kind, PhaseKind.work);
      expect(clips(work), ['chime.start', 'p.go']);
      expect(work.single.time, 10);
      expect(r.update(10), isEmpty);
      final done = r.update(80);
      expect(r.engine.done, isTrue);
      expect(clips(done), ['chime.finish', 'p.finish']);
      expect(r.update(81), isEmpty);
    });

    test('background gaps discard past phases and expired current cues', () {
      final r = runner();
      r.update(0);
      final due = r.update(
        49,
      ); // Rest began at 40; only its last tick is fresh.
      expect(r.engine.phase.kind, PhaseKind.rest);
      expect(r.engine.phaseStart, 40);
      expect(clips(due), ['chime.tick', 'n.1']);
      expect(due.single.time, 49);
      expect(r.update(49), isEmpty);
      expect(clips(r.update(50)), ['chime.start', 'p.go']);
    });

    test('skip and previous reload only the newly entered phase', () {
      final r = runner();
      r.update(10);
      r.skip(11);
      final rest = clips(r.update(11));
      expect(rest, contains('p.rest'));
      expect(rest, isNot(contains('p.nice'))); // No praise for a skipped move.
      expect(rest, isNot(contains('p.welcome')));
      r.skip(12);
      expect(r.engine.phase.exerciseId, 'w-dead-bug');
      expect(clips(r.update(12)), ['chime.start', 'p.go']);
      expect(r.update(12), isEmpty);
      r.previous(13);
      expect(r.engine.phase.exerciseId, 'h-squat');
      expect(clips(r.update(13)), ['chime.start', 'p.go']);
      expect(r.update(13), isEmpty);
    });
  });

  group('voice queue', () {
    test('higher priorities interrupt coaching; calls wait for counts', () {
      final output = RecordingVoiceOutput();
      final queue = VoiceQueue(
        output: output,
        lib: voices,
        settings: const VoiceSettings().toTrainerSettings(),
      );
      queue.submit(const VoiceCue(0, ['p.slow'], CuePriority.coach), 0);
      queue.submit(const VoiceCue(0, ['p.half'], CuePriority.info), .1);
      queue.submit(const VoiceCue(0, ['n.1'], CuePriority.count), .2);
      queue.submit(const VoiceCue(0, ['p.go'], CuePriority.call), .3);
      expect(output.spoken, hasLength(3));
      expect(output.stops, 2);
      queue.tick(.8);
      expect(queue.log.map((line) => line.clips.single), [
        'p.slow',
        'p.half',
        'n.1',
        'p.go',
      ]);
      expect(queue.log[0].cutAt, .1);
      expect(queue.log[1].cutAt, .2);
      expect(queue.log[2].cutAt, isNull);
      expect(output.spoken.last, [voices.asset('p.go')]);
    });

    test('cancel clears pending lines and stops the current line', () {
      final output = RecordingVoiceOutput();
      final queue = VoiceQueue(
        output: output,
        lib: voices,
        settings: const VoiceSettings().toTrainerSettings(),
      );
      queue.submit(const VoiceCue(0, ['n.1'], CuePriority.count), 0);
      queue.submit(const VoiceCue(0, ['p.half'], CuePriority.info), .1);
      queue.cancelAll(.2);
      queue.tick(1);
      expect(output.spoken, hasLength(1));
      expect(output.stops, 1);
      expect(queue.log.single.cutAt, .2);
    });

    test('chimes remain available with spoken coaching switched off', () {
      final output = RecordingVoiceOutput();
      final queue = VoiceQueue(
        output: output,
        lib: voices,
        settings: const VoiceSettings(voice: false).toTrainerSettings(),
      );
      queue.submit(
        const VoiceCue(0, ['chime.tick', 'n.3'], CuePriority.count),
        0,
      );
      expect(output.chimes, [voices.asset('chime.tick')]);
      expect(output.spoken, isEmpty);
    });
  });
}
