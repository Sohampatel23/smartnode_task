import 'dart:async';

import '../../domain/entities/inventory_item.dart';
import '../../domain/entities/inventory_operation.dart';
import '../../domain/entities/item_state_snapshot.dart';
import '../../domain/entities/pending_operation.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/local_store.dart';
import '../../domain/services/connectivity_monitor.dart';
import '../../domain/services/mqtt_service.dart';
import '../../domain/services/udp_service.dart';
import '../constants/app_constants.dart';
import '../network/local_connectivity.dart';
import '../utils/app_logger.dart';
import '../utils/id_generator.dart';

/// The orchestrator described in the README's architecture diagram:
///
/// ```
/// Repository -> SyncManager -> { MQTT | UDP | Local DB }
/// ```
///
/// This is where the "MQTT vs UDP vs offline queue" decision is made, where
/// duplicate operations are filtered (idempotency), and where the
/// commutative-delta conflict strategy is applied. Nothing here knows about
/// widgets - it only deals with domain entities and streams, which is what
/// makes it unit-testable with fake [MqttService]/[UdpService]
/// implementations (see test/).
class SyncManager {
  SyncManager({
    required MqttService mqttService,
    required UdpService udpService,
    required ConnectivityMonitor networkMonitor,
    required InventoryLocalStore inventoryStore,
    required OperationQueueStore queueStore,
    required ProcessedOperationsStore processedStore,
    required IdGenerator idGenerator,
    required String deviceId,
  })  : _mqttService = mqttService,
        _udpService = udpService,
        _networkMonitor = networkMonitor,
        _inventoryStore = inventoryStore,
        _queueStore = queueStore,
        _processedStore = processedStore,
        _idGenerator = idGenerator,
        _deviceId = deviceId;

  final MqttService _mqttService;
  final UdpService _udpService;
  final ConnectivityMonitor _networkMonitor;
  final InventoryLocalStore _inventoryStore;
  final OperationQueueStore _queueStore;
  final ProcessedOperationsStore _processedStore;
  final IdGenerator _idGenerator;
  final String _deviceId;

  final _itemsController = StreamController<List<InventoryItem>>.broadcast();
  final _statusController = StreamController<SyncStatus>.broadcast();
  final _pendingCountController = StreamController<int>.broadcast();

  final Map<String, InventoryItem> _items = {};
  final Map<String, DateTime> _recentLocalEditAt = {};
  SyncStatus _status = SyncStatus.connecting;
  Timer? _queueRetryTimer;

  StreamSubscription<bool>? _mqttConnSub;
  StreamSubscription<InventoryOperation>? _mqttOpsSub;
  StreamSubscription<ItemStateSnapshot>? _mqttStateSub;
  StreamSubscription<InventoryOperation>? _udpOpsSub;
  StreamSubscription<LocalConnectivity>? _networkSub;

  List<InventoryItem> get currentItems => _items.values.toList(growable: false);

  SyncStatus get currentStatus => _status;

  int get currentPendingCount => _queueStore.loadPending().length;

  Stream<List<InventoryItem>> get itemsStream => _itemsController.stream;

  Stream<SyncStatus> get statusStream => _statusController.stream;

  Stream<int> get pendingCountStream => _pendingCountController.stream;

  Future<void> init(List<InventoryItem> defaultSeedItems) async {
    await _inventoryStore.init();
    await _queueStore.init();
    await _processedStore.init();

    await _inventoryStore.seedIfEmpty(defaultSeedItems);
    for (final item in _inventoryStore.loadItems()) {
      _items[item.id] = item;
    }

    await _networkMonitor.start();
    _networkSub = _networkMonitor.onChange.listen((_) => _recomputeStatus());

    _mqttConnSub = _mqttService.connectionState.listen((_) => _onMqttConnectionChanged());
    _mqttOpsSub = _mqttService.incomingOperations.listen(_applyLocal);
    // Retained-state catch-up: fires when this device (re)subscribes and
    // the broker replays the last-known value for each item, closing the
    // gap that operation-only sync leaves for a device that was offline
    // while other devices made changes (see AppConstants.mqttStateTopicPrefix).
    _mqttStateSub = _mqttService.incomingItemStates.listen(_reconcileState);

    await _udpService.start();
    _udpOpsSub = _udpService.incomingOperations.listen(_applyLocal);

    _recomputeStatus();
    unawaited(_mqttService.connect());
  }

