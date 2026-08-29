import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/section_card.dart';
import '../dashboard_controller.dart';

class SendPanel extends StatefulWidget {
  const SendPanel({super.key});

  @override
  State<SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends State<SendPanel> {
  final TextEditingController _payload = TextEditingController();
  bool _hexMode = false;
  bool _appendCrlf = true;

  @override
  void dispose() {
    _payload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DashboardController controller = context.watch<DashboardController>();

    return SectionCard(
      title: 'Send a command',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('HEX'),
                selected: _hexMode,
                onSelected: (bool value) => setState(() => _hexMode = value),
              ),
              FilterChip(
                label: const Text('Add Enter'),
                selected: !_hexMode && _appendCrlf,
                onSelected: (bool value) => setState(() => _appendCrlf = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _payload,
                  enabled: controller.isConnected,
                  decoration: InputDecoration(
                    hintText: _hexMode ? '01 0A FF' : 'Type a command',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(controller),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: controller.isConnected
                    ? () => _send(controller)
                    : null,
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _send(DashboardController controller) {
    final String text = _payload.text;
    if (text.trim().isEmpty) {
      return;
    }
    if (_hexMode) {
      controller.sendHex(text);
    } else {
      controller.sendAscii(text, appendCrlf: _appendCrlf);
    }
  }
}
