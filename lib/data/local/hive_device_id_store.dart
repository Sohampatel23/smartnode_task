import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/repositories/local_store.dart';

class HiveDeviceIdStore implements DeviceIdStore {
  HiveDeviceIdStore(this._idGenerator);

  final IdGenerator _idGenerator;
  late Box _box;

  @override
  Future<String> getOrCreateDeviceId() async {
    _box = await Hive.openBox(AppConstants.metaBoxName);
    final existing = _box.get(AppConstants.deviceIdKey) as String?;
    if (existing != null) return existing;

    final created = _idGenerator.newDeviceId();
    await _box.put(AppConstants.deviceIdKey, created);
    return created;
  }
}
