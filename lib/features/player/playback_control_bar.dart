import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

bool shouldShowPlaybackControls({
  required bool requestedVisible,
  required bool playing,
  required bool buffering,
  required bool opening,
  required bool hasError,
}) => requestedVisible || !playing || buffering || opening || hasError;

class PlaybackControlBar extends StatelessWidget {
  const PlaybackControlBar({
    required this.channelName,
    required this.playing,
    required this.buffering,
    required this.muted,
    required this.volume,
    required this.fit,
    required this.fullscreen,
    required this.onPlayPause,
    required this.onMute,
    required this.onVolumeChanged,
    required this.onFitChanged,
    required this.onFullscreenChanged,
    super.key,
  });

  final String channelName;
  final bool playing;
  final bool buffering;
  final bool muted;
  final double volume;
  final BoxFit fit;
  final bool fullscreen;
  final VoidCallback? onPlayPause;
  final VoidCallback? onMute;
  final ValueChanged<double>? onVolumeChanged;
  final VoidCallback onFitChanged;
  final VoidCallback onFullscreenChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.92)],
      ),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: onPlayPause,
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 8),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: buffering ? KlipaColors.warning : KlipaColors.live,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          buffering ? 'BUFFERING' : 'LIVE',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            channelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: fit == BoxFit.contain ? 'Fill video' : 'Fit video',
          onPressed: onFitChanged,
          icon: Icon(
            fit == BoxFit.contain
                ? Icons.fit_screen_rounded
                : Icons.fullscreen_exit_rounded,
          ),
        ),
        IconButton(
          tooltip: fullscreen ? 'Exit full screen' : 'Enter full screen',
          onPressed: onFullscreenChanged,
          icon: Icon(
            fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
          ),
        ),
        IconButton(
          tooltip: muted ? 'Unmute' : 'Mute',
          onPressed: onMute,
          icon: Icon(
            muted || volume == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
          ),
        ),
        SizedBox(
          width: 104,
          child: Slider(
            value: volume.clamp(0, 100),
            max: 100,
            divisions: 20,
            label: '${volume.round()}%',
            onChanged: onVolumeChanged,
            semanticFormatterCallback: (value) => '${value.round()} percent',
          ),
        ),
      ],
    ),
  );
}
