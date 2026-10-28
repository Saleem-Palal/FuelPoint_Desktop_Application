import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../features/station/presentation/intercom_test_controller.dart';

/// Walkie-talkie bench for one ESP32. Compiled into the sidebar only in debug.
class IntercomTestScreen extends ConsumerStatefulWidget {
  const IntercomTestScreen({super.key});

  @override
  ConsumerState<IntercomTestScreen> createState() => _IntercomTestScreenState();
}

class _IntercomTestScreenState extends ConsumerState<IntercomTestScreen> {
  final TextEditingController _ssid = TextEditingController(
    text: 'WalkieTalkie',
  );
  final TextEditingController _password = TextEditingController(
    text: 'talk1234',
  );
  final TextEditingController _host = TextEditingController(
    text: '192.168.4.1',
  );
  final FocusNode _ssidFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _hostFocus = FocusNode();
  bool _revealPassword = false;
  final List<String> _clips = <String>[];

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    _host.dispose();
    _ssidFocus.dispose();
    _passwordFocus.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  bool get _typing =>
      _ssidFocus.hasFocus || _passwordFocus.hasFocus || _hostFocus.hasFocus;

  Future<void> _addMp3() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose MP3 files for the ESP speaker',
      type: FileType.custom,
      allowedExtensions: const <String>['mp3'],
    );
    if (!mounted || picked.isEmpty) {
      return;
    }
    setState(() {
      for (final PlatformFile file in picked) {
        final String? path = file.path;
        if (path != null && path.isNotEmpty && !_clips.contains(path)) {
          _clips.add(path);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }
    final DispensrTokens tokens = DispensrTokens.of(context);
    final IntercomTestState state = ref.watch(intercomTestControllerProvider);
    final IntercomTestController controller = ref.read(
      intercomTestControllerProvider.notifier,
    );
    final bool busy = state.link == IntercomTestLink.joining;
    final bool live = state.link == IntercomTestLink.live;

    return ColoredBox(
      color: tokens.canvas,
      child: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event.logicalKey != LogicalKeyboardKey.space || _typing) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) {
            controller.beginTalk();
          } else if (event is KeyUpEvent) {
            controller.endTalk();
          }
          return KeyEventResult.handled;
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const AppScreenHeader(
              title: 'Intercom Test',
              icon: Icons.settings_voice_outlined,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'Debug only. This PC joins the ESP access point and '
                          'talks half-duplex. Hold here to speak on the box '
                          'speaker. The microphone uses the same Windows voice '
                          'processing as the walkie-talkie page. Hold the box '
                          'button to speak on this PC.',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 14,
                            height: 1.4,
                            color: tokens.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Panel(
                          tokens: tokens,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                'ESP Wi-Fi',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: tokens.ink,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _Field(
                                label: 'Wi-Fi name',
                                controller: _ssid,
                                focusNode: _ssidFocus,
                                enabled: !busy && !live,
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: 'Password',
                                controller: _password,
                                focusNode: _passwordFocus,
                                enabled: !busy && !live,
                                obscure: !_revealPassword,
                                suffix: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _revealPassword = !_revealPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _revealPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: tokens.inkMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: 'ESP address',
                                controller: _host,
                                focusNode: _hostFocus,
                                enabled: !busy && !live,
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () {
                                              if (live) {
                                                unawaited(
                                                  controller.disconnect(),
                                                );
                                                return;
                                              }
                                              unawaited(
                                                controller.connect(
                                                  ssid: _ssid.text,
                                                  password: _password.text,
                                                  host: _host.text,
                                                ),
                                              );
                                            },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: live
                                            ? tokens.bad
                                            : tokens.coral,
                                        foregroundColor: tokens.card,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            tokens.radius12,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        busy
                                            ? 'Connecting…'
                                            : live
                                            ? 'Disconnect'
                                            : 'Connect',
                                        style: const TextStyle(
                                          fontFamily: 'Roboto',
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                state.status,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.35,
                                  color: _statusColor(tokens, state.link),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Panel(
                          tokens: tokens,
                          child: Column(
                            children: <Widget>[
                              _LevelSlider(
                                label: 'Mic',
                                hint: 'ESP microphone boost',
                                value: state.mic,
                                onChanged: controller.setMic,
                              ),
                              _LevelSlider(
                                label: 'Speaker',
                                hint: 'Same as the walkie page. 100 is full level',
                                value: state.speaker,
                                max: 150,
                                onChanged: controller.setSpeaker,
                              ),
                              _LevelSlider(
                                label: 'Noise cut',
                                hint: 'Box microphone only',
                                value: state.noiseCut,
                                onChanged: controller.setNoiseCut,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _TalkButton(
                          tokens: tokens,
                          enabled: live && !state.hearing,
                          talking: state.talking,
                          hearing: state.hearing,
                          onDown: controller.beginTalk,
                          onUp: controller.endTalk,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Space holds talk while a text field is not focused.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12,
                            color: tokens.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: live
                                    ? controller.swapMicChannel
                                    : null,
                                child: const Text('Swap mic channel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HoldOutlineButton(
                                enabled: live,
                                holding: state.micOnSpeaker,
                                idleLabel: 'Test mic on speaker',
                                heldLabel: 'Listening…',
                                onDown: controller.beginBoxLoop,
                                onUp: controller.endBoxLoop,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _Panel(
                          tokens: tokens,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                'Speaker file',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: tokens.ink,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Plays an MP3 on the ESP speaker with no '
                                'microphone processing. A clean file here means '
                                'the amplifier is fine. The Speaker slider is '
                                'the only volume.',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 13,
                                  height: 1.35,
                                  color: tokens.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: <Widget>[
                                  OutlinedButton.icon(
                                    onPressed: _addMp3,
                                    icon: const Icon(Icons.audio_file_outlined),
                                    label: const Text('Add MP3'),
                                  ),
                                  const SizedBox(width: 10),
                                  if (state.clipPath.isNotEmpty)
                                    TextButton(
                                      onPressed: controller.stopClip,
                                      child: const Text('Stop'),
                                    ),
                                ],
                              ),
                              if (_clips.isEmpty) ...<Widget>[
                                const SizedBox(height: 10),
                                Text(
                                  'No MP3 added yet.',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 13,
                                    color: tokens.inkMuted,
                                  ),
                                ),
                              ] else
                                const SizedBox(height: 8),
                              for (final String path in _clips)
                                _ClipRow(
                                  tokens: tokens,
                                  name: _fileName(path),
                                  playing: state.clipPath == path,
                                  enabled: live && state.clipPath != path,
                                  onPlay: () => controller.playClip(path),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'On a 5 V supply with USB unplugged, the ESP LED '
                          'flashes three times, then blinks until this PC '
                          'connects. No flashes means the board is held in '
                          'reset by the unpowered USB-serial chip. Power it '
                          'through the USB socket, or add 10 µF from EN to GND.',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12,
                            height: 1.4,
                            color: tokens.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fileName(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int slash = normalized.lastIndexOf('/');
    return slash < 0 ? path : normalized.substring(slash + 1);
  }

  Color _statusColor(DispensrTokens tokens, IntercomTestLink link) {
    switch (link) {
      case IntercomTestLink.live:
        return tokens.good;
      case IntercomTestLink.joining:
        return tokens.warn;
      case IntercomTestLink.failed:
        return tokens.bad;
      case IntercomTestLink.idle:
        return tokens.ink;
    }
  }
}

class _ClipRow extends StatelessWidget {
  const _ClipRow({
    required this.tokens,
    required this.name,
    required this.playing,
    required this.enabled,
    required this.onPlay,
  });

  final DispensrTokens tokens;
  final String name;
  final bool playing;
  final bool enabled;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(
            playing ? Icons.volume_up_rounded : Icons.music_note_rounded,
            size: 18,
            color: playing ? tokens.coral : tokens.inkMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: playing ? FontWeight.w700 : FontWeight.w500,
                color: tokens.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: enabled ? onPlay : null,
            child: Text(playing ? 'Playing' : 'Play'),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.tokens, required this.child});

  final DispensrTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    this.obscure = false,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscure,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w600,
        color: tokens.ink,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: tokens.inkMuted, fontFamily: 'Roboto'),
        suffixIcon: suffix,
        filled: true,
        fillColor: tokens.canvas,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
          borderSide: BorderSide(color: tokens.line),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
          borderSide: BorderSide(color: tokens.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
          borderSide: BorderSide(color: tokens.coral, width: 1.4),
        ),
      ),
    );
  }
}

class _LevelSlider extends StatelessWidget {
  const _LevelSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.max = 100,
  });

  final String label;
  final String hint;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
                    color: tokens.inkMuted,
                  ),
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(0, max).toDouble(),
            min: 0,
            max: max.toDouble(),
            divisions: max,
            activeColor: tokens.coral,
            label: '$value',
            onChanged: (double next) => onChanged(next.round()),
          ),
        ],
      ),
    );
  }
}

