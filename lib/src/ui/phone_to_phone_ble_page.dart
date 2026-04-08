import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:permission_handler/permission_handler.dart';

import 'phone_to_phone_ble/models/chat_message.dart';
import 'phone_to_phone_ble/widgets/action_card.dart';
import 'phone_to_phone_ble/widgets/chat_bubble.dart';
import 'phone_to_phone_ble/widgets/composer_card.dart';
import 'phone_to_phone_ble/widgets/discovery_card.dart';
import 'phone_to_phone_ble/widgets/empty_chat_state.dart';
import 'phone_to_phone_ble/widgets/header_card.dart';
import 'phone_to_phone_ble/widgets/server_info_card.dart';

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
  final List<ChatMessage> _messages = <ChatMessage>[];
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
      ChatMessage(
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
          : 'Connected. Enabling live updates...';
    });

    if (chatCharacteristic != null) {
      await _enableRealtimeUpdates(peripheral, chatCharacteristic);
    }
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

  Future<void> _enableRealtimeUpdates(
    Peripheral peripheral,
    GATTCharacteristic characteristic,
  ) async {
    if (_subscribed) {
      return;
    }

    await _centralManager.setCharacteristicNotifyState(
      peripheral,
      characteristic,
      state: true,
    );

    final initialValue = await _centralManager.readCharacteristic(
      peripheral,
      characteristic,
    );
    final initialText = utf8.decode(initialValue, allowMalformed: true).trim();

    if (!mounted) {
      return;
    }

    setState(() {
      _subscribed = true;
      if (initialText.isNotEmpty) {
        _appendMessage('Live value', initialText, outgoing: false);
      }
      _status = 'Connected with real-time updates';
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
            HeaderCard(
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
                height: 144,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _discoveries.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final discovery = _discoveries[index];
                    return DiscoveryCard(
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
              ServerInfoCard(
                serverValue: serverValue,
                subscribers: _subscribedCentrals.length,
              )
            else
              ActionCard(
                canWrite: canSend,
                subscribed: _subscribed,
                onWrite: sendMessage,
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _messages.isEmpty
                  ? const EmptyChatState()
                  : ListView.separated(
                      reverse: true,
                      itemCount: _messages.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          ChatBubble(message: _messages[index]),
                    ),
            ),
            const SizedBox(height: 12),
            ComposerCard(
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
