import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/pin_hasher.dart';
import '../providers/auth_provider.dart';

/// Touchscreen PIN unlock for the station terminal.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginPalette {
  static const Color background = Color(0xFF12181F);
  static const Color card = Color(0xFF1E2631);
  static const Color accent = Color(0xFF007ACC);
  static const Color success = Color(0xFF28A745);
  static const Color alert = Color(0xFFDC3545);
  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF9AA6B4);
  static const Color fieldFill = Color(0xFF161D26);
  static const Color fieldBorder = Color(0xFF2C3644);
  static const Color keyFill = Color(0xFF2A3441);
  static const Color disabled = Color(0xFF3A4553);
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _pin = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _pin.addListener(_onPinChanged);
    Future<void>(() {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(authProvider.notifier).bootstrap());
      _pinFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _pin.removeListener(_onPinChanged);
    _pin.dispose();
    _pinFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _onPinChanged() {
    setState(() {});
  }

  String get _pinValue => _pin.text.trim();

  bool _canSubmit(AuthState auth) {
    return auth.selectedManagerId != null &&
        PinHasher.isValidPlainPin(_pinValue) &&
        !auth.busy &&
        auth.managers.isNotEmpty;
  }

  void _appendDigit(String digit) {
    if (authBusy) {
      return;
    }
    if (_pin.text.length >= PinHasher.maxPinLength) {
      return;
    }
    _pin.text = '${_pin.text}$digit';
    _pin.selection = TextSelection.collapsed(offset: _pin.text.length);
  }

  bool get authBusy => ref.read(authProvider).busy;

  void _backspace() {
    if (authBusy || _pin.text.isEmpty) {
      return;
    }
    _pin.text = _pin.text.substring(0, _pin.text.length - 1);
    _pin.selection = TextSelection.collapsed(offset: _pin.text.length);
  }

  void _clearPin() {
    if (authBusy) {
      return;
    }
    _pin.clear();
  }

  Future<void> _submit() async {
    final AuthState auth = ref.read(authProvider);
    final String? managerId = auth.selectedManagerId;
    if (managerId == null || !_canSubmit(auth)) {
      return;
    }
    final bool ok = await ref
        .read(authProvider.notifier)
        .authenticateManager(managerId, _pinValue);
    if (!mounted) {
      return;
    }
    if (!ok) {
      _clearPin();
      _pinFocus.requestFocus();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/sale', (_) => false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (_pinFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_submit());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.escape) {
      _clearPin();
      return KeyEventResult.handled;
    }
    final String? digit = _digitOf(key);
    if (digit != null) {
      _appendDigit(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String? _digitOf(LogicalKeyboardKey key) {
    final Map<LogicalKeyboardKey, String> keys = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
    };
    return keys[key];
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authProvider);

    return Focus(
      autofocus: true,
      focusNode: _keyboardFocus,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: _LoginPalette.background,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 860;
            return ColoredBox(
              color: _LoginPalette.background,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wide ? 920 : 480,
                      minHeight: constraints.maxHeight < 720
                          ? 0
                          : constraints.maxHeight - 56,
                    ),
                    child: Center(
                      child: _LoginCard(
                        auth: auth,
                        pin: _pin,
                        pinFocus: _pinFocus,
                        wide: wide,
                        canSubmit: _canSubmit(auth),
                        onSelectManager: (String id) {
                          ref.read(authProvider.notifier).selectManager(id);
                          _clearPin();
                          _pinFocus.requestFocus();
                        },
                        onDigit: _appendDigit,
                        onBackspace: _backspace,
                        onClear: _clearPin,
                        onSubmit: () => unawaited(_submit()),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.auth,
    required this.pin,
    required this.pinFocus,
    required this.wide,
    required this.canSubmit,
    required this.onSelectManager,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  final AuthState auth;
  final TextEditingController pin;
  final FocusNode pinFocus;
  final bool wide;
  final bool canSubmit;
  final ValueChanged<String> onSelectManager;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final Widget form = _LoginForm(
      auth: auth,
      pin: pin,
      pinFocus: pinFocus,
      onSelectManager: onSelectManager,
      onSubmit: onSubmit,
    );
    final Widget keypad = _PinKeypad(
      enabled: !auth.busy,
      onDigit: onDigit,
      onBackspace: onBackspace,
      onClear: onClear,
      onSubmit: canSubmit ? onSubmit : null,
    );

    return Material(
      color: _LoginPalette.card,
      elevation: 16,
      shadowColor: const Color(0x99000000),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 22, 28, wide ? 32 : 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _StationHeader(),
            const SizedBox(height: 22),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 6, child: form),
                  const SizedBox(width: 28),
                  Expanded(flex: 5, child: keypad),
                ],
              )
            else ...<Widget>[form, const SizedBox(height: 20), keypad],
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: canSubmit ? onSubmit : null,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>((
                    Set<WidgetState> states,
                  ) {
                    if (states.contains(WidgetState.disabled)) {
                      return _LoginPalette.disabled;
                    }
                    if (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.pressed)) {
                      return const Color(0xFF218838);
                    }
                    return _LoginPalette.success;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color>((
                    Set<WidgetState> states,
                  ) {
                    if (states.contains(WidgetState.disabled)) {
                      return _LoginPalette.muted;
                    }
                    return _LoginPalette.text;
                  }),
                  overlayColor: WidgetStateProperty.all(
                    const Color(0x22FFFFFF),
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                child: auth.busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: _LoginPalette.text,
                        ),
                      )
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Login / Unlock System',
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.3,
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
}

class _StationHeader extends ConsumerWidget {
  const _StationHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authProvider);
    final String station = auth.stationName.trim().isEmpty
        ? 'FuelPoint Station OS'
        : auth.stationName.trim();
    final String contact = auth.contactNo.trim();
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _LoginPalette.accent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66007ACC),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.lock_open_rounded,
            color: _LoginPalette.text,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  station,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: _LoginPalette.text,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                contact.isEmpty
                    ? 'Manager PIN required to unlock the terminal'
                    : contact,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: _LoginPalette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.auth,
    required this.pin,
    required this.pinFocus,
    required this.onSelectManager,
    required this.onSubmit,
  });

  final AuthState auth;
  final TextEditingController pin;
  final FocusNode pinFocus;
  final ValueChanged<String> onSelectManager;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _FieldLabel(index: '01', title: 'On-Duty Manager'),
        const SizedBox(height: 10),
        if (auth.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: _LoginPalette.accent,
                ),
              ),
            ),
          )
        else if (auth.managers.isEmpty)
          const _InlineBanner(
            color: _LoginPalette.alert,
            icon: Icons.person_off_outlined,
            message:
                'No managers are registered. Complete setup and add the first manager account.',
          )
        else ...<Widget>[
          _ManagerDropdown(auth: auth, onSelect: onSelectManager),
          const SizedBox(height: 10),
          _ManagerCards(auth: auth, onSelect: onSelectManager),
        ],
        const SizedBox(height: 18),
        const _FieldLabel(index: '02', title: 'Manager PIN'),
        const SizedBox(height: 10),
        TextField(
          controller: pin,
          focusNode: pinFocus,
          obscureText: true,
          obscuringCharacter: '•',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(PinHasher.maxPinLength),
          ],
          onSubmitted: (_) => onSubmit(),
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: 10,
            color: _LoginPalette.text,
          ),
          decoration: InputDecoration(
            hintText: '••••',
            hintStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 28,
              letterSpacing: 10,
              color: _LoginPalette.muted.withValues(alpha: 0.45),
            ),
            prefixIcon: const Icon(
              Icons.pin_outlined,
              color: _LoginPalette.muted,
            ),
            filled: true,
            fillColor: _LoginPalette.fieldFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _LoginPalette.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: _LoginPalette.accent,
                width: 2,
              ),
            ),
          ),
        ),
        if (auth.errorMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          _InlineBanner(
            color: _LoginPalette.alert,
            icon: Icons.error_outline,
            message: auth.failedAttempts > 1
                ? '${auth.errorMessage}  (${auth.failedAttempts} attempts)'
                : auth.errorMessage!,
          ),
        ],
      ],
    );
  }
}

