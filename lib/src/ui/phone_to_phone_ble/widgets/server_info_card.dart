import 'package:flutter/material.dart';

import 'mini_badge.dart';

class ServerInfoCard extends StatelessWidget {
  const ServerInfoCard({
    required this.serverValue,
    required this.subscribers,
    super.key,
  });

  final String serverValue;
  final int subscribers;

  @override
  Widget build(BuildContext context) {
    final String displayValue =
        serverValue.trim().isEmpty ? 'Waiting for live value...' : serverValue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Current Value',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              MiniBadge(text: '$subscribers listener(s)'),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText(
                  displayValue,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
