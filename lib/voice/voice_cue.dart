// Extracted from HipLab@main lib/hip/voice/session_script.dart (VoiceCue / CuePriority),
// unchanged semantics: counts are never cut, calls beat info, info beats coaching.

/// Who wins when two lines want the air at once.
enum CuePriority { coach, info, call, count }

/// One thing to say (and/or a chime to play) at [at] seconds into a phase.
/// Clip keys are manifest keys; `chime.*` keys play on the chime channel.
class VoiceCue {
  const VoiceCue(this.at, this.clips, this.priority, {this.subtitle});
  final double at;
  final List<String> clips;
  final CuePriority priority;
  final String? subtitle;

  List<String> get voiceClips =>
      clips.where((c) => !c.startsWith('chime.')).toList();
  List<String> get chimes =>
      clips.where((c) => c.startsWith('chime.')).toList();

  @override
  String toString() => '${at.toStringAsFixed(2)} ${clips.join('+')}';
}
