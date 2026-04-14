import 'dart:convert';

class ChatData {
  final String message;
  final String sender;

  ChatData({required this.message, required this.sender});

  Map<String, dynamic> toJson() => <String, dynamic>{
    'message': message,
    'sender': sender,
  };

  String toJsonString() => jsonEncode(toJson());

  factory ChatData.fromJson(Map<String, dynamic> json) {
    return ChatData(
      message: json['message']?.toString() ?? '',
      sender: json['sender']?.toString() ?? 'Unknown',
    );
  }

  factory ChatData.fromRaw(String raw, {String fallbackSender = 'Unknown'}) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ChatData.fromJson(decoded);
      }
      if (decoded is Map) {
        return ChatData.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Fallback to plain text below.
    }

    return ChatData(message: raw, sender: fallbackSender);
  }
}
