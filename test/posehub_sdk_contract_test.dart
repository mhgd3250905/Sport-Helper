import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

// SDK 97eb66d bundled baseline: r2-v1 (249 actions). r1-v3 is not migrated;
// scapular-C and h-sleeper-stretch were deleted before r2-v1 (2026-11-04).
const _r2v1CatalogSha =
    '02721e4c24a0445f2a05ef185b2569dc105566d630c5b8f901da059c0945117b';

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
      _r2v1CatalogSha,
    );
    expect(PoseHubActionLibrary.catalogSha256, _r2v1CatalogSha);
    pack = await PoseHubActionLibrary.loadBundled();
  });

  test('r2-v1 baseline keeps 249 identities and an AI catalogue', () {
    expect(poseHubPackVersionOf(pack), 'r2-v1');
    expect(PoseHubActionLibrary.packVersion, 'r2-v1');
    final ids = pack.allActions.map((action) => action.id).toSet();
    expect(pack.allActions, hasLength(249));
    expect(ids, hasLength(249));
    expect(ids, isNot(contains('scapular-C')));
    expect(ids, isNot(contains('h-sleeper-stretch')));
    final ai = pack.toAiCatalog();
    expect(ai.problems, isEmpty);
    expect(ai.ids, pack.semanticCompleteActions.map((action) => action.id));
  });

  test('every file downloads from the r2-v1 media root', () {
    final files = [for (final action in pack.allActions) ...action.files.values];
    expect(files, hasLength(747));
    expect(files.map((file) => file.path).toSet(), hasLength(747));
    expect(files.fold(0, (sum, file) => sum + file.bytes), 60073245);
    final base = PoseHubActionLibrary.mediaBaseUriFor(pack);
    expect(base.toString(), 'https://media.uuugk.win/pack/r2-v1/');
    for (final file in files) {
      expect(file.downloadUri, base.resolve(file.path), reason: file.path);
    }
  });
}
