import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/shift/domain/shift_models.dart';
import '../../../../features/shift/presentation/shift_providers.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/presentation/intercom_controller.dart';
import '../../../../features/station/presentation/station_providers.dart';

class UnitIntercomBar extends ConsumerStatefulWidget {
  const UnitIntercomBar({super.key, required this.unitId});

  final int unitId;

  @override
  ConsumerState<UnitIntercomBar> createState() => _UnitIntercomBarState();
}

class _UnitIntercomBarState extends ConsumerState<UnitIntercomBar>
    with SingleTickerProviderStateMixin {
  static const Color _talk = Color(0xFF4A7FA7);
  static const Color _talkBg = Color(0xFFE6EFF6);
  static const Color _listen = Color(0xFF2E9E5B);
  static const Color _listenBg = Color(0xFFE1F2E7);

  late final AnimationController _wave;
  bool _live = false;
  bool _canPress = false;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  void _setLive(bool live) {
    if (live == _live) {
      return;
    }
    _live = live;
    if (live) {
      if (!_wave.isAnimating) {
        _wave.repeat();
      }
      return;
    }
    _wave.stop();
    _wave.value = 0;
  }

  void _beginTalk() {
    if (!_canPress) {
      return;
    }
    ref.read(intercomControllerProvider.notifier).beginTalk(widget.unitId);
  }

  void _endTalk() {
    if (!mounted) {
      return;
    }
    ref.read(intercomControllerProvider.notifier).endTalk(widget.unitId);
  }

  double _barScale(int index) {
    if (!_live) {
      return 0.18;
    }
    final double phase = (_wave.value + (index * 0.09)) % 1;
    final double crest = phase < 0.5 ? phase / 0.5 : (1 - phase) / 0.5;
    return 0.18 + (0.82 * crest);
  }

  String _clock(DateTime? started) {
    if (!_live || started == null) {
      return '0:00';
    }
    final int secs = DateTime.now().difference(started).inSeconds;
    final int minutes = secs ~/ 60;
    final int remain = secs % 60;
    return '$minutes:${remain.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool online = ref.watch(
      stationControllerProvider.select(
        (StationState station) => station.endpoint(widget.unitId).connected,
      ),
    );
    final IntercomState voice = ref.watch(intercomControllerProvider);
    final String? helperName = helperOnUnit(
      ref.watch(helperRosterProvider),
      widget.unitId,
    )?.name.trim();
    final String who = (helperName == null || helperName.isEmpty)
        ? 'Helper'
        : helperName;
    final bool talking =
        online &&
        voice.phase == IntercomPhase.talk &&
        voice.unitId == widget.unitId;
    final bool listening =
        online &&
        voice.phase == IntercomPhase.listen &&
        voice.unitId == widget.unitId;
    final bool live = talking || listening;
    _canPress = online && !listening;
    if (live != _live) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _setLive(live);
        }
      });
    }

    final Color accent = listening ? _listen : _talk;
    final Color background = talking
        ? _talkBg
        : listening
        ? _listenBg
        : tokens.canvas;
    final Color border = live ? accent : tokens.line;
    final String title = talking
        ? 'Speaking to helper…'
        : listening
        ? 'Helper speaking…'
        : 'Hold to talk';
    final String subtitle = !online
        ? 'Unit offline'
        : talking
        ? 'You · release to stop'
        : listening
        ? 'Wait to reply'
        : '$who · Unit ${widget.unitId}';

    return Opacity(
      opacity: online ? 1 : 0.55,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _wave,
                    builder: (BuildContext context, Widget? child) {
                      if (!_live) {
                        return const SizedBox.shrink();
                      }
                      final double t = _wave.value;
                      return Transform.scale(
                        scale: 1 + (0.9 * t),
                        child: Opacity(
                          opacity: 0.45 * (1 - t),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                            ),
                            child: const SizedBox(width: 44, height: 44),
                          ),
                        ),
                      );
                    },
                  ),
                  MouseRegion(
                    cursor: listening
                        ? SystemMouseCursors.forbidden
                        : online
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: _canPress
                          ? (DragDownDetails details) => _beginTalk()
                          : null,
                      onPanEnd: (DragEndDetails details) => _endTalk(),
                      onPanCancel: _endTalk,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 150),
                        scale: talking ? 0.95 : 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: live ? accent : tokens.card,
                            border: Border.all(
                              color: live ? accent : tokens.line,
                            ),
                          ),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.mic_none,
                              size: 20,
                              color: live ? Colors.white : tokens.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: tokens.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.good,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: tokens.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _wave,
              builder: (BuildContext context, Widget? child) {
                final Color bar = live ? accent : tokens.inkMuted;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: 24,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          for (int i = 0; i < 16; i++)
                            Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  width: 3,
                                  height: 24 * _barScale(i),
                                  decoration: BoxDecoration(
                                    color: bar.withValues(
                                      alpha: live ? 1 : 0.35,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      child: Text(
                        _clock(voice.startedAt),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 11,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          color: tokens.inkMuted,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
