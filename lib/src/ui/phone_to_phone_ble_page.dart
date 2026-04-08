import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:permission_handler/permission_handler.dart';

class PhoneToPhoneBlePage extends StatefulWidget {
  const PhoneToPhoneBlePage({super.key});

  @override
  State<PhoneToPhoneBlePage> createState() => _PhoneToPhoneBlePageState();
}

class _PhoneToPhoneBlePageState extends State<PhoneToPhoneBlePage> {
  static const String _serverName = 'Flutter_Server';

  final CentralManager _centralManager = CentralManager();
  final PeripheralManager _peripheralManager = PeripheralManager();
  final TextEditingController _messageController = TextEditingController();
  final List<DiscoveredEventArgs> _discoveries = <DiscoveredEventArgs>[];
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final UUID _serviceUuid = UUID.fromString(
    '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
  );
  final UUID _characteristicUuid = UUID.fromString(
    '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
  );

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>?
  _centralStateSubscription;
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>?
  _peripheralStateSubscription;
  StreamSubscription<DiscoveredEventArgs>? _discoveredSubscription;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>?
  _connectionSubscription;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>?
  _notifiedSubscription;
  StreamSubscription<GATTCharacteristicReadRequestedEventArgs>?
  _readRequestSubscription;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>?
  _writeRequestSubscription;
  StreamSubscription<GATTCharacteristicNotifyStateChangedEventArgs>?
  _notifyStateSubscription;

  String _status = 'Idle';
  bool _actingAsServer = false;
  bool _scanning = false;
  bool _advertising = false;
  bool _connecting = false;
  bool _subscribed = false;
  Peripheral? _connectedPeripheral;
  GATTCharacteristic? _chatCharacteristic;
  GATTCharacteristic? _serverCharacteristic;
  Uint8List _characteristicValue = Uint8List.fromList(
    utf8.encode('Server ready'),
  );
  final List<Central> _subscribedCentrals = <Central>[];

  @override
  void initState() {
    super.initState();
    _listenToManagers();
  }

  void _listenToManagers() {
    _centralStateSubscription = _centralManager.stateChanged.listen((
      event,
    ) async {
      if (event.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _centralManager.authorize();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Central state: ${event.state}';
      });
    });

    _peripheralStateSubscription = _peripheralManager.stateChanged.listen((
      event,
    ) async {
      if (event.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _peripheralManager.authorize();
      }
      if (!mounted) {
        return;
      }
      if (_actingAsServer) {
        setState(() {
          _status = 'Peripheral state: ${event.state}';
        });
      }
    });

