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
        gradient: LinearGradient(
          colors: <Color>[Colors.blue.shade100, Colors.cyan.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '$mode Mode',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
          Text(status),
        ],
      ),
    );
  }
}
