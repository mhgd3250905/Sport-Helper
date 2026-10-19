import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/domain/session.dart';
import 'package:smartfit/voice/session_runner.dart';
import 'package:smartfit/voice/session_script.dart';
import 'package:smartfit/voice/voice_cue.dart';
import 'package:smartfit/voice/voice_library.dart';
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
  final voices = VoiceLibrary.fromJson(
    jsonDecode(File(VoiceLibrary.manifestAsset).readAsStringSync())
        as Map<String, dynamic>,
  );
  final script = SessionScript(lib: voices, exercises: exercises);

  SessionRunner runner() {
    const first = PlanItem(
      exerciseId: 'h-squat',
      mode: DoseMode.time,
      sets: 1,
      workSeconds: 30,
      perSide: false,
      restSeconds: 10,
    );
    const second = PlanItem(
      exerciseId: 'w-dead-bug',
      mode: DoseMode.time,
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

  group('real voice manifest', () {
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
                reason: '${template.id}: missing manifest clip $key',
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
        settings: const VoiceSettings(),
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
        settings: const VoiceSettings(),
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
        settings: const VoiceSettings(voice: false),
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
