import 'package:flutter/material.dart';

class EmptyChatState extends StatelessWidget {
  const EmptyChatState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Your BLE chat activity will appear here.\nWrite, read, subscribe, or publish to start the conversation.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