class _ManagerDropdown extends StatelessWidget {
  const _ManagerDropdown({required this.auth, required this.onSelect});

  final AuthState auth;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final String? selected = auth.selectedManagerId;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      dropdownColor: _LoginPalette.card,
      iconEnabledColor: _LoginPalette.muted,
      style: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        color: _LoginPalette.text,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: _LoginPalette.fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _LoginPalette.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _LoginPalette.accent, width: 2),
        ),
      ),
      items: <DropdownMenuItem<String>>[
        for (final AuthManager manager in auth.managers)
          DropdownMenuItem<String>(
            value: manager.id,
            child: Text(
              '${manager.name}  ·  ${manager.id}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: auth.busy
          ? null
          : (String? id) {
              if (id != null) {
                onSelect(id);
              }
            },
    );
  }
}

class _ManagerCards extends StatelessWidget {
  const _ManagerCards({required this.auth, required this.onSelect});

  final AuthState auth;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final AuthManager manager in auth.managers)
          _ManagerChip(
            manager: manager,
            selected: manager.id == auth.selectedManagerId,
            onTap: auth.busy ? null : () => onSelect(manager.id),
          ),
      ],
    );
  }
}

class _ManagerChip extends StatefulWidget {
  const _ManagerChip({
    required this.manager,
    required this.selected,
    required this.onTap,
  });

