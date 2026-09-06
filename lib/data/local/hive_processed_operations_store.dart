import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/repositories/local_store.dart';

/// Persistent de-duplication set. Without this, a QoS-1 redelivery, a UDP
/// retransmit, or an operation arriving over both MQTT and UDP would be
/// applied more than once.
///
/// Known limitation (documented in README): this set grows unbounded for
/// the lifetime of the app install. Fine for a demo; a production version
/// would prune entries older than some retention window.
class HiveProcessedOperationsStore implements ProcessedOperationsStore {
  late Box<bool> _box;

  @override
  Future<void> init() async {
    _box = await Hive.openBox<bool>(AppConstants.processedOpsBoxName);
  }

  @override
  bool hasProcessed(String operationId) => _box.containsKey(operationId);

  @override
  Future<void> markProcessed(String operationId) async {
    await _box.put(operationId, true);
  }
}
