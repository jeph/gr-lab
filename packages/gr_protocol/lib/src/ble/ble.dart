/// GR camera BLE protocol: GATT catalog, codecs, advertising, client and
/// wake sequence (research/protocol/ble.md, research/protocol/ble-imagesync.md).
library;

export 'advertising.dart';
export 'aggregate.dart';
export 'bytes.dart';
export 'catalog.dart';
export 'client.dart';
export 'codecs.dart' hide fixedLengthUsable, parseBoolText, parseIntText;
export 'enums.dart';
export 'model.dart';
export 'pairing.dart';
export 'power_on_watch.dart';
export 'records.dart';
export 'tables.dart';
export 'tracing_transport.dart';
export 'wake.dart';