  /// Called when the app returns to the foreground. A backgrounded app can
  /// have its socket silently dropped by the OS without an explicit
  /// disconnect event firing; nudging a connect attempt here (safe/no-op if
  /// already connected or already trying) avoids waiting out the full
  /// reconnect-timer delay before the user sees 🟢 again.
  void onAppResumed() {
    if (!_mqttService.isConnected) {
      unawaited(_mqttService.connect());
    }
  }

  Future<void> changeQuantity(String itemId, int delta) async {
    final current = _items[itemId];
    if (current == null) return;
    if (delta < 0 && current.quantity <= 0) return;

    final operation = InventoryOperation(
      operationId: _idGenerator.newOperationId(),
      itemId: itemId,
      delta: delta,
      deviceId: _deviceId,
      timestamp: DateTime.now(),
    );

    // Recorded before dispatch (not after publish/flush) so the protection
    // window covers this edit from the instant it's made, regardless of how
    // long the network round trip to actually publish it takes.
    _recentLocalEditAt[itemId] = DateTime.now();

    await _applyLocal(operation);
    await _dispatch(operation);
  }

  // -------------------------------------------------------------------
  // Transport selection
  // -------------------------------------------------------------------

  void _recomputeStatus() {
    final SyncStatus next;
    if (_mqttService.isConnected) {
      next = SyncStatus.online;
    } else if (_networkMonitor.current == LocalConnectivity.wifi) {
      next = SyncStatus.localNetworkOnly;
    } else if (_networkMonitor.current == LocalConnectivity.none) {
      next = SyncStatus.offline;
    } else {
      // Mobile data / ethernet present but MQTT hasn't (yet) connected -
      // there is no LAN to fall back to, so this is transient "connecting"
      // rather than a stable state; it will resolve to online once MQTT
      // connects or offline if it keeps failing.
      next = SyncStatus.connecting;
    }

    if (next == _status) return;
    _status = next;
    AppLogger.sync('Sync status -> $next');
    _statusController.add(next);
  }

  void _onMqttConnectionChanged() {
    _recomputeStatus();
    if (_mqttService.isConnected) {
      unawaited(_flushQueue());
    }
  }

  Future<void> _dispatch(InventoryOperation operation) async {
    switch (_status) {
      case SyncStatus.online:
        final delivered = await _mqttService.publish(operation);
        if (!delivered) {
          await _enqueue(operation);
        }
      case SyncStatus.localNetworkOnly:
        // Real-time peer update over the LAN now, but the cloud copy is a
        // *separate concern* - still queue for MQTT so the moment internet
        // returns this operation reaches devices that were never on this
        // Wi-Fi (e.g. a warehouse manager checking from home).
        await _udpService.broadcast(operation);
        await _enqueue(operation);
      case SyncStatus.offline:
      case SyncStatus.connecting:
        await _enqueue(operation);
    }
  }

  // -------------------------------------------------------------------
  // Offline queue
  // -------------------------------------------------------------------

  Future<void> _enqueue(InventoryOperation operation) async {
    await _queueStore.enqueue(
      PendingOperation(
        operation: operation,
        status: PendingStatus.pending,
        retryCount: 0,
        enqueuedAt: DateTime.now(),
      ),
    );
    AppLogger.queue('Enqueued ${operation.operationId} (pending=$currentPendingCount)');
    _pendingCountController.add(currentPendingCount);
  }

  Future<void> _flushQueue() async {
    final pending = _queueStore.loadPending();
    if (pending.isEmpty) return;

    AppLogger.queue('Flushing ${pending.length} pending operation(s)');
    for (final entry in pending) {
      // Connection may drop mid-flush; anything not yet sent stays queued
      // for the next reconnect or retry timer tick.
      if (!_mqttService.isConnected) break;

      await _queueStore.updateStatus(entry.operation.operationId, PendingStatus.syncing);
      final delivered = await _mqttService.publish(entry.operation);

      if (delivered) {
        await _queueStore.remove(entry.operation.operationId);
        // The operation itself was queued while offline, so the retained
        // state topic was never updated for it at the time - do that now
        // so a device that joins later gets the fully caught-up value.
        await _publishStateIfOnline(entry.operation.itemId, entry.operation.operationId);
      } else {
        await _queueStore.updateStatus(
          entry.operation.operationId,
          PendingStatus.failed,
          retryCount: entry.retryCount + 1,
        );
      }
    }

    _pendingCountController.add(currentPendingCount);
    _scheduleQueueRetryIfNeeded();
  }

  void _scheduleQueueRetryIfNeeded() {
    _queueRetryTimer?.cancel();
    if (currentPendingCount == 0) return;
    _queueRetryTimer = Timer(AppConstants.queueRetryInterval, () {
      if (_mqttService.isConnected) unawaited(_flushQueue());
    });
  }

