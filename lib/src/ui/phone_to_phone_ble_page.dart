import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
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
  static const int _payloadChunkSize = 160;
  static const int _maxStreamBytes = 500 * 1024;
  static const int _frameStartByte = 0x02;
  static const int _frameEndByte = 0x03;

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
  int _currentTab = 0;
  Timer? _serverInputDebounce;
  String _lastServerPayload = '';
  bool _sendingJsonFile = false;
  Peripheral? _connectedPeripheral;
  GATTCharacteristic? _chatCharacteristic;
  GATTCharacteristic? _serverCharacteristic;
  Uint8List _characteristicValue = Uint8List.fromList(
    utf8.encode('Server ready'),
  );
  final List<Central> _subscribedCentrals = <Central>[];
  final BytesBuilder _clientReceiveBuffer = BytesBuilder(copy: false);
  final BytesBuilder _serverReceiveBuffer = BytesBuilder(copy: false);
  bool _clientReceivingChunks = false;
  bool _serverReceivingChunks = false;

  String _consoleTimestamp() => DateTime.now().toIso8601String();

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  List<Uint8List> _chunkBytes(Uint8List data, int size) {
    if (data.isEmpty) {
      return <Uint8List>[Uint8List(0)];
    }

    final chunks = <Uint8List>[];
    for (int start = 0; start < data.length; start += size) {
      final end = (start + size < data.length) ? start + size : data.length;
      chunks.add(Uint8List.fromList(data.sublist(start, end)));
    }
    return chunks;
  }

  Uint8List _startFrame() => Uint8List.fromList(<int>[_frameStartByte]);

  Uint8List _endFrame() => Uint8List.fromList(<int>[_frameEndByte]);

  bool _isStartFrame(Uint8List data) =>
      data.length == 1 && data.first == _frameStartByte;

  bool _isEndFrame(Uint8List data) =>
      data.length == 1 && data.first == _frameEndByte;

  String? _consumeIncomingPacket(
    Uint8List value, {
    required BytesBuilder buffer,
    required bool isReceivingChunks,
    required void Function(bool value) setReceivingChunks,
  }) {
    if (_isStartFrame(value)) {
      buffer.clear();
      setReceivingChunks(true);
      return null;
    }

    if (_isEndFrame(value)) {
      final complete = buffer.takeBytes();
      setReceivingChunks(false);
      return utf8.decode(complete, allowMalformed: true);
    }

    if (isReceivingChunks) {
      buffer.add(value);
      return null;
    }

    return utf8.decode(value, allowMalformed: true);
  }

  String _previewPayload(String text, {int maxChars = 180}) {
    final normalized = text.replaceAll('\n', r'\n');
    if (normalized.length <= maxChars) {
      return normalized;
    }
    return '${normalized.substring(0, maxChars)}...';
  }

  void _logBleEvent(
    String action, {
    String? role,
    String? direction,
    String? payload,
    int? bytes,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final parts = <String>[
      'time=${_consoleTimestamp()}',
      if (role != null) 'role=$role',
      if (direction != null) 'direction=$direction',
      if (bytes != null) 'bytes=$bytes',
      ...extra.entries.map((entry) => '${entry.key}=${entry.value}'),
      if (payload != null) 'payload=${_previewPayload(payload)}',
    ];
    final message = '[BLE] $action | ${parts.join(' | ')}';
    debugPrint(message);
    log(message, name: 'BLE_JSON_CHAT');
  }

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_handleComposerChanged);
    _listenToManagers();
  }

  void _handleComposerChanged() {
    if (!_actingAsServer || _sendingJsonFile) {
      return;
    }

    _serverInputDebounce?.cancel();

    final text = _messageController.text.trim();
    if (text.isEmpty || text == _lastServerPayload) {
      return;
    }

    _serverInputDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!_actingAsServer || !mounted) {
        return;
      }

      final latestText = _messageController.text.trim();
      if (latestText.isEmpty || latestText == _lastServerPayload) {
        return;
      }

      await _publishServerText(latestText, clearComposer: false);
    });
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
      final hasService = event.advertisement.serviceUUIDs.contains(
        _serviceUuid,
      );
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
      if (_connectedPeripheral != null &&
          event.peripheral != _connectedPeripheral) {
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

      _logBleEvent(
        'notification received',
        role: 'client',
        direction: 'receive',
        payload: utf8.decode(event.value, allowMalformed: true),
        bytes: event.value.length,
      );
      final text = _consumeIncomingPacket(
        event.value,
        buffer: _clientReceiveBuffer,
        isReceivingChunks: _clientReceivingChunks,
        setReceivingChunks: (value) => _clientReceivingChunks = value,
      );
      if (text == null) {
        return;
      }
      final textBytes = utf8.encode(text).length;
      setState(() {
        _upsertMessage('Notification', text, outgoing: false);
        _status = 'Stream received: ${_formatBytes(textBytes)}';
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
          _logBleEvent(
            'read request served',
            role: 'server',
            direction: 'send',
            payload: utf8.decode(_characteristicValue, allowMalformed: true),
            bytes: _characteristicValue.length,
            extra: <String, Object?>{
              'offset': offset,
            },
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

          await _peripheralManager.respondWriteRequest(event.request);
          _logBleEvent(
            'write request received',
            role: 'server',
            direction: 'receive',
            payload: utf8.decode(event.request.value, allowMalformed: true),
            bytes: event.request.value.length,
            extra: <String, Object?>{
              'central': event.central.uuid,
            },
          );
          final text = _consumeIncomingPacket(
            event.request.value,
            buffer: _serverReceiveBuffer,
            isReceivingChunks: _serverReceivingChunks,
            setReceivingChunks: (value) => _serverReceivingChunks = value,
          );
          if (text == null) {
            return;
          }
          _characteristicValue = Uint8List.fromList(utf8.encode(text));
          await _notifySubscribedCentrals(_characteristicValue);
          if (!mounted) {
            return;
          }
          final textBytes = utf8.encode(text).length;
          setState(() {
            _appendMessage('Received', text, outgoing: false);
            _status = 'Server received stream: ${_formatBytes(textBytes)}';
          });
        });

    _notifyStateSubscription = _peripheralManager
        .characteristicNotifyStateChanged
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
            _logBleEvent(
              'client subscribed',
              role: 'server',
              direction: 'system',
              extra: <String, Object?>{
                'central': event.central.uuid,
                'subscribers': _subscribedCentrals.length,
              },
            );
            await _notifySingleCentral(event.central, _characteristicValue);
          } else if (index != -1) {
            _subscribedCentrals.removeAt(index);
            _logBleEvent(
              'client unsubscribed',
              role: 'server',
              direction: 'system',
              extra: <String, Object?>{
                'central': event.central.uuid,
                'subscribers': _subscribedCentrals.length,
              },
            );
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

  void _upsertMessage(String label, String text, {required bool outgoing}) {
    final message = ChatMessage(
      label: label,
      text: text,
      outgoing: outgoing,
      time: TimeOfDay.now().format(context),
    );

    final index = _messages.indexWhere(
      (item) => item.label == label && item.outgoing == outgoing,
    );

    if (index == -1) {
      _messages.insert(0, message);
      return;
    }

    _messages
      ..removeAt(index)
      ..insert(0, message);
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
      _currentTab = 2;
      _subscribed = false;
      _lastServerPayload = 'Server ready';
      _serverCharacteristic = characteristic;
      _characteristicValue = Uint8List.fromList(utf8.encode('Server ready'));
      _status = 'Advertising as $_serverName';
      _messages.clear();
      _appendMessage('System', 'Server is ready to receive', outgoing: false);
      _discoveries.clear();
      _subscribedCentrals.clear();
      _clientReceiveBuffer.clear();
      _serverReceiveBuffer.clear();
      _clientReceivingChunks = false;
      _serverReceivingChunks = false;
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

    _serverInputDebounce?.cancel();
    await _stopServerSession();
    await _centralManager.stopDiscovery();

    setState(() {
      _actingAsServer = false;
      _currentTab = 1;
      _scanning = true;
      _connecting = false;
      _lastServerPayload = '';
      _connectedPeripheral = null;
      _chatCharacteristic = null;
      _serverCharacteristic = null;
      _subscribed = false;
      _discoveries.clear();
      _messages.clear();
      _appendMessage(
        'System',
        'Scanning for nearby BLE servers',
        outgoing: false,
      );
      _status = 'Scanning for $_serverName...';
      _clientReceiveBuffer.clear();
      _serverReceiveBuffer.clear();
      _clientReceivingChunks = false;
      _serverReceivingChunks = false;
    });

    await _centralManager.startDiscovery(serviceUUIDs: <UUID>[_serviceUuid]);
  }

  Future<void> connectToServer(DiscoveredEventArgs discovery) async {
    await _centralManager.stopDiscovery();

    setState(() {
      _currentTab = 2;
      _scanning = false;
      _connecting = true;
      _connectedPeripheral = discovery.peripheral;
      _status =
          'Connecting to ${discovery.advertisement.name ?? discovery.peripheral.uuid}...';
    });

    await _centralManager.connect(discovery.peripheral);
  }

  Future<void> _discoverChatCharacteristic(Peripheral peripheral) async {
    try {
      if (Platform.isAndroid) {
        await _centralManager.requestMTU(peripheral, mtu: 180);
      }
    } catch (e, s) {
      log("error $e , line $s");
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
    if (text.isEmpty ||
        _connectedPeripheral == null ||
        _chatCharacteristic == null) {
      return;
    }

    await _sendClientTextInChunks(text);
    _logBleEvent(
      'message sent',
      role: 'client',
      direction: 'send',
      payload: text,
      bytes: utf8.encode(text).length,
      extra: <String, Object?>{
        'target': _connectedPeripheral!.uuid,
        'chunkSize': _payloadChunkSize,
      },
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
    _logBleEvent(
      'initial value read',
      role: 'client',
      direction: 'receive',
      payload: initialText,
      bytes: initialValue.length,
      extra: <String, Object?>{
        'source': peripheral.uuid,
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _subscribed = true;
      if (initialText.isNotEmpty) {
        _upsertMessage('Notification', initialText, outgoing: false);
      }
      _status = 'Connected with real-time updates';
    });
  }

  Future<void> publishServerValue() async {
    final text = _messageController.text.trim();
    await _publishServerText(text, clearComposer: false);
  }

  Future<void> _publishServerText(
    String text, {
    required bool clearComposer,
  }) async {
    if (text.isEmpty) {
      return;
    }

    _characteristicValue = Uint8List.fromList(utf8.encode(text));
    _logBleEvent(
      'server publish',
      role: 'server',
      direction: 'send',
      payload: text,
      bytes: _characteristicValue.length,
      extra: <String, Object?>{
        'subscribers': _subscribedCentrals.length,
        'chunkSize': _payloadChunkSize,
      },
    );
    await _notifySubscribedCentrals(_characteristicValue);

    if (!mounted) {
      return;
    }

    setState(() {
      _lastServerPayload = text;
      _upsertMessage('Live update', text, outgoing: true);
      if (clearComposer) {
        _messageController.clear();
      }
      _status = 'Server value updated in real time';
    });
  }

  bool _isJsonPayload(String text) {
    final value = text.trimLeft();
    return value.startsWith('{') || value.startsWith('[');
  }

  Future<void> _pickAndSendJsonFile() async {
    if (_sendingJsonFile) {
      _logBleEvent(
        'json file skipped',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'system',
        extra: const <String, Object?>{
          'reason': 'already sending',
        },
      );
      return;
    }

    if (_actingAsServer && _subscribedCentrals.isEmpty) {
      _logBleEvent(
        'json file blocked',
        role: 'server',
        direction: 'system',
        extra: const <String, Object?>{
          'reason': 'no subscribed client',
        },
      );
      setState(() {
        _status = 'Wait for the second phone to show Subscribed before sending a JSON file';
      });
      return;
    }

    if (!_actingAsServer &&
        (_connectedPeripheral == null || _chatCharacteristic == null)) {
      _logBleEvent(
        'json file blocked',
        role: 'client',
        direction: 'system',
        extra: const <String, Object?>{
          'reason': 'client not connected',
        },
      );
      setState(() {
        _status = 'Connect first before sending a JSON file';
      });
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      withData: false,
    );

    final path = result?.files.single.path;
    if (path == null) {
      _logBleEvent(
        'json file picker cancelled',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'system',
      );
      return;
    }

    try {
      _logBleEvent(
        'json file selected',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'system',
        extra: <String, Object?>{
          'path': path,
        },
      );
      final raw = await File(path).readAsString();
      final rawBytes = utf8.encode(raw).length;
      _logBleEvent(
        'json file loaded',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'system',
        extra: <String, Object?>{
          'chars': raw.length,
          'bytes': rawBytes,
        },
      );

      if (!mounted) {
        return;
      }

      if (raw.trim().isEmpty) {
        setState(() {
          _status = 'Selected JSON file is empty';
        });
        return;
      }

      if (rawBytes > _maxStreamBytes) {
        setState(() {
          _status =
              'File too large for one stream. Max ${_formatBytes(_maxStreamBytes)}';
        });
        _logBleEvent(
          'json stream blocked',
          role: _actingAsServer ? 'server' : 'client',
          direction: 'system',
          extra: <String, Object?>{
            'reason': 'file too large',
            'bytes': rawBytes,
            'limit': _maxStreamBytes,
          },
        );
        return;
      }

      await _sendTextStream(
        raw,
        sourceLabel: 'JSON file',
      );
    } catch (e, s) {
      _logBleEvent(
        'json file send error',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'system',
        extra: <String, Object?>{
          'error': e,
        },
      );
      log('JSON file send error', error: e, stackTrace: s);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'JSON file error: $e';
      });
    }
  }

  Future<void> _sendTextStream(
    String text, {
    required String sourceLabel,
  }) async {
    final bytes = utf8.encode(text).length;

    if (mounted) {
      setState(() {
        _sendingJsonFile = true;
        _status = 'Streaming $sourceLabel: ${_formatBytes(bytes)}';
      });
    } else {
      _sendingJsonFile = true;
    }

    _logBleEvent(
      'stream started',
      role: _actingAsServer ? 'server' : 'client',
      direction: 'send',
      extra: <String, Object?>{
        'source': sourceLabel,
        'bytes': bytes,
        'chunkSize': _payloadChunkSize,
      },
    );

    try {
      await _sendSinglePayloadText(text);

      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Completed $sourceLabel stream: ${_formatBytes(bytes)}';
      });
      _logBleEvent(
        'stream completed',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'send',
        extra: <String, Object?>{
          'source': sourceLabel,
          'bytes': bytes,
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingJsonFile = false;
        });
      } else {
        _sendingJsonFile = false;
      }
    }
  }

  List<dynamic> _extractJsonItems(dynamic decoded) {
    if (decoded is List) {
      return List<dynamic>.from(decoded);
    }

    if (decoded is Map && decoded['items'] is List) {
      return List<dynamic>.from(decoded['items'] as List);
    }

    if (decoded == null) {
      return <dynamic>[];
    }

    return <dynamic>[decoded];
  }

  List<dynamic> _extractRawTextItems(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return <dynamic>[];
    }

    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isNotEmpty) {
      return lines;
    }

    const int chunkSize = 160;
    final chunks = <String>[];
    for (int index = 0; index < normalized.length; index += chunkSize) {
      final end = (index + chunkSize < normalized.length)
          ? index + chunkSize
          : normalized.length;
      chunks.add(normalized.substring(index, end));
    }
    return chunks;
  }

  dynamic _decodeJsonContent(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException catch (error) {
      _logBleEvent(
        'json decode failed',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'system',
        extra: <String, Object?>{
          'error': error.message,
          'offset': error.offset,
        },
      );

      final sanitized = _sanitizeJsonContent(raw);
      if (sanitized != raw) {
        _logBleEvent(
          'json decode retry',
          role: _actingAsServer ? 'server' : 'client',
          direction: 'system',
          extra: const <String, Object?>{
            'reason': 'sanitized content',
          },
        );
        return jsonDecode(sanitized);
      }

      rethrow;
    }
  }

  String _sanitizeJsonContent(String raw) {
    var sanitized = raw;

    // Remove UTF-8 BOM if present.
    if (sanitized.isNotEmpty && sanitized.codeUnitAt(0) == 0xFEFF) {
      sanitized = sanitized.substring(1);
    }

    // Remove trailing commas before closing object/array brackets.
    sanitized = sanitized.replaceAll(
      RegExp(r',(\s*[\]}])'),
      r'$1',
    );

    return sanitized;
  }

  Future<void> _sendJsonItemsInSteps(List<dynamic> items) async {
    const int batchSize = 100;

    setState(() {
      _sendingJsonFile = true;
      _status = 'Loaded ${items.length} JSON item(s)';
    });
    _logBleEvent(
      'json file send started',
      role: _actingAsServer ? 'server' : 'client',
      direction: 'send',
      extra: <String, Object?>{
        'items': items.length,
        'batchSize': batchSize,
      },
    );

    try {
      final totalBatches = (items.length / batchSize).ceil();

      for (int batchStart = 0; batchStart < items.length; batchStart += batchSize) {
        final batchIndex = (batchStart ~/ batchSize) + 1;
        final batchItems = items.skip(batchStart).take(batchSize).toList();
        _logBleEvent(
          'json batch started',
          role: _actingAsServer ? 'server' : 'client',
          direction: 'send',
          extra: <String, Object?>{
            'batch': '$batchIndex/$totalBatches',
            'items': batchItems.length,
          },
        );

        for (int i = 0; i < batchItems.length; i++) {
          final item = batchItems[i];
          final payload = item is String ? item : jsonEncode(item);

          await _sendSinglePayloadText(payload);

          if (!mounted) {
            return;
          }

          setState(() {
            _status =
                'Sending JSON file batch $batchIndex/$totalBatches item ${i + 1}/${batchItems.length}';
          });

          await Future<void>.delayed(const Duration(milliseconds: 60));
        }

        _logBleEvent(
          'json batch finished',
          role: _actingAsServer ? 'server' : 'client',
          direction: 'send',
          extra: <String, Object?>{
            'batch': '$batchIndex/$totalBatches',
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Completed JSON file send: ${items.length} item(s)';
      });
      _logBleEvent(
        'json file send completed',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'send',
        extra: <String, Object?>{
          'items': items.length,
        },
      );
    } catch (e, s) {
      _logBleEvent(
        'json batch send failed',
        role: _actingAsServer ? 'server' : 'client',
        direction: 'system',
        extra: <String, Object?>{
          'error': e,
        },
      );
      log('JSON batch send failed', error: e, stackTrace: s);
      if (mounted) {
        setState(() {
          _status = 'JSON batch send failed: $e';
        });
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _sendingJsonFile = false;
        });
      } else {
        _sendingJsonFile = false;
      }
    }
  }

  Future<void> _sendSinglePayloadText(String text) async {
    if (_actingAsServer) {
      await _publishServerText(text, clearComposer: false);
      return;
    }

    if (_connectedPeripheral == null || _chatCharacteristic == null) {
      _logBleEvent(
        'single payload skipped',
        role: 'client',
        direction: 'system',
        extra: const <String, Object?>{
          'reason': 'no connected peripheral/characteristic',
        },
      );
      return;
    }

    await _sendClientTextInChunks(text);
    _logBleEvent(
      'single payload sent',
      role: 'client',
      direction: 'send',
      payload: text,
      bytes: utf8.encode(text).length,
      extra: <String, Object?>{
        'target': _connectedPeripheral!.uuid,
        'chunkSize': _payloadChunkSize,
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _upsertMessage('Sent', text, outgoing: true);
    });
  }

  Future<void> _notifySubscribedCentrals(Uint8List value) async {
    for (final central in List<Central>.from(_subscribedCentrals)) {
      await _notifySingleCentral(central, value);
    }
  }

  Future<void> _sendClientTextInChunks(String text) async {
    final peripheral = _connectedPeripheral;
    final characteristic = _chatCharacteristic;
    if (peripheral == null || characteristic == null) {
      return;
    }

    final data = Uint8List.fromList(utf8.encode(text));
    final type =
        characteristic.properties.contains(
          GATTCharacteristicProperty.writeWithoutResponse,
        )
        ? GATTCharacteristicWriteType.withoutResponse
        : GATTCharacteristicWriteType.withResponse;
    final chunks = _chunkBytes(data, _payloadChunkSize);

    await _centralManager.writeCharacteristic(
      peripheral,
      characteristic,
      value: _startFrame(),
      type: type,
    );
    _logBleEvent(
      'client frame start sent',
      role: 'client',
      direction: 'send',
      bytes: 1,
      extra: <String, Object?>{
        'target': peripheral.uuid,
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 24));

    for (int index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      await _centralManager.writeCharacteristic(
        peripheral,
        characteristic,
        value: chunk,
        type: type,
      );
      _logBleEvent(
        'client chunk sent',
        role: 'client',
        direction: 'send',
        payload: utf8.decode(chunk, allowMalformed: true),
        bytes: chunk.length,
        extra: <String, Object?>{
          'target': peripheral.uuid,
          'chunk': '${index + 1}/${chunks.length}',
          'writeType': type.name,
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }

    await _centralManager.writeCharacteristic(
      peripheral,
      characteristic,
      value: _endFrame(),
      type: type,
    );
    _logBleEvent(
      'client frame end sent',
      role: 'client',
      direction: 'send',
      bytes: 1,
      extra: <String, Object?>{
        'target': peripheral.uuid,
      },
    );
  }

  Future<void> _notifySingleCentral(Central central, Uint8List value) async {
    final characteristic = _serverCharacteristic;
    if (characteristic == null) {
      return;
    }

    final maximumLength = await _peripheralManager.getMaximumNotifyLength(
      central,
    );
    if (maximumLength <= 0) {
      _logBleEvent(
        'notification skipped',
        role: 'server',
        direction: 'system',
        extra: <String, Object?>{
          'target': central.uuid,
          'reason': 'max notify length is 0',
        },
      );
      return;
    }
    final chunkSize = maximumLength < _payloadChunkSize
        ? maximumLength
        : _payloadChunkSize;
    final chunks = _chunkBytes(value, chunkSize);

    await _peripheralManager.notifyCharacteristic(
      central,
      characteristic,
      value: _startFrame(),
    );
    _logBleEvent(
      'notification frame start sent',
      role: 'server',
      direction: 'send',
      bytes: 1,
      extra: <String, Object?>{
        'target': central.uuid,
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 24));

    for (int index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      await _peripheralManager.notifyCharacteristic(
        central,
        characteristic,
        value: chunk,
      );
      _logBleEvent(
        'notification chunk sent',
        role: 'server',
        direction: 'send',
        payload: utf8.decode(chunk, allowMalformed: true),
        bytes: chunk.length,
        extra: <String, Object?>{
          'target': central.uuid,
          'chunk': '${index + 1}/${chunks.length}',
          'maxNotifyLength': maximumLength,
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }

    await _peripheralManager.notifyCharacteristic(
      central,
      characteristic,
      value: _endFrame(),
    );
    _logBleEvent(
      'notification frame end sent',
      role: 'server',
      direction: 'send',
      bytes: 1,
      extra: <String, Object?>{
        'target': central.uuid,
      },
    );
  }

  Future<void> stopAll() async {
    _serverInputDebounce?.cancel();
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
      _clientReceiveBuffer.clear();
      _serverReceiveBuffer.clear();
      _clientReceivingChunks = false;
      _serverReceivingChunks = false;
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
    _serverInputDebounce?.cancel();
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
    final canSend =
        !_actingAsServer &&
        _connectedPeripheral != null &&
        _chatCharacteristic != null;
    final serverValue = utf8.decode(_characteristicValue, allowMalformed: true);
    final hasSession =
        _scanning ||
        _advertising ||
        _connecting ||
        _connectedPeripheral != null ||
        _messages.isNotEmpty ||
        _subscribedCentrals.isNotEmpty;
    final Widget currentBody = _currentTab == 0
        ? _buildHomeTab(
            canSend: canSend,
            serverValue: serverValue,
            hasSession: hasSession,
          )
        : _currentTab == 1
        ? _buildScanTab(hasSession: hasSession)
        : _buildChatTab(canSend: canSend, serverValue: serverValue);

    return Scaffold(
      appBar: AppBar(title: const Text('BLE Chat')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: currentBody,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (int index) {
          setState(() {
            _currentTab = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_searching),
            selectedIcon: Icon(Icons.radar),
            label: 'Scan Device',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat),
            label: 'Connect',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab({
    required bool canSend,
    required String serverValue,
    required bool hasSession,
  }) {
    return ListView(
      children: <Widget>[
        HeaderCard(
          status: _status,
          mode: _actingAsServer ? 'Receiver' : 'Sender',
          connected: _connectedPeripheral != null,
          advertising: _advertising,
          scanning: _scanning,
          subscribed: _subscribed,
        ),
        const SizedBox(height: 16),
        const _SectionTitle(
          title: 'Action Buttons',
          subtitle:
              'Start server mode, scan devices, or stop the current BLE session.',
        ),
        const SizedBox(height: 12),
        _buildActionButtons(hasSession: hasSession),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _InfoChip(
              label: 'Mode',
              value: _actingAsServer ? 'Server' : 'Client',
            ),
            _InfoChip(label: 'Devices', value: '${_discoveries.length}'),
            _InfoChip(label: 'Messages', value: '${_messages.length}'),
            _InfoChip(label: 'Subscribe', value: _subscribed ? 'On' : 'Off'),
          ],
        ),
        const SizedBox(height: 16),
        const _SectionTitle(
          title: 'Chat / Server Info',
          subtitle: 'Quick status for the active connection.',
        ),
        const SizedBox(height: 12),
        if( !_actingAsServer)
            ActionCard(
                canWrite: canSend,
                subscribed: _subscribed,
                onWrite: sendMessage,
              ),
      ],
    );
  }

  Widget _buildScanTab({required bool hasSession}) {
    return Column(
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
        const SizedBox(height: 16),
        const _SectionTitle(
          title: 'Device Discovery List',
          subtitle: 'Scan and connect to nearby BLE devices.',
        ),
        const SizedBox(height: 12),
        _buildActionButtons(hasSession: hasSession),
        const SizedBox(height: 16),
        Expanded(
          child: !_actingAsServer && _discoveries.isNotEmpty
              ? ListView.separated(
                  itemCount: _discoveries.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final discovery = _discoveries[index];
                    return DiscoveryCard(
                      discovery: discovery,
                      enabled: !_connecting,
                      onTap: () => connectToServer(discovery),
                    );
                  },
                )
              : _SimpleHint(
                  text: _actingAsServer
                      ? 'You are in server mode. Switch to client mode to scan devices.'
                      : 'Tap "Be Client" to start scanning for nearby BLE servers.',
                ),
        ),
      ],
    );
  }

  Widget _buildChatTab({required bool canSend, required String serverValue}) {
    return Column(
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
          onAttach: canSend || _actingAsServer ? _pickAndSendJsonFile : null,
          hintText: _actingAsServer
              ? 'Type text or tap + for JSON file'
              : canSend
              ? 'Type a chat message or tap + for JSON file'
              : 'Connect first to send a message',
          buttonLabel: 'Send',
          showButton: !_actingAsServer,
          onSend: canSend
              ? sendMessage
              : null,
        ),
      ],
    );
  }

  Widget _buildActionButtons({required bool hasSession}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        FilledButton.icon(
          onPressed: startServer,
          icon: const Icon(Icons.settings_input_antenna),
          label: const Text('Be Server'),
        ),
        FilledButton.tonalIcon(
          onPressed: startClientScan,
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Be Client'),
        ),
        OutlinedButton.icon(
          onPressed: hasSession ? stopAll : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SimpleHint extends StatelessWidget {
  const _SimpleHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
