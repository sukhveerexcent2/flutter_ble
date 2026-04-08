import 'package:flutter/material.dart';

class ComposerCard extends StatelessWidget {
  const ComposerCard({
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.buttonLabel,
    required this.onSend,
    this.showButton = true,
    this.onChanged,
    this.onAttach,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final String buttonLabel;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSend;
  final bool showButton;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: enabled ? onAttach : null,
            icon: const Icon(Icons.add),
            tooltip: 'Select JSON file',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 6,
              onChanged: onChanged,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend?.call(),
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
              ),
            ),
          ),
          if (showButton) ...<Widget>[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSend,
              child: Text(buttonLabel),
            ),
          ],
        ],
      ),
    );
  }
}
