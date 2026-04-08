import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestBlePermissions({required bool includeAdvertise}) async {
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
