import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/data/dispenser_socket_manager.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/dispenser_monitor_models.dart';
import '../../../features/station/presentation/station_providers.dart';

class GatewayHeaderCard extends StatelessWidget {
  const GatewayHeaderCard({
    super.key,
    required this.station,
    required this.monitor,
    required this.onGlobalLock,
  });

  final StationState station;
  final DispenserMonitorState monitor;
  final VoidCallback onGlobalLock;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int active = station.endpoints.values
        .where((UnitEndpoint endpoint) => endpoint.connected)
        .length;
    final bool muxUp = active > 0;
    final bool heartbeatLost = station.bays.values.any((DispenserBay bay) {
      final UnitEndpoint endpoint = station.endpoint(bay.unitId);
      return BayLinkHealth.evaluate(
        bay: bay,
        endpoint: endpoint,
        snapshot: monitor.diagnosticFor(bay.unitId),
        now: monitor.clock,
      ).muxHeartbeatLost;
    });
    final String url = StationNetDefaults.gatewayUrl();
    final int? latencyMs = monitor.gatewayLatencyMs;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'FDX ALPHA  →  FDX ESP-01  →  Bay ESP-01  →  UART TX/RX  →  ESP32  →  ${StationNetDefaults.officeSsid}  →  App',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 0.3,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints bounds) {
              final bool compact = bounds.maxWidth < 1180;
              final Widget mux = _GatewayStatusBlock(
                url: url,
                connected: muxUp && !heartbeatLost,
                latencyMs: latencyMs,
                heartbeatLost: heartbeatLost && muxUp,
              );
              final Widget metrics = compact
                  ? Column(
                      children: <Widget>[
                        _MetricChip(
                          icon: Icons.wifi_tethering,
                          label: StationNetDefaults.officeSsid,
                          value: muxUp
                              ? 'OFFICE ROUTER UP'
                              : 'OFFICE ROUTER DOWN',
                          good: muxUp && !heartbeatLost,
                          warn: muxUp && heartbeatLost,
                        ),
                        const SizedBox(height: 8),
                        _MetricChip(
                          icon: Icons.dns_outlined,
                          label: 'Bay sockets',
                          value: '$active / $kDispenserUnitCount Connected',
                          good: active > 0,
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        Expanded(
                          child: _MetricChip(
                            icon: Icons.wifi_tethering,
                            label: StationNetDefaults.officeSsid,
                            value: muxUp
                                ? 'OFFICE ROUTER UP'
                                : 'OFFICE ROUTER DOWN',
                            good: muxUp && !heartbeatLost,
                            warn: muxUp && heartbeatLost,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricChip(
                            icon: Icons.dns_outlined,
                            label: 'Bay sockets',
                            value: '$active / $kDispenserUnitCount Connected',
                            good: active > 0,
                          ),
                        ),
                      ],
                    );
              final Widget lock = DsPillButton(
                label: 'GLOBAL KEYPAD LOCK',
                icon: Icons.lock_outline,
                variant: DsPillVariant.danger,
                onPressed: onGlobalLock,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    mux,
                    const SizedBox(height: 10),
                    metrics,
                    const SizedBox(height: 10),
                    lock,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(flex: 3, child: mux),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: metrics),
                  const SizedBox(width: 12),
                  Flexible(child: lock),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GatewayStatusBlock extends StatelessWidget {
  const _GatewayStatusBlock({
    required this.url,
    required this.connected,
    required this.latencyMs,
    required this.heartbeatLost,
  });

  final String url;
  final bool connected;
  final int? latencyMs;
  final bool heartbeatLost;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color accent = heartbeatLost
        ? tokens.bad
        : (connected ? tokens.good : tokens.inkMuted);
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(tokens.radius12),
          ),
          child: Icon(Icons.router_outlined, color: accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'CENTRAL ESP32 · ${StationNetDefaults.officeSsid}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                url,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  DsStatusPill(
                    label: heartbeatLost
                        ? 'RED ALERT · HEARTBEAT >3000ms'
                        : (connected ? 'CONNECTED' : 'DISCONNECTED'),
                    foreground: accent,
                    background: accent.withValues(alpha: 0.12),
                    border: accent.withValues(alpha: 0.35),
                  ),
                  DsStatusPill(
                    label: latencyMs == null
                        ? 'PING — ms'
                        : 'PING ${latencyMs}ms',
                    foreground: tokens.ink,
                    background: tokens.canvas,
                    border: tokens.line,
                    dot: false,
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy ESP32 URL',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
          },
          icon: Icon(Icons.copy_outlined, size: 16, color: tokens.inkMuted),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    this.good = false,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool good;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color accent = good
        ? tokens.good
        : (warn ? tokens.warn : tokens.inkMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                    letterSpacing: 0.7,
                    color: tokens.inkMuted,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: tokens.ink,
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
