import '../../core/network/local_connectivity.dart';

/// Contract for local network *type* detection, abstracted so [SyncManager]
/// can be unit-tested with a fake instead of the real `connectivity_plus`
/// platform channel. See `core/network/network_monitor.dart` for the real
/// implementation.
abstract class ConnectivityMonitor {
  LocalConnectivity get current;

  Stream<LocalConnectivity> get onChange;

  Future<void> start();

  Future<void> dispose();
}
