import 'package:flutter/material.dart';

class ActionCard extends StatelessWidget {
  const ActionCard({
    required this.canWrite,
    required this.subscribed,
    required this.onWrite,
    super.key,
  });

  final bool canWrite;
  final bool subscribed;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    // return Container(
    //   width: double.infinity,
    //   padding: const EdgeInsets.all(14),
    //   decoration: BoxDecoration(
    //     color: const Color(0xFFF8FAFC),
    //     borderRadius: BorderRadius.circular(14),
    //     border: Border.all(color: const Color(0xFFE2E8F0)),
    //   ),
    //   child: Column(
    //     crossAxisAlignment: CrossAxisAlignment.start,
    //     children: <Widget>[
    //       Text(
    //         subscribed
    //             ? 'Live updates are on. Incoming values appear automatically.'
    //             : 'Live updates will start automatically once the device finishes connecting.',
    //         style: Theme.of(context).textTheme.bodyMedium,
    //       ),
    //       const SizedBox(height: 10),
    //       FilledButton.tonal(
    //         onPressed: canWrite ? onWrite : null,
    //         child: const Text('Send Current Message'),
    //       ),
    //     ],
    //   ),
    // );
     return SizedBox.shrink();
  }
}