    _discoveredSubscription = _centralManager.discovered.listen((event) {
      final hasService = event.advertisement.serviceUUIDs.contains(_serviceUuid);
      final hasName = event.advertisement.name == _serverName;
      if (!hasService && !hasName) {
        return;
      }

      final index = _discoveries.indexWhere(
        (item) => item.peripheral == event.peripheral,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (index == -1) {
          _discoveries.add(event);
        } else {
          _discoveries[index] = event;
        }
        _status = 'Found ${_discoveries.length} BLE server(s)';
      });
    });

    _connectionSubscription = _centralManager.connectionStateChanged.listen((
      event,
    ) async {
      if (_connectedPeripheral != null && event.peripheral != _connectedPeripheral) {
        return;
      }

      if (!mounted) {
        return;
      }

      if (event.state == ConnectionState.connected) {
        setState(() {
          _connecting = false;
          _subscribed = false;
          _status = 'Connected. Discovering chat service...';
        });
        await _discoverChatCharacteristic(event.peripheral);
      } else {
        setState(() {
          _connecting = false;
          _connectedPeripheral = null;
          _chatCharacteristic = null;
          _subscribed = false;
          _status = 'Disconnected';
        });
      }
    });

    _notifiedSubscription = _centralManager.characteristicNotified.listen((
      event,
    ) {
      if (event.characteristic.uuid != _characteristicUuid || !mounted) {
        return;
      }

      final text = utf8.decode(event.value, allowMalformed: true);
      setState(() {
        _appendMessage('Notification', text, outgoing: false);
        _status = 'Characteristic notification received';
      });
    });

    _readRequestSubscription = _peripheralManager.characteristicReadRequested
        .listen((event) async {
          if (event.characteristic.uuid != _characteristicUuid) {
            await _peripheralManager.respondReadRequestWithError(
              event.request,
              error: GATTError.attributeNotFound,
            );
            return;
          }

          final offset = event.request.offset;
          if (offset > _characteristicValue.length) {
            await _peripheralManager.respondReadRequestWithError(
              event.request,
              error: GATTError.invalidOffset,
            );
            return;
          }

          await _peripheralManager.respondReadRequestWithValue(
            event.request,
            value: _characteristicValue.sublist(offset),
          );

          if (!mounted) {
            return;
          }

          setState(() {
            _appendMessage(
              'Read request',
              utf8.decode(_characteristicValue, allowMalformed: true),
              outgoing: false,
            );
            _status = 'Server handled a read request';
          });
        });

    _writeRequestSubscription = _peripheralManager.characteristicWriteRequested
        .listen((event) async {
          if (event.characteristic.uuid != _characteristicUuid) {
            await _peripheralManager.respondWriteRequest(event.request);
            return;
          }

          final text = utf8.decode(event.request.value, allowMalformed: true);
          _characteristicValue = Uint8List.fromList(event.request.value);
          await _peripheralManager.respondWriteRequest(event.request);
          await _notifySubscribedCentrals(_characteristicValue);
          if (!mounted) {
            return;
          }
          setState(() {
            _appendMessage('Received', text, outgoing: false);
            _status = 'Server received a write request';
          });
        });

    _notifyStateSubscription = _peripheralManager.characteristicNotifyStateChanged
        .listen((event) async {
          if (event.characteristic.uuid != _characteristicUuid) {
            return;
          }

          final index = _subscribedCentrals.indexWhere(
            (central) => central.uuid == event.central.uuid,
          );
          if (event.state) {
            if (index == -1) {
              _subscribedCentrals.add(event.central);
            }
            await _notifySingleCentral(event.central, _characteristicValue);
          } else if (index != -1) {
            _subscribedCentrals.removeAt(index);
          }

          if (!mounted) {
            return;
          }

          setState(() {
            _appendMessage(
              event.state ? 'Subscribed' : 'Unsubscribed',
              '${event.central.uuid}',
              outgoing: false,
            );
            _status = 'Subscriber count: ${_subscribedCentrals.length}';
          });
        });
  }

  void _appendMessage(String label, String text, {required bool outgoing}) {
    _messages.insert(
      0,
      _ChatMessage(
        label: label,
        text: text,
        outgoing: outgoing,
        time: TimeOfDay.now().format(context),
      ),
    );
  }

  Future<bool> _requestBlePermissions({required bool includeAdvertise}) async {
    final permissions = <Permission>[];

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 31) {
        permissions.addAll(<Permission>[
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          if (includeAdvertise) Permission.bluetoothAdvertise,
        ]);
      } else {
        permissions.add(Permission.locationWhenInUse);
      }
    } else {
      permissions.add(Permission.bluetooth);
    }

    final result = await permissions.request();
    return result.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  Future<void> startServer() async {
    final granted = await _requestBlePermissions(includeAdvertise: true);
    if (!granted) {
      setState(() {
        _status = 'BLE advertise permission denied';
      });
      return;
    }

    await _stopClientSession();
    await _peripheralManager.removeAllServices();

    final characteristic = GATTCharacteristic.mutable(
      uuid: _characteristicUuid,
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
      uuid: _serviceUuid,
      isPrimary: true,
      includedServices: const <GATTService>[],
      characteristics: <GATTCharacteristic>[characteristic],
    );

    await _peripheralManager.addService(service);
    await _peripheralManager.startAdvertising(
      Advertisement(
        name: Platform.isWindows ? null : _serverName,
        serviceUUIDs: <UUID>[_serviceUuid],
      ),
    );

    setState(() {
      _actingAsServer = true;
      _advertising = true;
      _subscribed = false;
      _serverCharacteristic = characteristic;
      _characteristicValue = Uint8List.fromList(utf8.encode('Server ready'));
      _status = 'Advertising as $_serverName';
      _messages.clear();
      _appendMessage('System', 'Server is ready to receive', outgoing: false);
      _discoveries.clear();
      _subscribedCentrals.clear();
    });
  }

  Future<void> startClientScan() async {
    final granted = await _requestBlePermissions(includeAdvertise: false);
    if (!granted) {
      setState(() {
        _status = 'BLE scan/connect permission denied';
      });
      return;
    }

    await _stopServerSession();
    await _centralManager.stopDiscovery();

    setState(() {
      _actingAsServer = false;
      _scanning = true;
      _connecting = false;
      _connectedPeripheral = null;
      _chatCharacteristic = null;
      _serverCharacteristic = null;
      _subscribed = false;
      _discoveries.clear();
      _messages.clear();
      _appendMessage('System', 'Scanning for nearby BLE servers', outgoing: false);
      _status = 'Scanning for $_serverName...';
    });

    await _centralManager.startDiscovery(serviceUUIDs: <UUID>[_serviceUuid]);
  }

  Future<void> connectToServer(DiscoveredEventArgs discovery) async {
    await _centralManager.stopDiscovery();

    setState(() {
      _scanning = false;
      _connecting = true;
      _connectedPeripheral = discovery.peripheral;
      _status = 'Connecting to ${discovery.advertisement.name ?? discovery.peripheral.uuid}...';
    });

    await _centralManager.connect(discovery.peripheral);
  }

  Future<void> _discoverChatCharacteristic(Peripheral peripheral) async {
    try {
      if (Platform.isAndroid) {
        await _centralManager.requestMTU(peripheral, mtu: 180);
      }
    } catch (_) {
      // MTU negotiation is optional for this demo.
    }

    final services = await _centralManager.discoverGATT(peripheral);
    GATTCharacteristic? chatCharacteristic;

    for (final service in services) {
      if (service.uuid != _serviceUuid) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _characteristicUuid) {
          chatCharacteristic = characteristic;
          break;
        }
      }
      if (chatCharacteristic != null) {
        break;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _chatCharacteristic = chatCharacteristic;
      _subscribed = false;
      _status = chatCharacteristic == null
          ? 'Connected, but chat characteristic not found'
          : 'Connected to BLE server';
    });
  }

  Future<void> sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _connectedPeripheral == null || _chatCharacteristic == null) {
      return;
    }

    final data = Uint8List.fromList(utf8.encode(text));
    final type =
        _chatCharacteristic!.properties.contains(
              GATTCharacteristicProperty.writeWithoutResponse,
            )
            ? GATTCharacteristicWriteType.withoutResponse
            : GATTCharacteristicWriteType.withResponse;

    await _centralManager.writeCharacteristic(
      _connectedPeripheral!,
      _chatCharacteristic!,
      value: data,
      type: type,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _appendMessage('Sent', text, outgoing: true);
      _messageController.clear();
      _status = 'Message sent to BLE server';
    });
  }

  Future<void> readCharacteristic() async {
    if (_connectedPeripheral == null || _chatCharacteristic == null) {
      return;
    }

    final value = await _centralManager.readCharacteristic(
      _connectedPeripheral!,
      _chatCharacteristic!,
    );
    final text = utf8.decode(value, allowMalformed: true);

    if (!mounted) {
      return;
    }

    setState(() {
      _appendMessage('Read', text, outgoing: false);
      _status = 'Characteristic read completed';
    });
  }

  Future<void> toggleSubscription() async {
    if (_connectedPeripheral == null || _chatCharacteristic == null) {
      return;
    }

    await _centralManager.setCharacteristicNotifyState(
      _connectedPeripheral!,
      _chatCharacteristic!,
      state: !_subscribed,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _subscribed = !_subscribed;
      _appendMessage(
        _subscribed ? 'Subscribed' : 'Unsubscribed',
        'Characteristic updates',
        outgoing: false,
      );
      _status = _subscribed
          ? 'Subscribed to characteristic'
          : 'Unsubscribed from characteristic';
    });
  }

  Future<void> publishServerValue() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    _characteristicValue = Uint8List.fromList(utf8.encode(text));
    await _notifySubscribedCentrals(_characteristicValue);

    if (!mounted) {
      return;
    }

    setState(() {
      _appendMessage('Published', text, outgoing: true);
      _messageController.clear();
      _status = 'Server value published';
    });
  }

  Future<void> _notifySubscribedCentrals(Uint8List value) async {
    for (final central in List<Central>.from(_subscribedCentrals)) {
      await _notifySingleCentral(central, value);
    }
  }

  Future<void> _notifySingleCentral(Central central, Uint8List value) async {
    final characteristic = _serverCharacteristic;
    if (characteristic == null) {
      return;
    }

    final maximumLength = await _peripheralManager.getMaximumNotifyLength(
      central,
    );
    final payload = value.length > maximumLength
        ? value.sublist(0, maximumLength)
        : value;

    await _peripheralManager.notifyCharacteristic(
      central,
      characteristic,
      value: payload,
    );
  }

  Future<void> stopAll() async {
    await _stopClientSession();
    await _stopServerSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Stopped';
      _discoveries.clear();
      _connectedPeripheral = null;
      _chatCharacteristic = null;
      _serverCharacteristic = null;
      _subscribed = false;
      _actingAsServer = false;
      _scanning = false;
      _advertising = false;
      _connecting = false;
      _subscribedCentrals.clear();
    });
  }

  Future<void> _stopClientSession() async {
    if (_scanning) {
      await _centralManager.stopDiscovery();
    }
    if (_connectedPeripheral != null) {
      await _centralManager.disconnect(_connectedPeripheral!);
    }
  }

  Future<void> _stopServerSession() async {
    if (_advertising) {
      await _peripheralManager.stopAdvertising();
    }
  }

  @override
  void dispose() {
    unawaited(_centralStateSubscription?.cancel());
    unawaited(_peripheralStateSubscription?.cancel());
    unawaited(_discoveredSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_notifiedSubscription?.cancel());
    unawaited(_readRequestSubscription?.cancel());
    unawaited(_writeRequestSubscription?.cancel());
    unawaited(_notifyStateSubscription?.cancel());
    unawaited(_centralManager.stopDiscovery());
    if (_connectedPeripheral != null) {
      unawaited(_centralManager.disconnect(_connectedPeripheral!));
    }
    if (_advertising) {
      unawaited(_peripheralManager.stopAdvertising());
    }
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !_actingAsServer &&
        _connectedPeripheral != null &&
        _chatCharacteristic != null;
    final canRead = canSend;
    final canSubscribe = canSend;
    final serverValue = utf8.decode(_characteristicValue, allowMalformed: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Chat'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _HeaderCard(
              status: _status,
              mode: _actingAsServer ? 'Receiver' : 'Sender',
              connected: _connectedPeripheral != null,
              advertising: _advertising,
              scanning: _scanning,
              subscribed: _subscribed,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton(
                  onPressed: startServer,
                  child: const Text('Be Server'),
                ),
                ElevatedButton(
                  onPressed: startClientScan,
                  child: const Text('Be Client'),
                ),
                OutlinedButton(
                  onPressed: stopAll,
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_actingAsServer && _discoveries.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _discoveries.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final discovery = _discoveries[index];
                    return _DiscoveryCard(
                      discovery: discovery,
                      enabled: !_connecting,
                      onTap: () => connectToServer(discovery),
                    );
                  },
                ),
              )
            else if (!_actingAsServer)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Tap "Be Client" to find nearby BLE chat servers.',
                ),
              ),
            const SizedBox(height: 12),
            if (_actingAsServer)
              _ServerInfoCard(
                serverValue: serverValue,
                subscribers: _subscribedCentrals.length,
              )
            else
              _ActionCard(
                canRead: canRead,
                canWrite: canSend,
                canSubscribe: canSubscribe,
                subscribed: _subscribed,
                onRead: readCharacteristic,
                onWrite: sendMessage,
                onToggleSubscribe: toggleSubscription,
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _messages.isEmpty
                  ? const _EmptyChatState()
                  : ListView.separated(
                      reverse: true,
                      itemCount: _messages.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _ChatBubble(message: _messages[index]),
                    ),
            ),
            const SizedBox(height: 12),
            _ComposerCard(
              controller: _messageController,
              enabled: canSend || _actingAsServer,
              hintText: _actingAsServer
                  ? 'Type a value to publish to subscribers'
                  : canSend
                  ? 'Type a chat message'
                  : 'Connect first to send a message',
              buttonLabel: _actingAsServer ? 'Publish' : 'Send',
              onSend: _actingAsServer
                  ? publishServerValue
                  : canSend
                  ? sendMessage
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.status,
    required this.mode,
    required this.connected,
    required this.advertising,
    required this.scanning,
    required this.subscribed,
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
              _MiniBadge(
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
                const _MiniBadge(text: 'Subscribed'),
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

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.discovery,
    required this.enabled,
    required this.onTap,
  });

  final DiscoveredEventArgs discovery;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  discovery.advertisement.name ?? 'BLE Server',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'RSSI: ${discovery.rssi}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  discovery.peripheral.uuid.toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(Icons.arrow_forward_ios, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.canRead,
    required this.canWrite,
    required this.canSubscribe,
    required this.subscribed,
    required this.onRead,
    required this.onWrite,
    required this.onToggleSubscribe,
  });

  final bool canRead;
  final bool canWrite;
  final bool canSubscribe;
  final bool subscribed;
  final VoidCallback onRead;
  final VoidCallback onWrite;
  final VoidCallback onToggleSubscribe;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonal(
              onPressed: canRead ? onRead : null,
              child: const Text('Read'),
            ),
            FilledButton.tonal(
              onPressed: canWrite ? onWrite : null,
              child: const Text('Write'),
            ),
            FilledButton.tonal(
              onPressed: canSubscribe ? onToggleSubscribe : null,
              child: Text(subscribed ? 'Unsubscribe' : 'Subscribe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerInfoCard extends StatelessWidget {
  const _ServerInfoCard({
    required this.serverValue,
    required this.subscribers,
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
            _MiniBadge(text: '$subscribers listener(s)'),
          ],
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = message.outgoing
        ? Colors.blue.shade600
        : Colors.grey.shade200;
    final textColor = message.outgoing ? Colors.white : Colors.black87;

    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(message.outgoing ? 18 : 6),
              bottomRight: Radius.circular(message.outgoing ? 6 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                message.label,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message.text,
                style: TextStyle(color: textColor, height: 1.3),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  message.time,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.75),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.buttonLabel,
    required this.onSend,
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
