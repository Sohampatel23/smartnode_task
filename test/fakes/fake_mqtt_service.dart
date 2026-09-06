import 'dart:async';

import 'package:smartnode_task/domain/entities/inventory_item.dart';
import 'package:smartnode_task/domain/entities/inventory_operation.dart';
import 'package:smartnode_task/domain/entities/item_state_snapshot.dart';
import 'package:smartnode_task/domain/services/mqtt_service.dart';

/// In-memory [MqttService] double. Lets tests simulate connect/disconnect,
/// inbound broker messages, and publish failures without a real broker.
class FakeMqttService implements MqttService {
  final _connectionController = StreamController<bool>.broadcast();
  final _incomingController = StreamController<InventoryOperation>.broadcast();
  final _incomingStateController = StreamController<ItemStateSnapshot>.broadcast();

  bool _connected = false;
  bool publishShouldFail = false;
  final List<InventoryOperation> published = [];
  final List<ItemStateSnapshot> publishedStates = [];

  @override
  Stream<bool> get connectionState => _connectionController.stream;

  @override
  Stream<InventoryOperation> get incomingOperations => _incomingController.stream;

  @override
  Stream<ItemStateSnapshot> get incomingItemStates => _incomingStateController.stream;

  @override
  bool get isConnected => _connected;

  /// Mirrors the real client: calling connect() does not synchronously mean
  /// connected - tests drive [setConnected] explicitly to simulate the
  /// broker handshake completing (or failing).
  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {
    setConnected(false);
    await _connectionController.close();
    await _incomingController.close();
    await _incomingStateController.close();
  }

  @override
  Future<bool> publish(InventoryOperation operation) async {
    if (!_connected || publishShouldFail) return false;
    published.add(operation);
    return true;
  }

  @override
  Future<bool> publishItemState(InventoryItem item, String causeOperationId) async {
    if (!_connected || publishShouldFail) return false;
    publishedStates.add(ItemStateSnapshot(item: item, lastOperationId: causeOperationId));
    return true;
  }

  /// Test helper: simulate a retained state snapshot arriving, e.g. right
  /// after (re)subscribing, or as the live echo of this device's own
  /// retained publish.
  void simulateIncomingState(ItemStateSnapshot snapshot) {
    _incomingStateController.add(snapshot);
  }

  /// Test helper: simulate the broker connection dropping or recovering.
  void setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _connectionController.add(value);
  }

  /// Test helper: simulate a message arriving from another device.
  void simulateIncoming(InventoryOperation operation) {
    _incomingController.add(operation);
  }
}
