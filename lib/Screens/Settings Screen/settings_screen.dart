import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/fuel_point_stat_card.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../features/access/presentation/master_pin_settings_card.dart';
import '../../features/shift/presentation/shift_providers.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/purchase_providers.dart';
import '../../features/station/presentation/station_providers.dart';
import '../../providers/managers_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/database_helper.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Timer? _metricsClock;

  @override
  void initState() {
    super.initState();
    _metricsClock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(settingsProvider.notifier).fetchDatabaseMetrics());
    });
  }

  @override
  void dispose() {
    _metricsClock?.cancel();
    super.dispose();
  }

  Future<void> _exportBackup() async {
    final String? directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Export FuelPoint backup',
    );
    if (directory == null || !mounted) {
      return;
    }
    await ref.read(settingsProvider.notifier).createLocalBackup(directory);
  }

  Future<void> _restoreBackup() async {
    final int openCount = ref.read(shiftWorkspaceProvider).activeShift == null
        ? 0
        : 1;
    if (openCount > 0) {
      await _showMessageDialog(
        title: 'Open shift on duty',
        body:
            'Close the live OPEN shift before restoring a database snapshot. '
            'Restoring now would replace cash, stock, and sales mid-shift.',
      );
      return;
    }
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: 'Restore FuelPoint database',
      type: FileType.custom,
      allowedExtensions: const <String>['db'],
    );
    if (picked == null || !mounted) {
      return;
    }
    final String? path = picked.path;
    if (path == null || path.isEmpty) {
      return;
    }
    final bool? confirmed = await _confirmRestore(path);
    if (confirmed != true || !mounted) {
      return;
    }
    final bool ok = await ref
        .read(settingsProvider.notifier)
        .restoreDatabase(path);
    if (!ok || !mounted) {
      return;
    }
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    await ref.read(shiftWorkspaceProvider.notifier).reload();
    await ref.read(managersProvider.notifier).reload();
  }

  Future<void> _eraseTables() async {
    final List<StationTableInfo> tables = await ref
        .read(settingsProvider.notifier)
        .listDatabaseTables();
    if (!mounted) {
      return;
    }
    if (tables.isEmpty) {
      await _showMessageDialog(
        title: 'No tables found',
        body: 'SQLite did not report any user tables to erase.',
      );
      return;
    }
    final Set<String>? selected = await showDialog<Set<String>>(
      context: context,
      builder: (BuildContext context) {
        return _EraseTablesDialog(
          tables: tables,
          hasOpenShift: ref.read(shiftWorkspaceProvider).activeShift != null,
        );
      },
    );
    if (selected == null || selected.isEmpty || !mounted) {
      return;
    }
    final bool ok = await ref
        .read(settingsProvider.notifier)
        .truncateSelectedTables(selected);
    if (!ok || !mounted) {
      return;
    }
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    await ref.read(stationControllerProvider.notifier).reloadPersistedData();
    await ref.read(purchaseControllerProvider).reload();
    await ref.read(shiftWorkspaceProvider.notifier).reload();
    await ref.read(managersProvider.notifier).reload();
  }

  Future<bool?> _confirmRestore(String path) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final DispensrTokens tokens = DispensrTokens.of(context);
        return AlertDialog(
          backgroundColor: tokens.card,
          surfaceTintColor: tokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius20),
            side: BorderSide(color: tokens.line),
          ),
          title: Text(
            'Restore database',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: tokens.ink,
            ),
          ),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                'Replace the live station database with this snapshot?\n\n$path\n\n'
                'This cannot be undone. Confirm there are no OPEN shifts.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13,
                  height: 1.4,
                  color: tokens.inkMuted,
                ),
              ),
            ),
          ),
          actions: <Widget>[
            DsPillButton(
              label: 'Cancel',
              variant: DsPillVariant.outline,
              compact: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            DsPillButton(
              label: 'Restore',
              variant: DsPillVariant.danger,
              compact: true,
              icon: Icons.restore,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMessageDialog({
    required String title,
    required String body,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final DispensrTokens tokens = DispensrTokens.of(context);
        return AlertDialog(
          backgroundColor: tokens.card,
          surfaceTintColor: tokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius20),
            side: BorderSide(color: tokens.line),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: tokens.ink,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              body,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 13,
                height: 1.4,
                color: tokens.inkMuted,
              ),
            ),
          ),
          actions: <Widget>[
            DsPillButton(
              label: 'OK',
              compact: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final SettingsState settings = ref.watch(settingsProvider);
    final ColorScheme colors = Theme.of(context).colorScheme;

    ref.listen<SettingsState>(settingsProvider, (
      SettingsState? previous,
      SettingsState next,
    ) {
      final String? error = next.errorMessage;
      if (error != null && error != previous?.errorMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
      final String? status = next.statusMessage;
      if (status != null && status != previous?.statusMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(status)));
      }
    });

    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppScreenHeader(
              title: 'Settings',
              icon: Icons.settings_outlined,
            ),
          ),
          if (settings.busy || settings.loading || settings.backingUp)
            LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: tokens.line,
              color: tokens.coral,
            )
          else
            const SizedBox(height: 3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget drive = _DriveCard(
                    settings: settings,
                    enabled: !settings.busy,
                  );
                  final Widget sqlite = _SqliteCard(
                    settings: settings,
                    enabled: !settings.busy,
                    onExport: _exportBackup,
                    onRestore: _restoreBackup,
                    onCheckpoint: () {
                      unawaited(
                        ref
                            .read(settingsProvider.notifier)
                            .executeWalCheckpoint(),
                      );
                    },
                    onOptimize: () {
                      unawaited(
                        ref.read(settingsProvider.notifier).optimizeDatabase(),
                      );
                    },
                    onErase: _eraseTables,
                  );
                  final Widget audit = SizedBox(
                    height: constraints.maxHeight < 640
                        ? 360
                        : constraints.maxHeight * 0.42,
                    child: _AuditCard(settings: settings),
                  );
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const MasterPinSettingsCard(),
                        const SizedBox(height: 10),
                        drive,
                        const SizedBox(height: 10),
                        sqlite,
                        const SizedBox(height: 10),
                        audit,
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (settings.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                settings.errorMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11,
                  color: colors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
    this.fillHeight = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Widget card = Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tokens.coral.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(tokens.radius12),
                  ),
                  child: Icon(icon, size: 18, color: tokens.coralPressed),
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
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: tokens.ink,
                        ),
                      ),
                      Text(
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
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: tokens.line),
          if (fillHeight) Expanded(child: child) else child,
        ],
      ),
    );
    return fillHeight ? SizedBox.expand(child: card) : card;
  }
}

