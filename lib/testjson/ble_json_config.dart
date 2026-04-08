import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

const String kBleJsonServerName = 'BLE_JSON_SERVER';

final UUID kBleJsonServiceUuid = UUID.fromString(
  '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
);

final UUID kBleJsonCharacteristicUuid = UUID.fromString(
  '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
);