  final AuthManager manager;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_ManagerChip> createState() => _ManagerChipState();
}

class _ManagerChipState extends State<_ManagerChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: selected
            ? const Color(0x33007ACC)
            : _hovered
            ? const Color(0xFF252E3A)
            : _LoginPalette.fieldFill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0x14007ACC),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? _LoginPalette.accent
                    : _LoginPalette.fieldBorder,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: selected
                      ? _LoginPalette.accent
                      : _LoginPalette.keyFill,
                  child: Text(
                    widget.manager.initials,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: _LoginPalette.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.manager.name,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected ? _LoginPalette.text : _LoginPalette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback? onSubmit;

  static const List<List<String>> _rows = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
    <String>['7', '8', '9'],
    <String>['C', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int r = 0; r < _rows.length; r++) ...<Widget>[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (int c = 0; c < 3; c++) ...<Widget>[
                if (c > 0) const SizedBox(width: 8),
                Expanded(
                  child: _KeypadKey(
                    label: _rows[r][c],
                    enabled: enabled,
                    onPressed: () {
                      final String label = _rows[r][c];
                      if (label == 'C') {
                        onClear();
                      } else if (label == '⌫') {
                        onBackspace();
                      } else {
                        onDigit(label);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled ? onSubmit : null,
            icon: const Icon(Icons.keyboard_return, size: 18),
            label: const Text(
              'Submit',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.disabled)) {
                  return _LoginPalette.disabled;
                }
                return _LoginPalette.accent;
              }),
              foregroundColor: WidgetStateProperty.all(_LoginPalette.text),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeypadKey extends StatefulWidget {
  const _KeypadKey({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_KeypadKey> createState() => _KeypadKeyState();
}

class _KeypadKeyState extends State<_KeypadKey> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool action = widget.label == 'C' || widget.label == '⌫';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: !widget.enabled
            ? _LoginPalette.disabled
            : action
            ? const Color(0xFF3A2A2E)
            : _hovered
            ? const Color(0xFF354050)
            : _LoginPalette.keyFill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: widget.enabled ? widget.onPressed : null,
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0x14007ACC),
          child: SizedBox(
            height: 58,
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: widget.label == '⌫' ? 20 : 22,
                  color: action ? const Color(0xFFFFB4B4) : _LoginPalette.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.index, required this.title});

  final String index;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          index,
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.4,
            color: _LoginPalette.accent,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: _LoginPalette.muted,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFF2C3644), height: 1)),
      ],
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.35,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
