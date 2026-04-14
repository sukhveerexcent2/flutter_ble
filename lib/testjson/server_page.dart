import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/material.dart';

import 'ble_json_config.dart';
import 'ble_permissions.dart';
import 'models/chat_data.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final PeripheralManager _peripheral = PeripheralManager();
  final TextEditingController _controller = TextEditingController();
  final List<ChatData> _messages = <ChatData>[];
  final List<Central> _subscribedCentrals = <Central>[];
  Timer? _typingDebounce;
  String _lastSentJson = '';

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>?
  _stateSubscription;
  StreamSubscription<GATTCharacteristicReadRequestedEventArgs>?
  _readRequestSubscription;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>?
  _writeRequestSubscription;
  StreamSubscription<GATTCharacteristicNotifyStateChangedEventArgs>?
  _notifyStateSubscription;

  GATTCharacteristic? _characteristic;
  Uint8List _lastPayload = Uint8List.fromList(
    utf8.encode(
      ChatData(message: 'Server ready', sender: 'Server').toJsonString(),
    ),
  );
  String _status = 'Starting server...';
  bool _advertising = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleInputChanged);
    _listenToPeripheral();
    unawaited(startServer());
  }

  void _handleInputChanged() {
    _typingDebounce?.cancel();

    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      return;
    }

    final preview = _buildOutgoingData(raw).toJsonString();
    if (preview == _lastSentJson) {
      return;
    }

    _typingDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) {
        return;
      }
      await sendJson(clearInput: false);
    });
  }

  void _listenToPeripheral() {
    _stateSubscription = _peripheral.stateChanged.listen((event) async {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Peripheral state: ${event.state}';
      });
    });

    _readRequestSubscription = _peripheral.characteristicReadRequested.listen((
      event,
    ) async {
      if (event.characteristic.uuid != kBleJsonCharacteristicUuid) {
        await _peripheral.respondReadRequestWithError(
          event.request,
          error: GATTError.attributeNotFound,
        );
        return;
      }

      final offset = event.request.offset;
      if (offset > _lastPayload.length) {
        await _peripheral.respondReadRequestWithError(
          event.request,
          error: GATTError.invalidOffset,
        );
        return;
      }

      await _peripheral.respondReadRequestWithValue(
        event.request,
        value: _lastPayload.sublist(offset),
      );
    });

    _writeRequestSubscription = _peripheral.characteristicWriteRequested.listen(
      (event) async {
        if (event.characteristic.uuid != kBleJsonCharacteristicUuid) {
          await _peripheral.respondWriteRequest(event.request);
          return;
        }

        _lastPayload = Uint8List.fromList(event.request.value);
        await _peripheral.respondWriteRequest(event.request);

        final raw = utf8.decode(event.request.value, allowMalformed: true);
        final data = ChatData.fromRaw(raw, fallbackSender: 'Client');

        if (!mounted) {
          return;
        }

        setState(() {
          _messages.insert(0, data);
          _status = 'Received JSON from client';
        });
      },
    );

    _notifyStateSubscription = _peripheral.characteristicNotifyStateChanged
        .listen((event) async {
          if (event.characteristic.uuid != kBleJsonCharacteristicUuid) {
            return;
          }

          final index = _subscribedCentrals.indexWhere(
            (central) => central.uuid == event.central.uuid,
          );

          if (event.state) {
            if (index == -1) {
              _subscribedCentrals.add(event.central);
            }
            await _notifyCentral(event.central, _lastPayload);
          } else if (index != -1) {
            _subscribedCentrals.removeAt(index);
          }

          if (!mounted) {
            return;
          }

          setState(() {
            _status = 'Subscribers: ${_subscribedCentrals.length}';
          });
        });
  }

  Future<void> startServer() async {
    final granted = await requestBlePermissions(includeAdvertise: true);
    if (!granted) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'BLE advertise permission denied';
      });
      return;
    }

    await _peripheral.removeAllServices();

    final char = GATTCharacteristic.mutable(
      uuid: kBleJsonCharacteristicUuid,
      properties: <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
        GATTCharacteristicProperty.notify,
      ],
      permissions: <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: const <GATTDescriptor>[],
    );

    final service = GATTService(
      uuid: kBleJsonServiceUuid,
      isPrimary: true,
      includedServices: const <GATTService>[],
      characteristics: <GATTCharacteristic>[char],
    );

    await _peripheral.addService(service);
    await _peripheral.startAdvertising(
      Advertisement(
        name: Platform.isWindows ? null : kBleJsonServerName,
        serviceUUIDs: <UUID>[kBleJsonServiceUuid],
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _characteristic = char;
      _advertising = true;
      _status = 'Advertising as $kBleJsonServerName';
      _messages.insert(0, ChatData(message: 'Server ready', sender: 'System'));
    });
  }

  ChatData _buildOutgoingData(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return ChatData(message: '', sender: 'Server');
    }
    return ChatData.fromRaw(text, fallbackSender: 'Server');
  }

  Future<void> sendJson({bool clearInput = true}) async {
    final data = _buildOutgoingData(_controller.text);
    if (data.message.isEmpty) {
      return;
    }

    final jsonString = jsonEncode(data.toJson());
    if (jsonString == _lastSentJson) {
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonString));

    _lastPayload = bytes;
    await _notifyAll(bytes);

    if (!mounted) {
      return;
    }

    setState(() {
      _lastSentJson = jsonString;
      _messages.insert(0, data);
      _status = 'JSON sent to ${_subscribedCentrals.length} client(s)';
      if (clearInput) {
        _controller.clear();
      }
    });
  }

  Future<void> _notifyAll(Uint8List value) async {
    for (final central in List<Central>.from(_subscribedCentrals)) {
      await _notifyCentral(central, value);
    }
  }

  Future<void> _notifyCentral(Central central, Uint8List value) async {
    final characteristic = _characteristic;
    if (characteristic == null) {
      return;
    }

    final maximumLength = await _peripheral.getMaximumNotifyLength(central);
    final payload = value.length > maximumLength
        ? value.sublist(0, maximumLength)
        : value;

    await _peripheral.notifyCharacteristic(
      central,
      characteristic,
      value: payload,
    );
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_readRequestSubscription?.cancel());
    unawaited(_writeRequestSubscription?.cancel());
    unawaited(_notifyStateSubscription?.cancel());
    _typingDebounce?.cancel();
    if (_advertising) {
      unawaited(_peripheral.stopAdvertising());
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_status, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Subscribers: ${_subscribedCentrals.length}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Type text or JSON here for real-time send',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => sendJson(),
              child: const Text('Send JSON'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(child: Text('No JSON messages yet'))
                  : ListView.separated(
                      reverse: true,
                      itemCount: _messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _messages[index];
                        return _MessageTile(data: item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.data});

  final ChatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            data.sender,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(data.message),
        ],
      ),
    );
  }
}
