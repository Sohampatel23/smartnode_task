import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/network/network_monitor.dart';
import 'core/sync/sync_manager.dart';
import 'core/utils/id_generator.dart';
import 'data/local/hive_device_id_store.dart';
import 'data/local/hive_inventory_local_store.dart';
import 'data/local/hive_operation_queue_store.dart';
import 'data/local/hive_processed_operations_store.dart';
import 'data/mqtt/mqtt_service_impl.dart';
import 'data/repositories/inventory_repository_impl.dart';
import 'data/udp/udp_service_impl.dart';
import 'domain/entities/inventory_item.dart';
import 'presentation/controllers/inventory_controller.dart';
import 'presentation/screens/inventory_screen.dart';
import 'presentation/theme/app_theme.dart';

/// Composition root: this is the only place concrete implementations
/// (Hive, mqtt_client, UDP sockets) are wired to their abstractions. Every
/// other layer depends only on the interfaces in `domain/`.
Future<InventoryController> _buildController() async {
  await Hive.initFlutter();

  final idGenerator = IdGenerator();
  final deviceIdStore = HiveDeviceIdStore(idGenerator);
  final deviceId = await deviceIdStore.getOrCreateDeviceId();

  final syncManager = SyncManager(
    mqttService: MqttServiceImpl(deviceId: deviceId),
    udpService: UdpServiceImpl(deviceId: deviceId),
    networkMonitor: NetworkMonitor(),
    inventoryStore: HiveInventoryLocalStore(),
    queueStore: HiveOperationQueueStore(),
    processedStore: HiveProcessedOperationsStore(),
    idGenerator: idGenerator,
    deviceId: deviceId,
  );

  final repository = InventoryRepositoryImpl(syncManager, _defaultItems());
  final controller = InventoryController(repository);
  await controller.init();
  return controller;
}

List<InventoryItem> _defaultItems() {
  final now = DateTime.now();
  return [
    InventoryItem(id: 'item-widget-a', name: 'Widget A', quantity: 10, updatedAt: now),
    InventoryItem(id: 'item-widget-b', name: 'Widget B', quantity: 5, updatedAt: now),
    InventoryItem(id: 'item-widget-c', name: 'Widget C', quantity: 20, updatedAt: now),
    InventoryItem(id: 'item-widget-d', name: 'Widget D', quantity: 0, updatedAt: now),
  ];
}

void main() {
  runApp(const InventorySyncApp());
}

class InventorySyncApp extends StatelessWidget {
  const InventorySyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Distributed Inventory Sync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: FutureBuilder<InventoryController>(
        future: _buildController(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text('Failed to start: ${snapshot.error}')),
            );
          }
          return ChangeNotifierProvider.value(
            value: snapshot.data!,
            child: const InventoryScreen(),
          );
        },
      ),
    );
  }
}