  // -------------------------------------------------------------------
  // Applying operations (local taps + remote deliveries)
  // -------------------------------------------------------------------

  Future<void> _applyLocal(InventoryOperation operation) async {
    if (_processedStore.hasProcessed(operation.operationId)) {
      AppLogger.sync('Ignoring duplicate operation ${operation.operationId}');
      return;
    }
    await _processedStore.markProcessed(operation.operationId);

    final current = _items[operation.itemId];
    if (current == null) {
      AppLogger.sync('Operation for unknown item ${operation.itemId} - ignored');
      return;
    }

    // Deltas commute, so concurrent +1s from two devices both apply instead
    // of one clobbering the other. Clamping at zero is a deliberate,
    // documented tradeoff: it keeps quantity non-negative for the UI at the
    // cost of perfect commutativity in rare near-zero race conditions (see
    // README "Known Limitations").
    final newQuantity = (current.quantity + operation.delta).clamp(0, 1 << 30);
    final updated = current.copyWith(quantity: newQuantity, updatedAt: DateTime.now());

    _items[operation.itemId] = updated;
    await _inventoryStore.saveItem(updated);
    _itemsController.add(currentItems);
    await _publishStateIfOnline(operation.itemId, operation.operationId);
  }

  /// Reconciles a retained state snapshot received on (re)subscribe. This is
  /// what lets a device catch up on changes it entirely missed while
  /// offline - [_applyLocal]/[incomingOperations] only reach devices that
  /// were connected and subscribed at the moment an operation was published.
  ///
  /// A retained publish is *also* delivered live to every already-subscribed
  /// client (retain only changes what a *future* subscriber gets), so a
  /// connected device normally receives both the delta operation and an
  /// echo of the resulting state for the very same change. [snapshot]
  /// carries the id of the operation that produced it, so that echo is
  /// recognized via the exact same processed-operation de-dupe set used for
  /// [incomingOperations] instead of being applied a second time - this is
  /// what prevents a single remote `+1` from being counted twice.
  void _reconcileState(ItemStateSnapshot snapshot) {
    if (_processedStore.hasProcessed(snapshot.lastOperationId)) {
      // Already know about this change - just the live echo of a retained
      // publish (ours or someone else's), not new information.
      return;
    }

    final remote = snapshot.item;
    final local = _items[remote.id];

    final hasUnsyncedLocalEdit =
        local != null && _queueStore.loadPending().any((p) => p.operation.itemId == remote.id);

    final recentLocalEditAt = _recentLocalEditAt[remote.id];
    final withinGracePeriod = recentLocalEditAt != null &&
        DateTime.now().difference(recentLocalEditAt) < AppConstants.retainedStateGracePeriod;

    if (hasUnsyncedLocalEdit || withinGracePeriod) {
      // Don't clobber a local edit with a snapshot that doesn't know about
      // it. The queue check covers "not yet published"; the grace-period
      // check covers the moment right after it *was* published, where a
      // concurrent peer's own (equally uninformed) snapshot can otherwise
      // race in and look "safe" purely because our queue just emptied.
      // Once this device's own operation propagates over the operations
      // topic, [_applyLocal] merges it into everyone's state correctly
      // regardless of this skip.
      AppLogger.sync(
        'Ignoring retained state for ${remote.id} - local edit in flight',
      );
      return;
    }

    _items[remote.id] = remote;
    unawaited(_inventoryStore.saveItem(remote));
    unawaited(_processedStore.markProcessed(snapshot.lastOperationId));
    _itemsController.add(currentItems);
    AppLogger.sync(
      'Caught up ${remote.id} -> qty=${remote.quantity} from retained state '
      '(operation ${snapshot.lastOperationId})',
    );
  }

  Future<void> _publishStateIfOnline(String itemId, String causeOperationId) async {
    if (!_mqttService.isConnected) return;
    final item = _items[itemId];
    if (item == null) return;
    await _mqttService.publishItemState(item, causeOperationId);
  }

  Future<void> dispose() async {
    _queueRetryTimer?.cancel();
    await _mqttConnSub?.cancel();
    await _mqttOpsSub?.cancel();
    await _mqttStateSub?.cancel();
    await _udpOpsSub?.cancel();
    await _networkSub?.cancel();
    await _mqttService.disconnect();
    await _udpService.stop();
    await _networkMonitor.dispose();
    await _itemsController.close();
    await _statusController.close();
    await _pendingCountController.close();
  }
}
