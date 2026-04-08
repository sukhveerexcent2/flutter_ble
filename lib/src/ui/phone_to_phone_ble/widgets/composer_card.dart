import 'package:flutter/material.dart';

class ComposerCard extends StatelessWidget {
  const ComposerCard({
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.buttonLabel,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final String buttonLabel;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend?.call(),
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSend,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
