import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/onboarding_provider.dart';

/// First-run industrial setup. Station metadata + owner Google identity.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPalette {
  static const Color background = Color(0xFF12181F);
  static const Color card = Color(0xFF1E2631);
  static const Color accent = Color(0xFF007ACC);
  static const Color success = Color(0xFF28A745);
  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF9AA6B4);
  static const Color fieldFill = Color(0xFF161D26);
  static const Color fieldBorder = Color(0xFF2C3644);
  static const Color disabled = Color(0xFF3A4553);
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _stationName = TextEditingController();
  final TextEditingController _contactNo = TextEditingController();
  final FocusNode _stationFocus = FocusNode();
  final FocusNode _contactFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _stationName.addListener(_onFieldsChanged);
    _contactNo.addListener(_onFieldsChanged);
  }

  @override
  void dispose() {
    _stationName.removeListener(_onFieldsChanged);
    _contactNo.removeListener(_onFieldsChanged);
    _stationName.dispose();
    _contactNo.dispose();
    _stationFocus.dispose();
    _contactFocus.dispose();
    super.dispose();
  }

  void _onFieldsChanged() {
    setState(() {});
  }

  bool _canComplete(OnboardingState onboarding) {
    return _stationName.text.trim().length >= 2 &&
        _contactNo.text.replaceAll(RegExp(r'\D'), '').length >= 7 &&
        onboarding.isGoogleAuthenticated &&
        !onboarding.busy;
  }

  void _signIn() {
    ref.read(onboardingProvider.notifier).deferGoogleAccountLink();
    _snack('google account link will be setup later');
  }

  Future<void> _complete() async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final bool ok = await ref
        .read(onboardingProvider.notifier)
        .completeOnboarding(
          stationName: _stationName.text,
          contactNo: _contactNo.text,
        );
    if (!mounted) {
      return;
    }
    if (!ok) {
      final String? error = ref.read(onboardingProvider).errorMessage;
      _snack(error ?? 'Could not finish station setup.');
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/managers', (_) => false);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2C3644),
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Roboto', color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OnboardingState onboarding = ref.watch(onboardingProvider);

    ref.listen<OnboardingState>(onboardingProvider, (
      OnboardingState? previous,
      OnboardingState next,
    ) {
      final String? error = next.errorMessage;
      if (error != null && error != previous?.errorMessage) {
        _snack(error);
      }
    });

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_canComplete(onboarding)) {
            unawaited(_complete());
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _OnboardingPalette.background,
          body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stacked = constraints.maxWidth < 980;
              final Widget brand = const _BrandPane();
              final Widget form = _SetupPane(
                formKey: _formKey,
                stationName: _stationName,
                contactNo: _contactNo,
                stationFocus: _stationFocus,
                contactFocus: _contactFocus,
                onboarding: onboarding,
                canComplete: _canComplete(onboarding),
                onSignIn: _signIn,
                onSignOut: () {
                  unawaited(
                    ref.read(onboardingProvider.notifier).signOutGoogle(),
                  );
                },
                onComplete: () => unawaited(_complete()),
              );
              if (stacked) {
                return Column(
                  children: <Widget>[
                    SizedBox(
                      height: constraints.maxHeight * 0.34,
                      child: brand,
                    ),
                    Expanded(child: form),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  const Expanded(flex: 1, child: _BrandPane()),
                  Expanded(flex: 1, child: form),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BrandPane extends StatelessWidget {
  const _BrandPane();

  static const List<({IconData icon, String title, String body})> _features =
      <({IconData icon, String title, String body})>[
        (
          icon: Icons.settings_input_component_outlined,
          title: '5-Bay ESP32 Relay Integration & Keypad Control',
          body: 'Hardware handshake for live nozzle, pump, and keypad I/O.',
        ),
        (
          icon: Icons.precision_manufacturing_outlined,
          title: 'Full Double-Precision Accounting Engine',
          body: 'REAL liters and rupees — no rounding in the ledger path.',
        ),
        (
          icon: Icons.groups_outlined,
          title: 'Multi-Manager Shift & Cash Reconciliation',
          body: 'PIN-gated managers, OPEN shifts, and expected-vs-actual cash.',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _OnboardingPalette.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 36, 36, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight < 64
                    ? 0
                    : constraints.maxHeight - 64,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _OnboardingPalette.accent,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x66007ACC),
                                blurRadius: 22,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_gas_station,
                            color: _OnboardingPalette.text,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'FuelPoint Station OS',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 26,
                                    letterSpacing: 0.2,
                                    color: _OnboardingPalette.text,
                                  ),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Industrial dispenser control · RetroSoft',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: _OnboardingPalette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    const Text(
                      'SYSTEM SPECIFICATIONS',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        color: _OnboardingPalette.accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (int i = 0; i < _features.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: 14),
                      _SpecRow(
                        icon: _features[i].icon,
                        title: _features[i].title,
                        body: _features[i].body,
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2C3644)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'System Initialization Mode',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: _OnboardingPalette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0x1A007ACC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x33007ACC)),
          ),
          child: Icon(icon, size: 20, color: _OnboardingPalette.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.3,
                  color: _OnboardingPalette.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  height: 1.4,
                  color: _OnboardingPalette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetupPane extends StatelessWidget {
  const _SetupPane({
    required this.formKey,
    required this.stationName,
    required this.contactNo,
    required this.stationFocus,
    required this.contactFocus,
    required this.onboarding,
    required this.canComplete,
    required this.onSignIn,
    required this.onSignOut,
    required this.onComplete,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController stationName;
  final TextEditingController contactNo;
  final FocusNode stationFocus;
  final FocusNode contactFocus;
  final OnboardingState onboarding;
  final bool canComplete;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _OnboardingPalette.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                minHeight: constraints.maxHeight < 88
                    ? 0
                    : constraints.maxHeight - 60,
              ),
              child: IntrinsicHeight(
                child: Center(
                  child: Material(
                    color: _OnboardingPalette.card,
                    elevation: 12,
                    shadowColor: const Color(0x88000000),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const Text(
                              'Station Setup',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                                color: _OnboardingPalette.text,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Register this terminal, verify the owner Google account, '
                              'then launch FuelPoint.',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 13,
                                height: 1.4,
                                color: _OnboardingPalette.muted,
                              ),
                            ),
                            const SizedBox(height: 22),
                            const _SectionLabel(
                              index: '01',
                              title: 'Station Details',
                            ),
                            const SizedBox(height: 12),
                            _SetupField(
                              controller: stationName,
                              focusNode: stationFocus,
                              label: 'Station Name',
                              hint: 'Khan Fuel Station',
                              icon: Icons.storefront_outlined,
                              textInputAction: TextInputAction.next,
                              validator: (String? value) {
                                if ((value ?? '').trim().length < 2) {
                                  return 'Station name is required.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            _SetupField(
                              controller: contactNo,
                              focusNode: contactFocus,
                              label: 'Contact Number',
                              hint: '+92 300 1234567',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              validator: (String? value) {
                                final String digits = (value ?? '').replaceAll(
                                  RegExp(r'\D'),
                                  '',
                                );
                                if (digits.length < 7) {
                                  return 'Enter a valid contact number.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            const _SectionLabel(
                              index: '02',
                              title: 'Owner Authentication',
                            ),
                            const SizedBox(height: 12),
                            if (onboarding.isGoogleAuthenticated)
                              _AuthenticatedOwner(
                                name: onboarding.ownerName,
                                email: onboarding.isGoogleLinkDeferred
                                    ? 'google account link will be setup later'
                                    : onboarding.ownerEmail,
                                deferred: onboarding.isGoogleLinkDeferred,
                                busy: onboarding.busy,
                                onSignOut: onSignOut,
                              )
                            else
                              _GoogleSignInButton(
                                busy: onboarding.busy,
                                onPressed: onSignIn,
                              ),
                            const Spacer(),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 52,
                              child: FilledButton(
                                onPressed: canComplete ? onComplete : null,
                                style: ButtonStyle(
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith<Color>((
                                        Set<WidgetState> states,
                                      ) {
                                        if (states.contains(
                                          WidgetState.disabled,
                                        )) {
                                          return _OnboardingPalette.disabled;
                                        }
                                        if (states.contains(
                                              WidgetState.hovered,
                                            ) ||
                                            states.contains(
                                              WidgetState.pressed,
                                            )) {
                                          return const Color(0xFF218838);
                                        }
                                        return _OnboardingPalette.success;
                                      }),
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith<Color>((
                                        Set<WidgetState> states,
                                      ) {
                                        if (states.contains(
                                          WidgetState.disabled,
                                        )) {
                                          return _OnboardingPalette.muted;
                                        }
                                        return _OnboardingPalette.text;
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
                                child: onboarding.busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: _OnboardingPalette.text,
                                        ),
                                      )
                                    : const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'Complete Setup & Launch System',
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.index, required this.title});

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
            color: _OnboardingPalette.accent,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: _OnboardingPalette.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFF2C3644), height: 1)),
      ],
    );
  }
}

class _SetupField extends StatelessWidget {
  const _SetupField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validator,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final OutlineInputBorder rest = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _OnboardingPalette.fieldBorder),
    );
    final OutlineInputBorder focus = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _OnboardingPalette.accent, width: 2),
    );
    final OutlineInputBorder error = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5533D), width: 1.4),
    );
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: keyboardType == TextInputType.phone
          ? TextCapitalization.none
          : TextCapitalization.words,
      style: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        color: _OnboardingPalette.text,
      ),
      cursorColor: _OnboardingPalette.accent,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _OnboardingPalette.muted, size: 20),
        filled: true,
        fillColor: _OnboardingPalette.fieldFill,
        labelStyle: const TextStyle(
          fontFamily: 'Roboto',
          color: _OnboardingPalette.muted,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Roboto',
          color: _OnboardingPalette.muted.withValues(alpha: 0.55),
        ),
        errorStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: rest,
        enabledBorder: rest,
        focusedBorder: focus,
        errorBorder: error,
        focusedErrorBorder: error.copyWith(
          borderSide: const BorderSide(color: Color(0xFFE5533D), width: 2),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatefulWidget {
  const _GoogleSignInButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? const Color(0xFFF7F8FA) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: widget.busy ? null : widget.onPressed,
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0x14007ACC),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered
                    ? _OnboardingPalette.accent
                    : const Color(0xFFD0D7DE),
                width: _hovered ? 1.6 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: widget.busy
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _OnboardingPalette.accent,
                      ),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _GoogleGLogo(size: 18),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Sign in with Google Account',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF1F1F1F),
                          ),
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

