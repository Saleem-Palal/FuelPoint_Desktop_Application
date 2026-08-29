import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/presentation/station_providers.dart';

Future<void> showUnitLinkDialog({
  required BuildContext context,
  required int unitId,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return _UnitLinkDialog(unitId: unitId);
    },
  );
}

class _UnitLinkDialog extends ConsumerStatefulWidget {
  const _UnitLinkDialog({required this.unitId});

  final int unitId;

  @override
  ConsumerState<_UnitLinkDialog> createState() => _UnitLinkDialogState();
}

class _UnitLinkDialogState extends ConsumerState<_UnitLinkDialog> {
  late final TextEditingController _host;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    final UnitEndpoint endpoint = ref
        .read(stationControllerProvider)
        .endpoint(widget.unitId);
    _host = TextEditingController(text: endpoint.host);
    _port = TextEditingController(text: '${endpoint.port}');
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  int? _parsedPort() {
    return int.tryParse(_port.text.trim());
  }

  void _saveThen(void Function(int unitId) action) {
    final int? port = _parsedPort();
    if (_host.text.trim().isEmpty ||
        port == null ||
        port <= 0 ||
        port > 65535) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Enter a valid IP and port')),
      );
      return;
    }
    ref
        .read(stationControllerProvider.notifier)
        .saveEndpoint(unitId: widget.unitId, host: _host.text, port: port);
    action(widget.unitId);
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final DispenserBay bay = ref
        .watch(stationControllerProvider)
        .bay(widget.unitId);
    final UnitEndpoint endpoint = ref
        .watch(stationControllerProvider)
        .endpoint(widget.unitId);

    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${bay.name} link',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tokens.ink,
              ),
            ),
          ),
          DsStatusPill(
            label: endpoint.connected ? 'Connected' : 'Disconnected',
            foreground: endpoint.connected ? tokens.good : tokens.inkMuted,
            background: endpoint.connected
                ? tokens.good.withValues(alpha: 0.12)
                : tokens.line.withValues(alpha: 0.6),
            border: endpoint.connected
                ? tokens.good.withValues(alpha: 0.3)
                : tokens.line,
            dot: true,
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'IP address',
                hintText: '192.168.1.101',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8080',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DsPillButton(
                label: 'Disconnect',
                variant: DsPillVariant.outline,
                compact: true,
                onPressed: () {
                  _saveThen(
                    ref.read(stationControllerProvider.notifier).disconnectUnit,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Connect',
                variant: DsPillVariant.coral,
                compact: true,
                onPressed: () {
                  _saveThen(
                    ref.read(stationControllerProvider.notifier).connectUnit,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
