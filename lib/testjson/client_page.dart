import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'ble_json_config.dart';
import 'ble_permissions.dart';
import 'client_chat_page.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  final CentralManager _central = CentralManager();
  final List<DiscoveredEventArgs> _discoveries = <DiscoveredEventArgs>[];

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>?
  _stateSubscription;
  StreamSubscription<DiscoveredEventArgs>? _discoveredSubscription;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>?
  _connectionSubscription;

  String _status = 'Ready to scan';
  bool _scanning = false;
  bool _connecting = false;
  bool _openingChat = false;
  Peripheral? _targetPeripheral;
  GATTCharacteristic? _targetCharacteristic;

  @override
  void initState() {
    super.initState();
    _listenToCentral();
    unawaited(scan());
  }

  void _listenToCentral() {
    _stateSubscription = _central.stateChanged.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Central state: ${event.state}';
      });
    });

    _discoveredSubscription = _central.discovered.listen((event) {
      final hasService = event.advertisement.serviceUUIDs.contains(
        kBleJsonServiceUuid,
      );
      final hasName = event.advertisement.name == kBleJsonServerName;
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
        _status = 'Found ${_discoveries.length} BLE JSON server(s)';
      });
    });

    _connectionSubscription = _central.connectionStateChanged.listen((event) async {
      if (_targetPeripheral != null && event.peripheral != _targetPeripheral) {
        return;
      }

      if (!mounted) {
        return;
      }

      if (event.state == ConnectionState.connected) {
        setState(() {
          _connecting = false;
          _status = 'Connected. Discovering JSON characteristic...';
        });

        final characteristic = await _discoverJsonCharacteristic(event.peripheral);
        if (!mounted || characteristic == null || _openingChat) {
          return;
        }

        _openingChat = true;
        _targetCharacteristic = characteristic;

        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ClientChatPage(
              centralManager: _central,
              peripheral: event.peripheral,
              characteristic: characteristic,
            ),
          ),
        );

        _openingChat = false;
        if (!mounted) {
          return;
        }

        setState(() {
          _status = 'Returned from chat';
        });
      } else {
        setState(() {
          _connecting = false;
          _targetPeripheral = null;
          _targetCharacteristic = null;
          _status = 'Disconnected';
        });
      }
    });
  }

  Future<void> scan() async {
    final granted = await requestBlePermissions(includeAdvertise: false);
    if (!granted) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'BLE scan/connect permission denied';
      });
      return;
    }

    await _central.stopDiscovery();
    if (!mounted) {
      return;
    }

    setState(() {
      _discoveries.clear();
      _scanning = true;
      _status = 'Scanning for $kBleJsonServerName...';
    });

    await _central.startDiscovery(serviceUUIDs: <UUID>[kBleJsonServiceUuid]);
  }

  Future<void> connectToServer(DiscoveredEventArgs discovery) async {
    await _central.stopDiscovery();

    if (!mounted) {
      return;
    }

    setState(() {
      _scanning = false;
      _connecting = true;
      _targetPeripheral = discovery.peripheral;
      _status =
          'Connecting to ${discovery.advertisement.name ?? discovery.peripheral.uuid}...';
    });

    await _central.connect(discovery.peripheral);
  }

  Future<GATTCharacteristic?> _discoverJsonCharacteristic(
    Peripheral peripheral,
  ) async {
    try {
      if (Platform.isAndroid) {
        await _central.requestMTU(peripheral, mtu: 180);
      }
    } catch (_) {
      // MTU request is optional.
    }

    final services = await _central.discoverGATT(peripheral);

    for (final service in services) {
      if (service.uuid != kBleJsonServiceUuid) {
        continue;
      }

      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == kBleJsonCharacteristicUuid) {
          return characteristic;
        }
      }
    }

    if (mounted) {
      setState(() {
        _status = 'Connected, but JSON characteristic not found';
      });
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_discoveredSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_central.stopDiscovery());
    if (_targetPeripheral != null) {
      unawaited(_central.disconnect(_targetPeripheral!));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client')),
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
            ElevatedButton(
              onPressed: _connecting ? null : scan,
              child: Text(_scanning ? 'Scanning...' : 'Scan Again'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _discoveries.isEmpty
                  ? const Center(
                      child: Text('No BLE JSON server found yet'),
                    )
                  : ListView.separated(
                      itemCount: _discoveries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final discovery = _discoveries[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _connecting
                              ? null
                              : () => connectToServer(discovery),
                          child: Ink(
                            padding: const EdgeInsets.all(14),
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
                                  discovery.advertisement.name ??
                                      'BLE JSON Server',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text('RSSI: ${discovery.rssi}'),
                                const SizedBox(height: 6),
                                Text(
                                  discovery.peripheral.uuid.toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
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