class _AuthenticatedOwner extends StatelessWidget {
  const _AuthenticatedOwner({
    required this.name,
    required this.email,
    required this.deferred,
    required this.busy,
    required this.onSignOut,
  });

  final String name;
  final String email;
  final bool deferred;
  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: const Color(0x1428A745),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x6628A745)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0x3328A745),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user,
              color: _OnboardingPalette.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x3328A745),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle,
                        size: 13,
                        color: _OnboardingPalette.success,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        deferred ? 'LINK LATER' : 'OWNER VERIFIED',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: _OnboardingPalette.success,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _OnboardingPalette.text,
                  ),
                ),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
                    color: _OnboardingPalette.muted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : onSignOut,
            child: const Text(
              'Change',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                color: _OnboardingPalette.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleGLogo extends StatelessWidget {
  const _GoogleGLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _GoogleGPainter());
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Offset c = Offset(s / 2, s / 2);
    final double stroke = s * 0.18;
    final Rect ring = Rect.fromCircle(center: c, radius: s / 2 - stroke / 2);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(ring, -0.35, 1.7, false, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(ring, 1.35, 0.95, false, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(ring, 2.3, 0.75, false, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(ring, 3.05, 0.95, false, paint);

    final Paint bar = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - stroke / 2, s / 2 - stroke * 0.15, stroke),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
