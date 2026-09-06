import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/inventory_repository.dart';

enum ViewLoadState { loading, ready, error }

/// The only object the UI talks to. It never touches MQTT, UDP, or storage
/// directly - all of that is behind [InventoryRepository]. This is where
/// optimistic UI update semantics live: [changeQuantity] mutates local state
/// synchronously through the repository (which persists immediately) and
/// never awaits a network round trip before the UI reflects the change.
class InventoryController extends ChangeNotifier with WidgetsBindingObserver {
  InventoryController(this._repository);

  final InventoryRepository _repository;

  StreamSubscription<List<InventoryItem>>? _itemsSub;
  StreamSubscription<SyncStatus>? _statusSub;
  StreamSubscription<int>? _pendingSub;

  ViewLoadState _loadState = ViewLoadState.loading;
  String? _errorMessage;
  List<InventoryItem> _items = [];
  SyncStatus _syncStatus = SyncStatus.connecting;
  int _pendingCount = 0;

  ViewLoadState get loadState => _loadState;

  String? get errorMessage => _errorMessage;

  List<InventoryItem> get items {
    final sorted = List<InventoryItem>.of(_items)..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(sorted);
  }

  SyncStatus get syncStatus => _syncStatus;

  int get pendingCount => _pendingCount;

  Future<void> init() async {
    try {
      WidgetsBinding.instance.addObserver(this);
      await _repository.init();
      _items = _repository.currentItems;
      _syncStatus = _repository.currentStatus;
      _pendingCount = _repository.currentPendingCount;
      _loadState = ViewLoadState.ready;

      _itemsSub = _repository.watchItems().listen((items) {
        _items = items;
        notifyListeners();
      });
      _statusSub = _repository.watchSyncStatus().listen((status) {
        _syncStatus = status;
        notifyListeners();
      });
      _pendingSub = _repository.watchPendingCount().listen((count) {
        _pendingCount = count;
        notifyListeners();
      });

      notifyListeners();
    } catch (e, st) {
      AppLogger.error('Failed to initialize inventory', e, st);
      _loadState = ViewLoadState.error;
      _errorMessage = e is AppException ? e.message : 'Something went wrong while starting up.';
      notifyListeners();
    }
  }

  Future<void> increment(String itemId) => changeQuantity(itemId, 1);

  Future<void> decrement(String itemId) => changeQuantity(itemId, -1);

  Future<void> changeQuantity(String itemId, int delta) async {
    try {
      await _repository.changeQuantity(itemId, delta);
    } catch (e, st) {
      AppLogger.error('Failed to change quantity for $itemId', e, st);
      // The optimistic local update already succeeded inside the sync
      // layer for any storage-independent failure; a thrown exception here
      // means even local persistence failed, which we surface without
      // crashing the UI.
      _errorMessage = e is AppException ? e.message : 'Could not save that change.';
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _repository.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _itemsSub?.cancel();
    _statusSub?.cancel();
    _pendingSub?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
