import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/dispenser_monitor_models.dart';
import '../../../features/station/presentation/station_providers.dart';
import '../../../utils/fuel_formatter.dart';

class DiagnosticBayCard extends ConsumerStatefulWidget {
  const DiagnosticBayCard({
    super.key,
    required this.bay,
    required this.endpoint,
    required this.snapshot,
    required this.clock,
  });

  final DispenserBay bay;
  final UnitEndpoint endpoint;
  final BayDiagnosticSnapshot snapshot;
  final DateTime clock;

  @override
  ConsumerState<DiagnosticBayCard> createState() => _DiagnosticBayCardState();
}

class _DiagnosticBayCardState extends ConsumerState<DiagnosticBayCard> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  static final DateFormat _stamp = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.endpoint.host);
    _port = TextEditingController(text: '${widget.endpoint.port}');
  }

  @override
  void didUpdateWidget(covariant DiagnosticBayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint.host != widget.endpoint.host &&
        _host.text != widget.endpoint.host) {
      _host.text = widget.endpoint.host;
    }
    if (oldWidget.endpoint.port != widget.endpoint.port &&
        _port.text != '${widget.endpoint.port}') {
      _port.text = '${widget.endpoint.port}';
    }
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

  bool _commitEndpoint() {
    final int? port = _parsedPort();
    if (_host.text.trim().isEmpty ||
        port == null ||
        port <= 0 ||
        port > 65535) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Enter a valid IP and port')),
      );
      return false;
    }
    ref
        .read(stationControllerProvider.notifier)
        .saveEndpoint(unitId: widget.bay.unitId, host: _host.text, port: port);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationController station = ref.read(
      stationControllerProvider.notifier,
    );
    final DispenserBay bay = widget.bay;
    final UnitEndpoint endpoint = widget.endpoint;
    final BayLinkHealth health = BayLinkHealth.evaluate(
      bay: bay,
      endpoint: endpoint,
      snapshot: widget.snapshot,
      now: widget.clock,
    );
    final MonitorBayStatus status = monitorStatusFor(
      bay,
      linkOnline: endpoint.connected && !health.muxHeartbeatLost,
    );
    final Color statusColor = switch (status) {
      MonitorBayStatus.online => tokens.good,
      MonitorBayStatus.dispensing => tokens.coral,
      MonitorBayStatus.keypadLocked => tokens.warn,
      MonitorBayStatus.offline => tokens.inkMuted,
    };
    final DateTime stamp = bay.lastPacketAt ?? widget.clock;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(
          color: health.muxAlert ? tokens.bad : tokens.line,
          width: health.muxAlert ? 1.4 : 1,
        ),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Unit ${bay.unitId}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(width: 8),
              DsStatusPill(
                label: kDieselFuelType,
                foreground: tokens.inkMuted,
                background: tokens.canvas,
                border: tokens.line,
                dot: false,
              ),
              const Spacer(),
              DsStatusPill(
                label: status.label,
                foreground: statusColor,
                background: statusColor.withValues(alpha: 0.12),
                border: statusColor.withValues(alpha: 0.35),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SocketFields(
            host: _host,
            port: _port,
            hintHost: UnitEndpoint.seedFor(bay.unitId).host,
            hintPort: '${UnitEndpoint.seedFor(bay.unitId).port}',
            connected: endpoint.connected,
            onConnect: () {
              if (_commitEndpoint()) {
                station.connectUnit(bay.unitId);
              }
            },
            onDisconnect: () {
              _commitEndpoint();
              station.disconnectUnit(bay.unitId);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: _FdxLinkPane(health: health)),
              const SizedBox(width: 8),
              Expanded(child: _SerialLinkPane(health: health)),
            ],
          ),
          const SizedBox(height: 8),
          _FaultRow(health: health),
          const SizedBox(height: 10),
          _TelemetryGrid(
            fields: <_Field>[
              _Field('unit_id', '${bay.unitId}'),
              _Field('timestamp', _stamp.format(stamp)),
              _Field('status', status.label),
              _Field('rssi', '${health.rssiDbm}'),
              _Field('liters', FuelFormatter.lcdVolume(bay.volumeLiters)),
              _Field('amount_pkr', FuelFormatter.lcdDispenserAmount(bay.amountPkr)),
              _Field('rate_pkr', FuelFormatter.lcdRate(bay.rate)),
              _Field('total_meter', FuelFormatter.lcdVolume(bay.meterCount)),
              _Field('keypad_locked', bay.keypadLocked ? 'true' : 'false'),
              _Field(
                'esp_to_board_link',
                health.serialLive
                    ? 'true'
                    : (health.serialStall ? 'false' : '—'),
              ),
              _Field(
                'pending_tx',
                '${widget.snapshot.pendingTxCount ?? 0}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'TROUBLESHOOT',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.8,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
          DsPillButton(
            label: 'Re-scan Bay Wi-Fi',
            icon: Icons.wifi_find_outlined,
            variant: DsPillVariant.outline,
            compact: true,
            onPressed: () => station.rescanBayWifi(bay.unitId),
          ),
          const SizedBox(height: 6),
          DsPillButton(
            label: 'Flush UART Buffer',
            icon: Icons.cleaning_services_outlined,
            variant: DsPillVariant.outline,
            compact: true,
            onPressed: () => station.flushUartBuffer(bay.unitId),
          ),
          const SizedBox(height: 6),
          DsPillButton(
            label: 'Reset Bay Socket',
            icon: Icons.restart_alt,
            variant: DsPillVariant.muted,
            compact: true,
            onPressed: () => station.resetBaySocket(bay.unitId),
          ),
        ],
      ),
    );
  }
}

