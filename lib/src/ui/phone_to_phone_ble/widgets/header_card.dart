import 'package:flutter/material.dart';

import 'mini_badge.dart';

class HeaderCard extends StatelessWidget {
  const HeaderCard({
    required this.status,
    required this.mode,
    required this.connected,
    required this.advertising,
    required this.scanning,
    required this.subscribed,
    super.key,
  });

  final String status;
  final String mode;
  final bool connected;
  final bool advertising;
  final bool scanning;
  final bool subscribed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Text(
                '$mode Mode',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              MiniBadge(
                text: connected
                    ? 'Connected'
                    : advertising
                    ? 'Advertising'
                    : scanning
                    ? 'Scanning'
                    : 'Idle',
              ),
              if (subscribed) ...<Widget>[
                const SizedBox(width: 8),
                const MiniBadge(text: 'Subscribed'),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
