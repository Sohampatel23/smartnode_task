import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/repositories/local_store.dart';

/// Hive-backed implementation of [InventoryLocalStore]. Items are stored as
/// plain `Map`s (no generated TypeAdapters) to keep the persistence layer
/// simple and dependency-free for an interview-scale project.
class HiveInventoryLocalStore implements InventoryLocalStore {
  late Box _box;

  @override
  Future<void> init() async {
    try {
      _box = await Hive.openBox(AppConstants.inventoryBoxName);
    } catch (e, st) {
      AppLogger.error('Failed to open inventory box', e, st);
      throw const StorageException('Could not open local inventory storage.');
    }
  }

  @override
  List<InventoryItem> loadItems() {
    return _box.values
        .cast<Map>()
        .map((raw) => InventoryItem.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }

  @override
  Future<void> saveItem(InventoryItem item) async {
    try {
      await _box.put(item.id, item.toMap());
    } catch (e, st) {
      AppLogger.error('Failed to save item ${item.id}', e, st);
      throw const StorageException('Could not save inventory changes.');
    }
  }

  @override
  Future<void> seedIfEmpty(List<InventoryItem> defaults) async {
    if (_box.isNotEmpty) return;
    for (final item in defaults) {
      await saveItem(item);
    }
  }
}
