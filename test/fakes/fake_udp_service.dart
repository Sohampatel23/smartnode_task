import 'dart:async';

import 'package:smartnode_task/domain/entities/inventory_operation.dart';
import 'package:smartnode_task/domain/services/udp_service.dart';

class FakeUdpService implements UdpService {
  final _incomingController = StreamController<InventoryOperation>.broadcast();
  final List<InventoryOperation> broadcasted = [];
  bool started = false;
  bool broadcastShouldFail = false;

  @override
  Stream<InventoryOperation> get incomingOperations => _incomingController.stream;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    started = false;
    await _incomingController.close();
  }

  @override
  Future<bool> broadcast(InventoryOperation operation) async {
    if (broadcastShouldFail) return false;
    broadcasted.add(operation);
    return true;
  }

  void simulateIncoming(InventoryOperation operation) {
    _incomingController.add(operation);
  }
}