class _TalkButton extends StatelessWidget {
  const _TalkButton({
    required this.tokens,
    required this.enabled,
    required this.talking,
    required this.hearing,
    required this.onDown,
    required this.onUp,
  });

  final DispensrTokens tokens;
  final bool enabled;
  final bool talking;
  final bool hearing;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final Color fill = !enabled && !hearing
        ? tokens.line
        : talking
        ? tokens.bad
        : hearing
        ? tokens.good
        : tokens.coral;
    final String caption = talking
        ? 'TALKING'
        : hearing
        ? 'BOX IS TALKING'
        : 'HOLD TO TALK';
    return Center(
      child: GestureDetector(
        onPanDown: enabled ? (_) => onDown() : null,
        onPanStart: enabled ? (_) {} : null,
        onPanUpdate: enabled ? (_) {} : null,
        onPanEnd: enabled ? (_) => onUp() : null,
        onPanCancel: enabled ? onUp : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 240,
          height: 240,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            boxShadow: enabled ? tokens.cardShadow : const <BoxShadow>[],
          ),
          child: Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 0.6,
              color: enabled || hearing ? tokens.card : tokens.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldOutlineButton extends StatelessWidget {
  const _HoldOutlineButton({
    required this.enabled,
    required this.holding,
    required this.idleLabel,
    required this.heldLabel,
    required this.onDown,
    required this.onUp,
  });

  final bool enabled;
  final bool holding;
  final String idleLabel;
  final String heldLabel;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color ink = enabled ? tokens.ink : tokens.inkMuted;
    return GestureDetector(
      onPanDown: enabled ? (_) => onDown() : null,
      onPanStart: enabled ? (_) {} : null,
      onPanUpdate: enabled ? (_) {} : null,
      onPanEnd: enabled ? (_) => onUp() : null,
      onPanCancel: enabled ? onUp : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: holding ? tokens.blush : tokens.card,
          borderRadius: BorderRadius.circular(tokens.radius12),
          border: Border.all(color: enabled ? tokens.coral : tokens.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text(
            holding ? heldLabel : idleLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}
