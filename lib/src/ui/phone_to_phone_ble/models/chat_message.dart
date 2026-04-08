class ChatMessage {
  const ChatMessage({
    required this.label,
    required this.text,
    required this.outgoing,
    required this.time,
  });

  final String label;
  final String text;
  final bool outgoing;
  final String time;
}