class _DriveCard extends ConsumerStatefulWidget {
  const _DriveCard({required this.settings, required this.enabled});

  final SettingsState settings;
  final bool enabled;

  @override
  ConsumerState<_DriveCard> createState() => _DriveCardState();
}

class _DriveCardState extends ConsumerState<_DriveCard> {
  late final TextEditingController _clientId;
  late final TextEditingController _clientSecret;
  bool _showClientId = false;
  bool _showSecret = false;

  SettingsState get settings => widget.settings;

  bool get _actionsEnabled => widget.enabled && !settings.backingUp;

  @override
  void initState() {
    super.initState();
    _clientId = TextEditingController(text: settings.oauthClientId);
    _clientSecret = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant _DriveCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (settings.oauthClientId != oldWidget.settings.oauthClientId &&
        _clientId.text != settings.oauthClientId) {
      _clientId.text = settings.oauthClientId;
    }
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials(SettingsNotifier notifier) async {
    await notifier.saveOauthCredentials(
      clientId: _clientId.text,
      clientSecret: _clientSecret.text,
    );
    if (!mounted) {
      return;
    }
    if (ref.read(settingsProvider).hasOauthSecret) {
      _clientSecret.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final GoogleDriveAccount? account = settings.account;
    final bool connected = account != null;
    final SettingsNotifier notifier = ref.read(settingsProvider.notifier);
    final String email = account?.email ?? '';
    final String displayName = (account?.displayName ?? '').trim();
    final String statusLabel = connected
        ? 'Connected as $email'
        : 'Not Connected';
    final DateTime? lastBackupAt = settings.lastBackupAt;
    final String lastFile = (settings.lastBackupFileName ?? '').trim();

    return _SectionCard(
      title: 'Google Drive Sync & Cloud Storage',
      subtitle:
          'OAuth loopback sign-in, FuelPoint_Backups folder, and shift reports',
      icon: Icons.cloud_sync_outlined,
      trailing: DsStatusPill(
        label: connected ? 'Connected' : 'Not Connected',
        foreground: connected ? tokens.good : tokens.inkMuted,
        background: connected
            ? tokens.good.withValues(alpha: 0.12)
            : tokens.line.withValues(alpha: 0.6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: connected
                    ? tokens.good.withValues(alpha: 0.08)
                    : tokens.canvas,
                borderRadius: BorderRadius.circular(tokens.radius12),
                border: Border.all(
                  color: connected
                      ? tokens.good.withValues(alpha: 0.35)
                      : tokens.line,
                ),
              ),
              child: Row(
                children: <Widget>[
                  _AccountAvatar(account: account),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          connected
                              ? (displayName.isEmpty ? email : displayName)
                              : 'No Google account connected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: tokens.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12,
                            color: connected ? tokens.good : tokens.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'OAUTH CONFIGURATION',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 9,
                letterSpacing: 0.8,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Paste a Google Cloud Desktop client. Credentials stay in local '
              'station settings — never in the app installer.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                height: 1.35,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 10),
            _SecretField(
              controller: _clientId,
              label: 'Client ID',
              hint: 'xxxxx.apps.googleusercontent.com',
              obscure: !_showClientId,
              enabled: _actionsEnabled,
              onToggle: () {
                setState(() {
                  _showClientId = !_showClientId;
                });
              },
            ),
            const SizedBox(height: 8),
            _SecretField(
              controller: _clientSecret,
              label: 'Client Secret',
              hint: settings.hasOauthSecret
                  ? 'Saved on this station — enter a new secret to replace'
                  : 'GOCSPX-…',
              obscure: !_showSecret,
              enabled: _actionsEnabled,
              onToggle: () {
                setState(() {
                  _showSecret = !_showSecret;
                });
              },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: DsPillButton(
                label: 'Save Credentials',
                icon: Icons.save_outlined,
                variant: DsPillVariant.ink,
                onPressed: _actionsEnabled
                    ? () {
                        unawaited(_saveCredentials(notifier));
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                DsPillButton(
                  label: 'OAuth Sign In',
                  icon: Icons.login,
                  variant: DsPillVariant.ink,
                  onPressed: _actionsEnabled && settings.oauthConfigured
                      ? () {
                          unawaited(notifier.authenticateGoogleDrive());
                        }
                      : null,
                ),
                if (connected)
                  DsPillButton(
                    label: 'Disconnect / Sign Out',
                    icon: Icons.logout,
                    variant: DsPillVariant.outline,
                    onPressed: _actionsEnabled
                        ? () {
                            unawaited(notifier.signOutGoogleDrive());
                          }
                        : null,
                  ),
                DsPillButton(
                  label: settings.backingUp
                      ? 'Uploading…'
                      : 'Backup Database Now',
                  icon: Icons.cloud_upload_outlined,
                  onPressed: _actionsEnabled
                      ? () {
                          unawaited(notifier.uploadBackupToGoogleDrive());
                        }
                      : null,
                ),
                if (settings.backingUp)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: tokens.coral,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: tokens.line),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: settings.autoBackupOnShiftClose,
              activeThumbColor: tokens.good,
              onChanged: _actionsEnabled
                  ? (bool value) {
                      unawaited(notifier.setAutoBackupOnShiftClose(value));
                    }
                  : null,
              title: Text(
                'Auto-Backup on Shift Close',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: tokens.ink,
                ),
              ),
              subtitle: Text(
                'Uploads a timestamped snapshot and today’s shift reports after tally.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11,
                  color: tokens.inkMuted,
                ),
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              key: ValueKey<int>(settings.autoBackupIntervalHours),
              initialValue: settings.autoBackupIntervalHours,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Periodic Auto-Backup Interval',
              ),
              items: <DropdownMenuItem<int>>[
                for (final int hours in BackupIntervalHours.choices)
                  DropdownMenuItem<int>(
                    value: hours,
                    child: Text(BackupIntervalHours.label(hours)),
                  ),
              ],
              onChanged: _actionsEnabled
                  ? (int? value) {
                      if (value == null) {
                        return;
                      }
                      unawaited(notifier.setAutoBackupIntervalHours(value));
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.canvas,
                borderRadius: BorderRadius.circular(tokens.radius12),
                border: Border.all(color: tokens.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _BackupMetaRow(
                    label: 'Last Successful Backup',
                    value: lastBackupAt == null
                        ? 'Never'
                        : formatDateTime(lastBackupAt),
                  ),
                  const SizedBox(height: 8),
                  _BackupMetaRow(
                    label: 'Last Uploaded File',
                    value: lastFile.isEmpty ? '—' : lastFile,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecretField extends StatelessWidget {
  const _SecretField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscure,
    required this.enabled,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.visiblePassword,
      style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show' : 'Hide',
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

class _BackupMetaRow extends StatelessWidget {
  const _BackupMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 0.4,
            color: tokens.inkMuted,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: tokens.ink,
          ),
        ),
      ],
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account});

  final GoogleDriveAccount? account;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String? photo = account?.photoUrl;
    return CircleAvatar(
      radius: 26,
      backgroundColor: tokens.coral.withValues(alpha: 0.18),
      foregroundColor: tokens.coralPressed,
      backgroundImage: photo == null || photo.isEmpty
          ? null
          : NetworkImage(photo),
      child: photo == null || photo.isEmpty
          ? Text(
              account?.initials ?? 'G',
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            )
          : null,
    );
  }
}

class _SqliteCard extends StatelessWidget {
  const _SqliteCard({
    required this.settings,
    required this.enabled,
    required this.onExport,
    required this.onRestore,
    required this.onCheckpoint,
    required this.onOptimize,
    required this.onErase,
  });

  final SettingsState settings;
  final bool enabled;
  final VoidCallback onExport;
  final VoidCallback onRestore;
  final VoidCallback onCheckpoint;
  final VoidCallback onOptimize;
  final VoidCallback onErase;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final DatabaseMetrics? metrics = settings.metrics;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return _SectionCard(
      title: 'Local SQLite Health',
      subtitle: 'WAL checkpoints, vacuum, USB backup, restore and erase',
      icon: Icons.storage_outlined,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'DATABASE PATH',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 9,
                letterSpacing: 0.8,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              metrics?.dbPath ?? 'Resolving…',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 12,
                height: 1.35,
                color: tokens.ink,
              ),
            ),
            const SizedBox(height: 12),
            ExtentWrap(
              maxCrossAxisExtent: 280,
              children: <Widget>[
                FuelPointStatCard(
                  title: '.db size',
                  value: metrics?.dbSizeMbLabel ?? '—',
                  subtitle: 'Primary SQLite file',
                  icon: Icons.sd_storage_outlined,
                  badgeBackgroundColor: tokens.coral.withValues(alpha: 0.14),
                  badgeIconColor: tokens.coralPressed,
                ),
                FuelPointStatCard(
                  title: '.db-wal size',
                  value: metrics?.walSizeMbLabel ?? '—',
                  subtitle: 'Write-ahead log',
                  icon: Icons.pending_actions_outlined,
                  badgeBackgroundColor: tokens.warn.withValues(alpha: 0.16),
                  badgeIconColor: tokens.warn,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                DsPillButton(
                  label: 'Force WAL Checkpoint',
                  icon: Icons.merge_type,
                  variant: DsPillVariant.outline,
                  onPressed: enabled ? onCheckpoint : null,
                ),
                DsPillButton(
                  label: 'Optimize & Vacuum DB',
                  icon: Icons.auto_fix_high_outlined,
                  variant: DsPillVariant.ink,
                  onPressed: enabled ? onOptimize : null,
                ),
                DsPillButton(
                  label: 'Export Backup to USB / Directory',
                  icon: Icons.usb_outlined,
                  onPressed: enabled ? onExport : null,
                ),
                DsPillButton(
                  label: 'Restore Database',
                  icon: Icons.restore,
                  variant: DsPillVariant.danger,
                  onPressed: enabled ? onRestore : null,
                ),
                DsPillButton(
                  label: 'Reset / Erase Tables',
                  icon: Icons.delete_forever_outlined,
                  variant: DsPillVariant.danger,
                  onPressed: enabled ? onErase : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditCard extends ConsumerWidget {
  const _AuditCard({required this.settings});

  final SettingsState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String? filter = settings.actionFilter;
    return _SectionCard(
      title: 'System Audit Trail',
      subtitle: 'Station event log of operator and system actions',
      icon: Icons.fact_check_outlined,
      fillHeight: true,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: DropdownButtonFormField<String>(
              key: ValueKey<String>(filter ?? ''),
              initialValue: filter ?? '',
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Action type',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text(
                    'All actions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final String action in AuditActionType.filterOptions)
                  DropdownMenuItem<String>(
                    value: action,
                    child: Text(
                      action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (String? value) {
                unawaited(
                  ref
                      .read(settingsProvider.notifier)
                      .setAuditFilter(
                        value == null || value.isEmpty ? null : value,
                      ),
                );
              },
            ),
          ),
          Expanded(
            child: settings.auditLogs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        filter == null || filter.isEmpty
                            ? 'No audit events yet. Backups, WAL checkpoints, '
                                  'restores, and shift-close uploads appear here.'
                            : 'No $filter events recorded yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          color: tokens.inkMuted,
                        ),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final double minWidth = constraints.maxWidth < 960
                              ? 960
                              : constraints.maxWidth;
                          return _TwoAxisScroll(
                            minWidth: minWidth,
                            child: DataTable(
                              headingRowHeight: 32,
                              dataRowMinHeight: 40,
                              dataRowMaxHeight: 48,
                              headingRowColor: WidgetStatePropertyAll<Color>(
                                tokens.canvas,
                              ),
                              headingTextStyle: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 0.9,
                                color: tokens.inkMuted,
                              ),
                              dataTextStyle: const TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                              columns: const <DataColumn>[
                                DataColumn(label: Text('TIMESTAMP')),
                                DataColumn(label: Text('MANAGER ID')),
                                DataColumn(label: Text('ACTION TYPE')),
                                DataColumn(label: Text('DETAILS')),
                              ],
                              rows: <DataRow>[
                                for (final AuditLogEntry row
                                    in settings.auditLogs)
                                  DataRow(
                                    cells: <DataCell>[
                                      DataCell(
                                        Text(formatDateTime(row.timestamp)),
                                      ),
                                      DataCell(
                                        Text(
                                          row.managerId,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          row.actionType,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: tokens.coralPressed,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 420,
                                          child: Text(
                                            row.details,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: <Widget>[
                Text(
                  settings.auditTotal == 0
                      ? '0 events'
                      : 'Page ${settings.auditPage + 1} of ${settings.auditPageCount}  ·  ${settings.auditTotal} events',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 11,
                    color: tokens.inkMuted,
                  ),
                ),
                const Spacer(),
                DsPillButton(
                  label: 'Prev',
                  variant: DsPillVariant.outline,
                  compact: true,
                  onPressed: settings.canGoPrevAudit
                      ? () {
                          unawaited(
                            ref
                                .read(settingsProvider.notifier)
                                .goToAuditPage(settings.auditPage - 1),
                          );
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                DsPillButton(
                  label: 'Next',
                  variant: DsPillVariant.outline,
                  compact: true,
                  onPressed: settings.canGoNextAudit
                      ? () {
                          unawaited(
                            ref
                                .read(settingsProvider.notifier)
                                .goToAuditPage(settings.auditPage + 1),
                          );
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoAxisScroll extends StatelessWidget {
  const _TwoAxisScroll({required this.minWidth, required this.child});

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EraseTablesDialog extends StatefulWidget {
  const _EraseTablesDialog({required this.tables, required this.hasOpenShift});

  final List<StationTableInfo> tables;
  final bool hasOpenShift;

  @override
  State<_EraseTablesDialog> createState() => _EraseTablesDialogState();
}

class _EraseTablesDialogState extends State<_EraseTablesDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = <String>{};
  }

  bool get _allSelected =>
      widget.tables.isNotEmpty && _selected.length == widget.tables.length;

  bool get _touchesLiveShift {
    return widget.hasOpenShift &&
        (_selected.contains(DatabaseHelper.tableShifts) ||
            _selected.contains(DatabaseHelper.tableSalesTransactions) ||
            _selected.contains(DatabaseHelper.tableManagers));
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.tables.map((StationTableInfo table) => table.name));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      title: Text(
        'Reset / erase tables',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: tokens.ink,
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Choose which SQLite tables to empty. Selected tables are '
                'truncated (all rows deleted). This cannot be undone.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13,
                  height: 1.4,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _toggleAll,
                  child: Text(_allSelected ? 'Clear selection' : 'Select all'),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: Material(
                  color: tokens.canvas,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.radius12),
                    side: BorderSide(color: tokens.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.tables.length,
                    separatorBuilder: (BuildContext context, int index) {
                      return Divider(height: 1, color: tokens.line);
                    },
                    itemBuilder: (BuildContext context, int index) {
                      final StationTableInfo table = widget.tables[index];
                      final bool checked = _selected.contains(table.name);
                      return CheckboxListTile(
                        value: checked,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: tokens.coral,
                        hoverColor: tokens.ink.withValues(alpha: 0.04),
                        title: Text(
                          table.label,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: tokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          '${table.name}  ·  ${table.rowCount} row${table.rowCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 11,
                            color: tokens.inkMuted,
                          ),
                        ),
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(table.name);
                            } else {
                              _selected.remove(table.name);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              if (_touchesLiveShift)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'An OPEN shift is live. Erasing shifts, sales, or managers '
                    'will drop in-progress station data.',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.35,
                      color: tokens.bad,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        DsPillButton(
          label: 'Cancel',
          variant: DsPillVariant.outline,
          compact: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DsPillButton(
          label: _selected.isEmpty
              ? 'Erase tables'
              : 'Erase ${_selected.length} table${_selected.length == 1 ? '' : 's'}',
          variant: DsPillVariant.danger,
          compact: true,
          icon: Icons.delete_forever_outlined,
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set<String>.of(_selected)),
        ),
      ],
    );
  }
}
