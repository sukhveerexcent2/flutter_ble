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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Current Value',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(serverValue),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MiniBadge(text: '$subscribers listener(s)'),
          ],
        ),
      ),
    );
  }
}