class _SocketFields extends StatelessWidget {
  const _SocketFields({
    required this.host,
    required this.port,
    required this.hintHost,
    required this.hintPort,
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
  });

  final TextEditingController host;
  final TextEditingController port;
  final String hintHost;
  final String hintPort;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: TextField(
                controller: host,
                decoration: InputDecoration(
                  labelText: 'IP',
                  hintText: hintHost,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: port,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Port',
                  hintText: hintPort,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: DsPillButton(
                label: 'Disconnect',
                variant: DsPillVariant.outline,
                compact: true,
                onPressed: connected ? onDisconnect : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Connect',
                variant: DsPillVariant.coral,
                compact: true,
                onPressed: connected ? null : onConnect,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FdxLinkPane extends StatelessWidget {
  const _FdxLinkPane({required this.health});

  final BayLinkHealth health;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color color = health.fdxWifiDrop
        ? tokens.bad
        : (health.fdxWifiUp ? tokens.good : tokens.inkMuted);
    return _TierPane(
      title: 'FDX LINK',
      subtitle: 'FDX ALPHA ↔ ESP32',
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            health.fdxWifiDrop
                ? 'Wi-Fi DROP'
                : (health.fdxWifiUp ? 'Wi-Fi UP' : 'IDLE'),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: tokens.ink,
            ),
          ),
          Text(
            '${health.rssiDbm} dBm',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: tokens.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SerialLinkPane extends StatelessWidget {
  const _SerialLinkPane({required this.health});

  final BayLinkHealth health;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color color = health.serialStall
        ? tokens.warn
        : (health.serialLive ? tokens.good : tokens.inkMuted);
    return _TierPane(
      title: 'SERIAL UART',
      subtitle: 'GPIO16 RX · 4800',
      color: color,
      child: Row(
        children: <Widget>[
          _Lamp(label: 'TX', on: health.txHot, color: tokens.coral),
          const SizedBox(width: 8),
          _Lamp(label: 'RX', on: health.rxHot, color: tokens.good),
          const Spacer(),
          Flexible(
            child: Text(
              health.serialStall
                  ? 'STALL'
                  : (health.serialLive ? 'LIVE' : 'IDLE'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierPane extends StatelessWidget {
  const _TierPane({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.7,
              color: tokens.inkMuted,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 9,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _Lamp extends StatelessWidget {
  const _Lamp({required this.label, required this.on, required this.color});

  final String label;
  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: on ? color : tokens.line,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 9,
            color: tokens.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _FaultRow extends StatelessWidget {
  const _FaultRow({required this.health});

  final BayLinkHealth health;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        if (health.fdxWifiDrop)
          DsStatusPill(
            label: 'FDX Wi-Fi DROP',
            foreground: tokens.bad,
            background: tokens.bad.withValues(alpha: 0.12),
            border: tokens.bad.withValues(alpha: 0.4),
          ),
        if (health.serialStall)
          DsStatusPill(
            label: 'UART STALL',
            foreground: tokens.warn,
            background: tokens.warn.withValues(alpha: 0.12),
            border: tokens.warn.withValues(alpha: 0.4),
          ),
        if (health.muxAlert)
          DsStatusPill(
            label: health.muxHeartbeatLost
                ? 'ESP32 / MUX >3000ms'
                : 'ESP32 SOCKET DOWN',
            foreground: tokens.bad,
            background: tokens.bad.withValues(alpha: 0.12),
            border: tokens.bad.withValues(alpha: 0.4),
          ),
        if (!health.fdxWifiDrop && !health.serialStall && !health.muxAlert)
          DsStatusPill(
            label: 'BRIDGE OK',
            foreground: tokens.good,
            background: tokens.good.withValues(alpha: 0.12),
            border: tokens.good.withValues(alpha: 0.35),
          ),
      ],
    );
  }
}

class _Field {
  const _Field(this.key, this.value);

  final String key;
  final String value;
}

class _TelemetryGrid extends StatelessWidget {
  const _TelemetryGrid({required this.fields});

  final List<_Field> fields;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: tokens.ink,
        borderRadius: BorderRadius.circular(tokens.radius12),
      ),
      child: Column(
        children: <Widget>[
          for (final _Field field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: Text(
                      field.key,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                        color: tokens.canvas.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      field.value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: tokens.canvas,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
