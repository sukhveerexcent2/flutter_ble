import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'models/chat_data.dart';

class ClientChatPage extends StatefulWidget {
  const ClientChatPage({
    required this.centralManager,
    required this.peripheral,
    required this.characteristic,
    super.key,
  });

  final CentralManager centralManager;
  final Peripheral peripheral;
  final GATTCharacteristic characteristic;

  @override
  State<ClientChatPage> createState() => _ClientChatPageState();
}

class _ClientChatPageState extends State<ClientChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatData> _messages = <ChatData>[];
  final StreamController<List<ChatData>> _messagesStreamController =
      StreamController<List<ChatData>>.broadcast();

  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifiedSubscription;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>?
  _connectionSubscription;

  String _status = 'Connecting to live updates...';
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _listenForUpdates();
    unawaited(_enableRealtimeUpdates());
  }

  void _listenForUpdates() {
    _notifiedSubscription = widget.centralManager.characteristicNotified.listen((
      event,
    ) {
      if (event.characteristic.uuid != widget.characteristic.uuid || !mounted) {
        return;
      }

      _appendIncoming(event.value);
    });

    _connectionSubscription = widget.centralManager.connectionStateChanged.listen((
      event,
    ) {
      if (event.peripheral != widget.peripheral || !mounted) {
        return;
      }

      setState(() {
        _status = event.state == ConnectionState.connected
            ? 'Connected with real-time JSON updates'
            : 'Disconnected from server';
      });
    });
  }

  Future<void> _enableRealtimeUpdates() async {
    await widget.centralManager.setCharacteristicNotifyState(
      widget.peripheral,
      widget.characteristic,
      state: true,
    );

    final initialValue = await widget.centralManager.readCharacteristic(
      widget.peripheral,
      widget.characteristic,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _subscribed = true;
      _status = 'Connected with real-time JSON updates';
    });

    if (initialValue.isNotEmpty) {
      _appendIncoming(initialValue);
    }
  }

  void _appendIncoming(Uint8List value) {
    final raw = utf8.decode(value, allowMalformed: true);
    final chat = ChatData.fromRaw(raw, fallbackSender: 'Server');

    setState(() {
      _messages.insert(0, chat);
      _status = 'Real-time update received';
    });
    _emitMessages();
  }

  Future<void> _sendToServer() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      return;
    }

    final chat = ChatData.fromRaw(raw, fallbackSender: 'Client');
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(chat.toJson())));

    final type = widget.characteristic.properties.contains(
          GATTCharacteristicProperty.writeWithoutResponse,
        )
        ? GATTCharacteristicWriteType.withoutResponse
        : GATTCharacteristicWriteType.withResponse;

    await widget.centralManager.writeCharacteristic(
      widget.peripheral,
      widget.characteristic,
      value: bytes,
      type: type,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _messages.insert(0, chat);
      _status = 'JSON sent to server';
      _controller.clear();
    });
    _emitMessages();
  }

  void _emitMessages() {
    if (!_messagesStreamController.isClosed) {
      _messagesStreamController.add(List<ChatData>.from(_messages));
    }
  }

  @override
  void dispose() {
    unawaited(_notifiedSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    if (_subscribed) {
      unawaited(
        widget.centralManager.setCharacteristicNotifyState(
          widget.peripheral,
          widget.characteristic,
          state: false,
        ),
      );
    }
    unawaited(widget.centralManager.disconnect(widget.peripheral));
    unawaited(_messagesStreamController.close());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client Chat')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(_status),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Type message text or full JSON',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _sendToServer,
              child: const Text('Send to Server'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<ChatData>>(
                stream: _messagesStreamController.stream,
                initialData: const <ChatData>[],
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <ChatData>[];
                  if (items.isEmpty) {
                    return const Center(
                      child: Text('Waiting for real-time JSON updates'),
                    );
                  }

                  return ListView.separated(
                    reverse: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.sender,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(item.message),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
