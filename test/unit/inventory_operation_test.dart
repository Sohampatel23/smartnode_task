import 'package:flutter_test/flutter_test.dart';
import 'package:smartnode_task/core/errors/app_exceptions.dart';
import 'package:smartnode_task/domain/entities/inventory_operation.dart';

void main() {
  group('InventoryOperation.fromJsonMap', () {
    test('parses a valid payload', () {
      final op = InventoryOperation.fromJsonMap({
        'operationId': 'op-1',
        'itemId': 'item-1',
        'delta': 1,
        'deviceId': 'device-1',
        'timestamp': DateTime(2026, 1, 1).toIso8601String(),
      });

      expect(op.operationId, 'op-1');
      expect(op.itemId, 'item-1');
      expect(op.delta, 1);
      expect(op.deviceId, 'device-1');
    });

    test('round-trips through toJsonMap', () {
      final original = InventoryOperation(
        operationId: 'op-1',
        itemId: 'item-1',
        delta: -1,
        deviceId: 'device-1',
        timestamp: DateTime(2026, 1, 1),
      );
      final decoded = InventoryOperation.fromJsonMap(original.toJsonMap());
      expect(decoded.operationId, original.operationId);
      expect(decoded.delta, original.delta);
    });

    test('rejects missing fields', () {
      expect(
        () => InventoryOperation.fromJsonMap({'operationId': 'op-1'}),
        throwsA(isA<InvalidPayloadException>()),
      );
    });

    test('rejects wrong-typed fields', () {
      expect(
        () => InventoryOperation.fromJsonMap({
          'operationId': 'op-1',
          'itemId': 'item-1',
          'delta': 'not-a-number',
          'deviceId': 'device-1',
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        }),
        throwsA(isA<InvalidPayloadException>()),
      );
    });

    test('rejects a zero delta', () {
      expect(
        () => InventoryOperation.fromJsonMap({
          'operationId': 'op-1',
          'itemId': 'item-1',
          'delta': 0,
          'deviceId': 'device-1',
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        }),
        throwsA(isA<InvalidPayloadException>()),
      );
    });

    test('rejects empty required strings', () {
      expect(
        () => InventoryOperation.fromJsonMap({
          'operationId': '',
          'itemId': 'item-1',
          'delta': 1,
          'deviceId': 'device-1',
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        }),
        throwsA(isA<InvalidPayloadException>()),
      );
    });

    test('rejects malformed JSON-shaped garbage without crashing the caller', () {
      expect(
        () => InventoryOperation.fromJsonMap({'garbage': true}),
        throwsA(isA<InvalidPayloadException>()),
      );
    });
  });
}
