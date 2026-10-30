import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import 'theme.dart';

/// Prewarm and the full training page use the same screen-width decode key.
abstract final class TrainingPosterImages {
  static int decodeWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(1, 0x7fffffff);

  static List<String> candidates(BuildContext context, Exercise exercise) {
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final action = services?.poseHubCatalog?.tryGet(exercise.id);
    final media = exercise.media;
    return {
      if (action != null)
        'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${action.id}.webp',
      if (media.alphaPlaybackPoster?.isNotEmpty == true)
        media.alphaPlaybackPoster!,
      media.playbackPosterFor(
        light: Theme.of(context).brightness == Brightness.light,
      ),
    }.where((asset) => asset.isNotEmpty).toList(growable: false);
  }

  static ImageProvider<Object> provider(String asset, int width) =>
      ResizeImage.resizeIfNeeded(width, null, AssetImage(asset));

  static Future<void> precache(BuildContext context, Exercise exercise) async {
    await prepare(context, exercise);
  }

  static Future<bool> prepare(BuildContext context, Exercise exercise) async {
    final assets = candidates(context, exercise);
    final width = decodeWidth(context);
    for (final asset in assets) {
      var failed = false;
      await precacheImage(
        provider(asset, width),
        context,
        onError: (_, _) => failed = true,
      );
      if (!failed) return true;
      if (!context.mounted) return false;
    }
    return false;
  }
}

/// The same square, contain-fitted still that covers the video until it emits
/// a real first frame. It is the actual media, never an entrance placeholder.
class TrainingPoster extends StatelessWidget {
  const TrainingPoster({
    super.key,
    required this.exercise,
    this.mirrored = false,
    this.radius = 0,
  });
  final Exercise exercise;
  final bool mirrored;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(radius),
    child: ColoredBox(
      color: SfColors.mediaStage,
      child: Transform.flip(
        flipX: mirrored,
        child: AspectRatio(
          aspectRatio: 1,
          child: DecodedTrainingPoster(exercise: exercise),
        ),
      ),
    ),
  );
}

/// Resolves only when the asset/theme/decode key changes, retaining the still
/// across ordinary SDK updates without another codec or empty image frame.
class DecodedTrainingPoster extends StatefulWidget {
  const DecodedTrainingPoster({super.key, required this.exercise});
  final Exercise exercise;

  @override
  State<DecodedTrainingPoster> createState() => _DecodedTrainingPosterState();
}

class _DecodedTrainingPosterState extends State<DecodedTrainingPoster> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  String? _signature;
  List<String> _assets = const [];
  var _width = 1;
  var _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(DecodedTrainingPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _resolve() {
    final assets = TrainingPosterImages.candidates(context, widget.exercise);
    final width = TrainingPosterImages.decodeWidth(context);
    final signature =
        '$width/${assets.join('|')}/${DefaultAssetBundle.of(context).hashCode}';
    if (_signature == signature) return;
    _signature = signature;
    _assets = assets;
    _width = width;
    _index = 0;
    _info?.dispose();
    _info = null;
    _listen();
  }

  void _listen() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
    _stream = null;
    if (_index >= _assets.length) return;
    final stream = TrainingPosterImages.provider(
      _assets[_index],
      _width,
    ).resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!mounted || !identical(_stream, stream)) {
          info.dispose();
          return;
        }
        void update() {
          _info?.dispose();
          _info = info;
        }

        if (synchronousCall) {
          update();
        } else {
          setState(update);
        }
      },
      onError: (Object _, StackTrace? stack) {
        if (!mounted || !identical(_stream, stream)) return;
        _index++;
        _listen();
        if (mounted) setState(() {});
      },
    );
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    return RepaintBoundary(
      child: image == null
          ? const SizedBox.expand()
          : RawImage(
              image: image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}
