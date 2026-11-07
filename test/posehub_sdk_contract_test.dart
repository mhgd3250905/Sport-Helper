import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

// SDK PR #21 bundled baseline: r2-v10 keeps 249 actions and 23 alternating
// pairs; updated media objects remain under the r2-v1 distribution root.
// r1-v3 is not migrated; scapular-C and h-sleeper-stretch were deleted before
// r2-v1 (2026-11-04).
const _r2v10CatalogSha =
    'bd1963f3e139d2e0c0ed50ee763452841c91dcdffbd7663c4e9190597c8e0b0b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late coach.PoseHubAppTestCatalog pack;

  setUpAll(() async {
    final raw = await rootBundle.load(
      '${PoseHubActionLibrary.assetRoot}catalog.json',
    );
    expect(
      coach.sha256Hex(
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      ),
      _r2v10CatalogSha,
    );
    expect(PoseHubActionLibrary.catalogSha256, _r2v10CatalogSha);
    pack = await PoseHubActionLibrary.loadBundled();
  });

  test('r2-v10 baseline keeps 249 identities and an AI catalogue', () {
    expect(poseHubPackVersionOf(pack), 'r2-v10');
    expect(PoseHubActionLibrary.packVersion, 'r2-v10');
    final ids = pack.allActions.map((action) => action.id).toSet();
    expect(pack.allActions, hasLength(249));
    expect(ids, hasLength(249));
    expect(ids, isNot(contains('scapular-C')));
    expect(ids, isNot(contains('h-sleeper-stretch')));
    final ai = pack.toAiCatalog();
    expect(ai.problems, isEmpty);
    expect(ai.ids, pack.semanticCompleteActions.map((action) => action.id));
  });

  test('every file downloads from the r2-v1 media root (r2-v10 reuses it)', () {
    expect(poseHubMediaPackOf(pack), 'r2-v1');
    final files = [
      for (final action in pack.allActions) ...action.files.values,
    ];
    expect(files, hasLength(747));
    expect(files.map((file) => file.path).toSet(), hasLength(747));
    expect(files.fold(0, (sum, file) => sum + file.bytes), 60198071);
    final base = PoseHubActionLibrary.mediaBaseUriFor(pack);
    expect(base.toString(), 'https://media.uuugk.win/pack/r2-v1/');
    for (final file in files) {
      expect(file.downloadUri, base.resolve(file.path), reason: file.path);
    }
  });
}
