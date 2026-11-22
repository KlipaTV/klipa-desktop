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
    this.reconnecting = false,
    this.showStatus = true,
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

  /// The channel stopped after it played and is being reopened.
  final bool reconnecting;

  /// False while an error covers the picture, so the bar never claims LIVE
  /// for a channel that stopped.
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final isWarning = buffering || reconnecting;
    final statusColor = isWarning ? KlipaColors.warning : KlipaColors.live;
    final statusLabel = reconnecting
        ? 'RECONNECTING'
        : buffering
        ? 'BUFFERING'
        : 'LIVE';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
        ),
      ),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: KlipaColors.inkRaised.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KlipaColors.borderStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: onPlayPause,
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: KlipaColors.foreground,
              ),
            ),
            if (showStatus) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.55),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: isWarning
                            ? KlipaColors.warning
                            : KlipaColors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KlipaColors.foreground,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: fit == BoxFit.contain ? 'Fill video' : 'Fit video',
              onPressed: onFitChanged,
              icon: Icon(
                fit == BoxFit.contain
                    ? Icons.fit_screen_rounded
                    : Icons.fullscreen_exit_rounded,
                size: 20,
                color: KlipaColors.foregroundMuted,
              ),
            ),
            IconButton(
              tooltip: fullscreen ? 'Exit full screen' : 'Enter full screen',
              onPressed: onFullscreenChanged,
              icon: Icon(
                fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                size: 21,
                color: KlipaColors.foregroundMuted,
              ),
            ),
            IconButton(
              tooltip: muted ? 'Unmute' : 'Mute',
              onPressed: onMute,
              icon: Icon(
                muted || volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                size: 20,
                color: KlipaColors.foregroundMuted,
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
                semanticFormatterCallback: (value) =>
                    '${value.round()} percent',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
