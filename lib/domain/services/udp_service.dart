import '../entities/inventory_operation.dart';

/// Contract for the local-network (Phase 3) fallback transport.
abstract class UdpService {
  /// Successfully parsed, validated, non-self-originated operations
  /// received over the LAN.
  Stream<InventoryOperation> get incomingOperations;

  Future<void> start();

  Future<void> stop();

  Future<bool> broadcast(InventoryOperation operation);
}
