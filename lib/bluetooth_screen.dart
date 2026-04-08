// import 'dart:async';
//
// import 'package:flutter/material.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:permission_handler/permission_handler.dart';
//
// import 'dashboard_widgets.dart';
//
// class BluetoothScreen extends StatefulWidget {
//   const BluetoothScreen({super.key});
//
//   @override
//   State<BluetoothScreen> createState() => _BluetoothScreenState();
// }
//
// class _BluetoothScreenState extends State<BluetoothScreen> {
//   final List<ScanResult> devices = [];
//
//   StreamSubscription<List<ScanResult>>? _scanSubscription;
//   BluetoothDevice? connectedDevice;
//   List<BluetoothService> services = [];
//   String statusMessage = 'Requesting permissions...';
//   bool isScanning = false;
//   bool permissionsGranted = false;
//   bool isBusy = false;
//   String? busyDeviceId;
//
//   @override
//   void initState() {
//     super.initState();
//     requestPermissions();
//   }
//
//   @override
//   void dispose() {
//     _scanSubscription?.cancel();
//     super.dispose();
//   }
//
//   Future<void> requestPermissions() async {
//     final statuses = await [
//       Permission.bluetoothScan,
//       Permission.bluetoothConnect,
//       Permission.location,
//     ].request();
//
//     final allGranted = statuses.values.every((status) => status.isGranted);
//
//     if (!mounted) return;
//     setState(() {
//       permissionsGranted = allGranted;
//       statusMessage = allGranted
//           ? 'Ready to scan nearby Bluetooth Low Energy devices.'
//           : 'Bluetooth and location permissions are required before scanning.';
//     });
//   }
//
//   Future<void> startScan() async {
//     if (!permissionsGranted) {
//       await requestPermissions();
//       if (!permissionsGranted) return;
//     }
//
//     final adapterState = await FlutterBluePlus.adapterState.first;
//     if (adapterState != BluetoothAdapterState.on) {
//       await FlutterBluePlus.turnOn();
//       await Future.delayed(const Duration(seconds: 2));
//     }
//
//     _scanSubscription?.cancel();
//
//     if (!mounted) return;
//     setState(() {
//       devices.clear();
//       connectedDevice = null;
//       services = [];
//       isScanning = true;
//       statusMessage = 'Scanning in progress...';
//     });
//
//     _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
//       if (!mounted) return;
//       setState(() {
//         devices
//           ..clear()
//           ..addAll(results);
//       });
//     });
//
//     await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
//
//     if (!mounted) return;
//     setState(() {
//       isScanning = false;
//       statusMessage = devices.isEmpty
//           ? 'No devices found this round. Try scanning again.'
//           : 'Scan complete. Pick a device to inspect its services.';
//     });
//   }
//
//   Future<void> connectDevice(BluetoothDevice device) async {
//     if (!mounted) return;
//     setState(() {
//       isBusy = true;
//       busyDeviceId = device.remoteId.str;
//       statusMessage = 'Connecting to ${_deviceName(device)}...';
//     });
//
//     try {
//       await device.connect(
//         license: License.free,
//         timeout: const Duration(seconds: 10),
//         mtu: 512,
//       );
//
//       final discoveredServices = await device.discoverServices();
//
//       if (!mounted) return;
//       setState(() {
//         connectedDevice = device;
//         services = discoveredServices;
//         statusMessage =
//             'Connected to ${_deviceName(device)}. ${discoveredServices.length} services discovered.';
//       });
//     } catch (error) {
//       if (!mounted) return;
//       setState(() {
//         statusMessage = 'Connection failed: $error';
//       });
//     } finally {
//       if (mounted) {
//         setState(() {
//           isBusy = false;
//           busyDeviceId = null;
//         });
//       }
//     }
//   }
//
//   Future<void> disconnectDevice() async {
//     final device = connectedDevice;
//     if (device == null) return;
//
//     await device.disconnect();
//
//     if (!mounted) return;
//     setState(() {
//       connectedDevice = null;
//       services = [];
//       statusMessage = 'Disconnected. You can scan again at any time.';
//     });
//   }
//
//   Future<void> readCharacteristic(BluetoothCharacteristic c) async {
//     final value = await c.read();
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Read ${c.uuid}: ${_formatValue(value)}')),
//     );
//   }
//
//   Future<void> writeCharacteristic(BluetoothCharacteristic c) async {
//     const value = [1, 2, 3];
//     await c.write(value, withoutResponse: false);
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Wrote ${_formatValue(value)} to ${c.uuid}')),
//     );
//   }
//
//   Future<void> subscribeCharacteristic(BluetoothCharacteristic c) async {
//     await c.setNotifyValue(true);
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Subscribed to ${c.uuid} notifications')),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final connected = connectedDevice != null;
//
//     return Scaffold(
//       body: Stack(
//         children: [
//           const AppBackdrop(),
//           SafeArea(
//             child: Center(
//               child: ConstrainedBox(
//                 constraints: const BoxConstraints(maxWidth: 1180),
//                 child: ListView(
//                   padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
//                   children: [
//                     _buildHero(theme, connected),
//                     const SizedBox(height: 20),
//                     LayoutBuilder(
//                       builder: (context, constraints) {
//                         if (constraints.maxWidth < 880) {
//                           return Column(
//                             children: [
//                               _buildStatusPanel(theme),
//                               const SizedBox(height: 16),
//                               _buildContentPanel(theme),
//                             ],
//                           );
//                         }
//
//                         return Row(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Expanded(flex: 4, child: _buildStatusPanel(theme)),
//                             const SizedBox(width: 16),
//                             Expanded(flex: 7, child: _buildContentPanel(theme)),
//                           ],
//                         );
//                       },
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildHero(ThemeData theme, bool connected) {
//     return Container(
//       clipBehavior: Clip.antiAlias,
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(36),
//         gradient: const LinearGradient(
//           colors: [Color(0xFF102E2A), Color(0xFF0F766E), Color(0xFF134E4A)],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: const Color(0xFF0F766E).withValues(alpha: 0.18),
//             blurRadius: 44,
//             offset: const Offset(0, 24),
//           ),
//         ],
//       ),
//       child: Stack(
//         children: [
//           const Positioned(
//             top: -90,
//             right: -10,
//             child: BlurOrb(size: 250, color: Color(0x14FFFFFF)),
//           ),
//           Positioned(
//             bottom: -110,
//             left: -40,
//             child: BlurOrb(
//               size: 220,
//               color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
//             ),
//           ),
//           LayoutBuilder(
//             builder: (context, constraints) {
//               final intro = Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Wrap(
//                     alignment: WrapAlignment.spaceBetween,
//                     runSpacing: 12,
//                     spacing: 12,
//                     crossAxisAlignment: WrapCrossAlignment.center,
//                     children: [
//                       Container(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 14,
//                           vertical: 10,
//                         ),
//                         decoration: BoxDecoration(
//                           color: Colors.white.withValues(alpha: 0.12),
//                           borderRadius: BorderRadius.circular(999),
//                         ),
//                         child: Row(
//                           mainAxisSize: MainAxisSize.min,
//                           children: [
//                             const Icon(
//                               Icons.bolt_rounded,
//                               size: 18,
//                               color: Colors.white,
//                             ),
//                             const SizedBox(width: 8),
//                             Text(
//                               connected
//                                   ? 'Active session'
//                                   : 'Ready for discovery',
//                               style: const TextStyle(
//                                 color: Colors.white,
//                                 fontWeight: FontWeight.w700,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       StatusBadge(
//                         color: connected
//                             ? const Color(0xFFBBF7D0)
//                             : isScanning
//                             ? const Color(0xFFFCD34D)
//                             : const Color(0xFFE2E8F0),
//                         label: connected
//                             ? 'Connected'
//                             : (isScanning ? 'Scanning' : 'Idle'),
//                         onDarkSurface: true,
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 28),
//                   Text(
//                     connected ? 'BLE mission control' : 'Scan with confidence',
//                     style: theme.textTheme.headlineMedium?.copyWith(
//                       color: Colors.white,
//                       fontWeight: FontWeight.w800,
//                       height: 1.05,
//                     ),
//                   ),
//                   const SizedBox(height: 12),
//                   Text(
//                     connected
//                         ? 'Your active peripheral is online. Explore services, trigger reads and writes, and keep the session focused on what matters.'
//                         : 'A sharper dashboard for BLE scanning, connection health, and fast access to the devices around you.',
//                     style: theme.textTheme.titleMedium?.copyWith(
//                       color: Colors.white.withValues(alpha: 0.9),
//                       height: 1.45,
//                     ),
//                   ),
//                   const SizedBox(height: 22),
//                   Wrap(
//                     spacing: 12,
//                     runSpacing: 12,
//                     children: [
//                       HeroMetric(
//                         label: 'Devices found',
//                         value: devices.length.toString(),
//                       ),
//                       HeroMetric(
//                         label: 'Services',
//                         value: services.length.toString(),
//                       ),
//                       HeroMetric(
//                         label: 'Permissions',
//                         value: permissionsGranted ? 'Ready' : 'Blocked',
//                       ),
//                       HeroMetric(
//                         label: 'Mode',
//                         value: connected ? 'Connected' : 'Browse',
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 22),
//                   Wrap(
//                     spacing: 12,
//                     runSpacing: 12,
//                     children: [
//                       FilledButton.icon(
//                         onPressed: (isScanning || isBusy) ? null : startScan,
//                         style: FilledButton.styleFrom(
//                           backgroundColor: const Color(0xFFF6F1E8),
//                           foregroundColor: const Color(0xFF12211D),
//                         ),
//                         icon: Icon(
//                           isScanning
//                               ? Icons.radar_rounded
//                               : Icons.travel_explore_rounded,
//                         ),
//                         label: Text(
//                           isScanning ? 'Scanning...' : 'Scan Devices',
//                         ),
//                       ),
//                       OutlinedButton.icon(
//                         onPressed: isBusy
//                             ? null
//                             : (connected
//                                   ? disconnectDevice
//                                   : requestPermissions),
//                         style: OutlinedButton.styleFrom(
//                           foregroundColor: Colors.white,
//                           side: BorderSide(
//                             color: Colors.white.withValues(alpha: 0.3),
//                           ),
//                         ),
//                         icon: Icon(
//                           connected
//                               ? Icons.link_off_rounded
//                               : Icons.verified_user_rounded,
//                         ),
//                         label: Text(
//                           connected ? 'Disconnect' : 'Refresh Access',
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               );
//
//               final spotlight = _buildHeroSpotlight(theme, connected);
//               if (constraints.maxWidth < 920) {
//                 return Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [intro, const SizedBox(height: 18), spotlight],
//                 );
//               }
//
//               return Row(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Expanded(flex: 7, child: intro),
//                   const SizedBox(width: 18),
//                   Expanded(flex: 4, child: spotlight),
//                 ],
//               );
//             },
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildHeroSpotlight(ThemeData theme, bool connected) {
//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white.withValues(alpha: 0.1),
//         borderRadius: BorderRadius.circular(28),
//         border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             connected ? 'Active device snapshot' : 'Workflow snapshot',
//             style: theme.textTheme.titleMedium?.copyWith(
//               color: Colors.white,
//               fontWeight: FontWeight.w800,
//             ),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             connected
//                 ? 'The current connection is ready for service discovery and characteristic actions.'
//                 : 'Grant access, scan the room, and connect to a device to unlock service inspection.',
//             style: theme.textTheme.bodyMedium?.copyWith(
//               color: Colors.white.withValues(alpha: 0.84),
//               height: 1.45,
//             ),
//           ),
//           const SizedBox(height: 18),
//           InfoRow(
//             icon: Icons.memory_rounded,
//             title: connected ? 'Device' : 'Next step',
//             value: connected
//                 ? _deviceName(connectedDevice!)
//                 : (permissionsGranted ? 'Start a scan' : 'Refresh permissions'),
//             darkSurface: true,
//           ),
//           const SizedBox(height: 12),
//           InfoRow(
//             icon: Icons.route_rounded,
//             title: connected ? 'Identifier' : 'Scan state',
//             value:
//                 connectedDevice?.remoteId.str ??
//                 (isScanning ? 'In progress' : 'Idle'),
//             darkSurface: true,
//           ),
//           const SizedBox(height: 12),
//           InfoRow(
//             icon: Icons.graphic_eq_rounded,
//             title: 'Focus',
//             value: connected ? 'Service exploration' : 'Discovery and connect',
//             darkSurface: true,
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildStatusPanel(ThemeData theme) {
//     final connected = connectedDevice != null;
//
//     return DashboardPanel(
//       title: 'Session pulse',
//       subtitle: 'Permissions, connection health, and the next best action.',
//       trailing: MiniPill(
//         icon: connected
//             ? Icons.memory_rounded
//             : Icons.bluetooth_searching_rounded,
//         label: connected ? 'Live device' : 'No device',
//         tinted: true,
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             width: double.infinity,
//             padding: const EdgeInsets.all(18),
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(24),
//               gradient: LinearGradient(
//                 colors: connected
//                     ? const [Color(0xFF0F766E), Color(0xFF155E75)]
//                     : isScanning
//                     ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
//                     : const [Color(0xFF1F2937), Color(0xFF334155)],
//                 begin: Alignment.topLeft,
//                 end: Alignment.bottomRight,
//               ),
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 StatusBadge(
//                   color: Colors.white,
//                   label: connected
//                       ? 'Connected and stable'
//                       : (isScanning ? 'Scanning now' : 'Waiting for action'),
//                   onDarkSurface: true,
//                 ),
//                 const SizedBox(height: 12),
//                 Text(
//                   statusMessage,
//                   style: theme.textTheme.bodyLarge?.copyWith(
//                     color: Colors.white,
//                     height: 1.45,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: 18),
//           Wrap(
//             spacing: 12,
//             runSpacing: 12,
//             children: [
//               HighlightTile(
//                 icon: Icons.bluetooth_connected_rounded,
//                 label: 'Active device',
//                 value: connected
//                     ? _deviceName(connectedDevice!)
//                     : 'No device selected',
//               ),
//               HighlightTile(
//                 icon: Icons.wifi_tethering_rounded,
//                 label: 'Discovery',
//                 value: isScanning ? 'In progress' : 'Stopped',
//               ),
//               HighlightTile(
//                 icon: Icons.verified_user_rounded,
//                 label: 'Access',
//                 value: permissionsGranted ? 'Granted' : 'Required',
//               ),
//             ],
//           ),
//           const SizedBox(height: 18),
//           InfoRow(
//             icon: Icons.vpn_key_rounded,
//             title: 'Device identifier',
//             value: connectedDevice?.remoteId.str ?? 'Waiting for connection',
//           ),
//           const SizedBox(height: 14),
//           InfoRow(
//             icon: Icons.layers_rounded,
//             title: 'Discovered services',
//             value: connected ? '${services.length} available' : 'None yet',
//           ),
//           const SizedBox(height: 22),
//           Wrap(
//             spacing: 12,
//             runSpacing: 12,
//             children: [
//               FilledButton.icon(
//                 onPressed: (isScanning || isBusy) ? null : startScan,
//                 icon: const Icon(Icons.search_rounded),
//                 label: Text(connected ? 'Scan Again' : 'Start Scan'),
//               ),
//               OutlinedButton.icon(
//                 onPressed: isBusy
//                     ? null
//                     : (connected ? disconnectDevice : requestPermissions),
//                 icon: Icon(
//                   connected
//                       ? Icons.link_off_rounded
//                       : Icons.admin_panel_settings_rounded,
//                 ),
//                 label: Text(connected ? 'Disconnect' : 'Check Access'),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildContentPanel(ThemeData theme) {
//     final connected = connectedDevice != null;
//
//     return DashboardPanel(
//       title: connected ? 'Device explorer' : 'Discovery feed',
//       subtitle: connected
//           ? 'Services and characteristics for the connected peripheral.'
//           : 'Nearby peripherals ready to connect.',
//       trailing: MiniPill(
//         icon: connected ? Icons.hub_rounded : Icons.radar_rounded,
//         label: connected
//             ? '${services.length} services'
//             : '${devices.length} devices',
//         tinted: true,
//       ),
//       child: connected ? _buildDeviceDetails(theme) : _buildScanList(theme),
//     );
//   }
//
//   Widget _buildScanList(ThemeData theme) {
//     if (devices.isEmpty) {
//       return EmptyState(
//         icon: isScanning
//             ? Icons.radar_rounded
//             : Icons.bluetooth_disabled_rounded,
//         title: isScanning
//             ? 'Searching for nearby devices'
//             : 'No scan results yet',
//         message: isScanning
//             ? 'Keep this screen open while the BLE scan completes.'
//             : 'Start a scan to populate this view with nearby Bluetooth peripherals.',
//       );
//     }
//
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'Nearby devices',
//           style: theme.textTheme.titleLarge?.copyWith(
//             fontWeight: FontWeight.w800,
//           ),
//         ),
//         const SizedBox(height: 8),
//         Text(
//           'Choose a device to connect, then inspect its services and characteristic capabilities.',
//           style: theme.textTheme.bodyMedium?.copyWith(
//             color: const Color(0xFF64748B),
//           ),
//         ),
//         const SizedBox(height: 18),
//         Wrap(
//           spacing: 12,
//           runSpacing: 12,
//           children: [
//             MiniPill(
//               icon: Icons.devices_rounded,
//               label: '${devices.length} devices in range',
//               tinted: true,
//             ),
//             const MiniPill(
//               icon: Icons.touch_app_rounded,
//               label: 'Tap connect to inspect services',
//               tinted: true,
//             ),
//           ],
//         ),
//         const SizedBox(height: 18),
//         ...devices.map((result) => _buildDeviceCard(theme, result)),
//       ],
//     );
//   }
//
//   Widget _buildDeviceCard(ThemeData theme, ScanResult result) {
//     final device = result.device;
//     final signal = result.rssi;
//     final isCurrentDeviceBusy = busyDeviceId == device.remoteId.str;
//     final signalColor = signal >= -65
//         ? const Color(0xFF0F766E)
//         : signal >= -80
//         ? const Color(0xFFB45309)
//         : const Color(0xFFB91C1C);
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 14),
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white.withValues(alpha: 0.9),
//         borderRadius: BorderRadius.circular(28),
//         border: Border.all(color: const Color(0xFFE7DFD2)),
//       ),
//       child: LayoutBuilder(
//         builder: (context, constraints) {
//           final details = Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Container(
//                     width: 56,
//                     height: 56,
//                     decoration: BoxDecoration(
//                       gradient: const LinearGradient(
//                         colors: [Color(0xFFE1F8F3), Color(0xFFD5F2EA)],
//                       ),
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: const Icon(
//                       Icons.memory_rounded,
//                       color: Color(0xFF0F766E),
//                     ),
//                   ),
//                   const SizedBox(width: 14),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           _deviceName(device),
//                           style: theme.textTheme.titleMedium?.copyWith(
//                             fontWeight: FontWeight.w800,
//                           ),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           device.remoteId.str,
//                           style: theme.textTheme.bodyMedium?.copyWith(
//                             color: const Color(0xFF64748B),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 16),
//               Wrap(
//                 spacing: 10,
//                 runSpacing: 10,
//                 children: [
//                   MiniPill(
//                     icon: Icons.network_cell_rounded,
//                     label: 'RSSI $signal dBm',
//                     color: signalColor,
//                   ),
//                   MiniPill(
//                     icon: Icons.stacked_line_chart_rounded,
//                     label: _signalSummary(signal),
//                     color: signalColor,
//                   ),
//                   MiniPill(
//                     icon: Icons.bluetooth_audio_rounded,
//                     label: result.advertisementData.connectable
//                         ? 'Connectable'
//                         : 'Broadcast only',
//                     tinted: true,
//                   ),
//                 ],
//               ),
//             ],
//           );
//
//           final action = FilledButton.icon(
//             onPressed: isBusy ? null : () => connectDevice(device),
//             style: FilledButton.styleFrom(
//               backgroundColor: isCurrentDeviceBusy
//                   ? const Color(0xFF155E75)
//                   : const Color(0xFF0F766E),
//               disabledBackgroundColor: isCurrentDeviceBusy
//                   ? const Color(0xFF155E75)
//                   : const Color(0xFF0F766E).withValues(alpha: 0.88),
//               disabledForegroundColor: Colors.white,
//             ),
//             icon: Icon(
//               isCurrentDeviceBusy ? Icons.sync_rounded : Icons.east_rounded,
//             ),
//             label: Text(isCurrentDeviceBusy ? 'Connecting...' : 'Connect'),
//           );
//
//           if (constraints.maxWidth < 640) {
//             return Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 details,
//                 const SizedBox(height: 16),
//                 SizedBox(width: double.infinity, child: action),
//               ],
//             );
//           }
//
//           return Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(child: details),
//               const SizedBox(width: 16),
//               action,
//             ],
//           );
//         },
//       ),
//     );
//   }
//
//   Widget _buildDeviceDetails(ThemeData theme) {
//     if (services.isEmpty) {
//       return const EmptyState(
//         icon: Icons.developer_board_off_rounded,
//         title: 'No services discovered',
//         message:
//             'The device connected successfully, but no services are available yet.',
//       );
//     }
//
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           _deviceName(connectedDevice!),
//           style: theme.textTheme.headlineSmall?.copyWith(
//             fontWeight: FontWeight.w800,
//           ),
//         ),
//         const SizedBox(height: 8),
//         Text(
//           'Explore exposed services, inspect characteristic properties, and run BLE actions from one place.',
//           style: theme.textTheme.bodyMedium?.copyWith(
//             color: const Color(0xFF64748B),
//           ),
//         ),
//         const SizedBox(height: 18),
//         Wrap(
//           spacing: 12,
//           runSpacing: 12,
//           children: [
//             MiniPill(
//               icon: Icons.vpn_key_rounded,
//               label: connectedDevice!.remoteId.str,
//               tinted: true,
//             ),
//             MiniPill(
//               icon: Icons.layers_rounded,
//               label: '${services.length} services loaded',
//               tinted: true,
//             ),
//           ],
//         ),
//         const SizedBox(height: 18),
//         ...services.map((service) => _buildServiceCard(theme, service)),
//       ],
//     );
//   }
//
//   Widget _buildServiceCard(ThemeData theme, BluetoothService service) {
//     return Container(
//       margin: const EdgeInsets.only(bottom: 14),
//       decoration: BoxDecoration(
//         color: Colors.white.withValues(alpha: 0.88),
//         borderRadius: BorderRadius.circular(28),
//         border: Border.all(color: const Color(0xFFE7DFD2)),
//       ),
//       child: ExpansionTile(
//         tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
//         childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
//         collapsedShape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(28),
//         ),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
//         title: Text(
//           'Service ${service.uuid}',
//           style: theme.textTheme.titleMedium?.copyWith(
//             fontWeight: FontWeight.w800,
//           ),
//         ),
//         subtitle: Padding(
//           padding: const EdgeInsets.only(top: 6),
//           child: MiniPill(
//             icon: Icons.tune_rounded,
//             label: '${service.characteristics.length} characteristics',
//             tinted: true,
//           ),
//         ),
//         children: service.characteristics
//             .map(
//               (characteristic) =>
//                   _buildCharacteristicCard(theme, characteristic),
//             )
//             .toList(),
//       ),
//     );
//   }
//
//   Widget _buildCharacteristicCard(
//     ThemeData theme,
//     BluetoothCharacteristic characteristic,
//   ) {
//     final actions = <Widget>[
//       if (characteristic.properties.read)
//         ActionPill(
//           icon: Icons.download_rounded,
//           label: 'Read',
//           onPressed: () => readCharacteristic(characteristic),
//         ),
//       if (characteristic.properties.write)
//         ActionPill(
//           icon: Icons.upload_rounded,
//           label: 'Write',
//           onPressed: () => writeCharacteristic(characteristic),
//         ),
//       if (characteristic.properties.notify)
//         ActionPill(
//           icon: Icons.notifications_active_rounded,
//           label: 'Notify',
//           onPressed: () => subscribeCharacteristic(characteristic),
//         ),
//     ];
//
//     return Container(
//       margin: const EdgeInsets.only(top: 12),
//       padding: const EdgeInsets.all(18),
//       decoration: BoxDecoration(
//         color: const Color(0xFFF9F6EF),
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(color: const Color(0xFFE6DDD0)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Container(
//                 width: 42,
//                 height: 42,
//                 decoration: BoxDecoration(
//                   color: const Color(0xFFE1F8F3),
//                   borderRadius: BorderRadius.circular(14),
//                 ),
//                 child: const Icon(
//                   Icons.settings_input_component_rounded,
//                   color: Color(0xFF0F766E),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Characteristic ${characteristic.uuid}',
//                       style: theme.textTheme.titleSmall?.copyWith(
//                         fontWeight: FontWeight.w800,
//                       ),
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       _describeProperties(characteristic.properties),
//                       style: theme.textTheme.bodyMedium?.copyWith(
//                         color: const Color(0xFF64748B),
//                         height: 1.45,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 14),
//           if (actions.isNotEmpty)
//             Wrap(spacing: 10, runSpacing: 10, children: actions)
//           else
//             const MiniPill(
//               icon: Icons.info_outline_rounded,
//               label: 'No interactive actions available',
//               tinted: true,
//             ),
//         ],
//       ),
//     );
//   }
//
//   String _deviceName(BluetoothDevice device) {
//     final name = device.platformName;
//     return name.isEmpty ? 'Unknown Device' : name;
//   }
//
//   String _formatValue(List<int> value) {
//     if (value.isEmpty) return '[]';
//     return value.join(', ');
//   }
//
//   String _describeProperties(CharacteristicProperties properties) {
//     final labels = <String>[
//       if (properties.read) 'read',
//       if (properties.write) 'write',
//       if (properties.writeWithoutResponse) 'writeWithoutResponse',
//       if (properties.notify) 'notify',
//       if (properties.indicate) 'indicate',
//       if (properties.broadcast) 'broadcast',
//     ];
//
//     return labels.isEmpty
//         ? 'No interactive properties exposed.'
//         : labels.join(' | ');
//   }
//
//   String _signalSummary(int signal) {
//     if (signal >= -65) return 'Strong signal';
//     if (signal >= -80) return 'Moderate signal';
//     return 'Weak signal';
//   }
// }
