import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_pack_installation.dart';
import 'theme.dart';
import 'theme/trainer_theme.dart';

/// Installation is shared with training media; the SDK owns browsing and practice.
class PoseHubLibraryPage extends StatefulWidget {
  const PoseHubLibraryPage({super.key, required this.catalog, this.media});

  final coach.PoseHubAppTestCatalog catalog;
  final PoseHubPackInstallation? media;

  @override
  State<PoseHubLibraryPage> createState() => _PoseHubLibraryPageState();
}

class _PoseHubLibraryPageState extends State<PoseHubLibraryPage> {
  Future<Uri>? _ready;

  @override
  void initState() {
    super.initState();
    _ready = widget.media?.ensureInstalled();
  }

  @override
  void didUpdateWidget(PoseHubLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.media, widget.media)) {
      _ready = widget.media?.ensureInstalled();
    }
  }

  void _retry() {
    final ready = widget.media?.ensureInstalled();
    setState(() {
      _ready = ready;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        return PoseHubActionBrowser(
          catalog: widget.catalog,
          mediaBaseUri: snapshot.data!,
          theme: SmartFitTrainerTheme.of(context),
        );
      }
      final failed = snapshot.hasError || widget.media == null;
      return Scaffold(
        appBar: const SfTopBar(title: '动作库'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(SfSpace.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SfIcon(
                  failed ? SfGlyph.info : SfGlyph.grid,
                  size: 36,
                  color: SfColors.muted,
                ),
                const SizedBox(height: SfSpace.x4),
                Text(
                  failed ? '动作素材暂时无法准备' : '正在准备动作素材',
                  key: ValueKey(
                    failed ? 'posehub-prepare-error' : 'posehub-preparing',
                  ),
                  style: SfType.headline,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SfSpace.x2),
                Text(
                  failed ? '请重试，已有训练数据会保留。' : '首次准备需要一点时间，完成后即可浏览与单练。',
                  style: SfType.body.copyWith(color: SfColors.muted),
                  textAlign: TextAlign.center,
                ),
                if (failed && widget.media != null) ...[
                  const SizedBox(height: SfSpace.x5),
                  SfPrimaryButton(
                    key: const ValueKey('posehub-prepare-retry'),
                    label: '重试',
                    expand: false,
                    onPressed: _retry,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
