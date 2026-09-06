import 'package:flutter/foundation.dart';

import '../../core/errors/app_exceptions.dart';

/// A single, commutative mutation to an item's quantity.
///
/// Design rationale (see README "Synchronization Strategy" for the full
/// writeup): the wire format carries a *delta* (+1 / -1), not an absolute
/// quantity. This makes concurrent updates from two devices commute
/// correctly - both `+1`s are applied instead of one clobbering the other,
/// which is what would happen with naive "last write wins on the absolute
/// value" synchronization.
///
/// [operationId] is a globally unique id used everywhere (MQTT, UDP, the
/// local queue, the processed-ops de-dupe set) to detect and ignore
/// duplicate delivery.
@immutable
class InventoryOperation {
  const InventoryOperation({
    required this.operationId,
    required this.itemId,
    required this.delta,
    required this.deviceId,
    required this.timestamp,
  });

  final String operationId;
  final String itemId;
  final int delta;
  final String deviceId;
  final DateTime timestamp;

  Map<String, dynamic> toJsonMap() => {
        'operationId': operationId,
        'itemId': itemId,
        'delta': delta,
        'deviceId': deviceId,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Parses and validates a wire payload (MQTT or UDP). Throws
  /// [InvalidPayloadException] for anything malformed rather than letting a
  /// raw [FormatException]/[TypeError] escape into networking callbacks.
  factory InventoryOperation.fromJsonMap(Map<String, dynamic> map) {
    try {
      final operationId = map['operationId'] as String;
      final itemId = map['itemId'] as String;
      final delta = map['delta'] as int;
      final deviceId = map['deviceId'] as String;
      final timestamp = DateTime.parse(map['timestamp'] as String);

      if (operationId.isEmpty || itemId.isEmpty || deviceId.isEmpty) {
        throw const InvalidPayloadException('Empty required field in operation payload.');
      }
      if (delta == 0) {
        throw const InvalidPayloadException('Operation delta must be non-zero.');
      }
      return InventoryOperation(
        operationId: operationId,
        itemId: itemId,
        delta: delta,
        deviceId: deviceId,
        timestamp: timestamp,
      );
    } on InvalidPayloadException {
      rethrow;
    } catch (e) {
      throw InvalidPayloadException('Malformed operation payload: $e');
    }
  }

  Map<String, dynamic> toStorageMap() => {
        ...toJsonMap(),
      };

  factory InventoryOperation.fromStorageMap(Map<dynamic, dynamic> map) {
    return InventoryOperation.fromJsonMap(Map<String, dynamic>.from(map));
  }

  @override
  String toString() => 'Op($operationId, item=$itemId, delta=$delta)';
}
