import 'package:flutter_test/flutter_test.dart';
import 'package:smartnode_task/core/network/local_connectivity.dart';
import 'package:smartnode_task/core/sync/sync_manager.dart';
import 'package:smartnode_task/core/utils/id_generator.dart';
import 'package:smartnode_task/domain/entities/inventory_item.dart';
import 'package:smartnode_task/domain/entities/inventory_operation.dart';
import 'package:smartnode_task/domain/entities/item_state_snapshot.dart';
import 'package:smartnode_task/domain/entities/sync_status.dart';

import '../fakes/fake_connectivity_monitor.dart';
import '../fakes/fake_mqtt_service.dart';
import '../fakes/fake_udp_service.dart';
import '../fakes/in_memory_local_stores.dart';

InventoryItem _seedItem({int quantity = 10}) => InventoryItem(
      id: 'item-1',
      name: 'Widget A',
      quantity: quantity,
      updatedAt: DateTime(2026, 1, 1),
    );

class _Harness {
  _Harness({LocalConnectivity connectivity = LocalConnectivity.wifi})
      : mqtt = FakeMqttService(),
        udp = FakeUdpService(),
        network = FakeConnectivityMonitor(connectivity),
        inventoryStore = InMemoryInventoryLocalStore(),
        queueStore = InMemoryOperationQueueStore(),
        processedStore = InMemoryProcessedOperationsStore() {
    manager = SyncManager(
      mqttService: mqtt,
      udpService: udp,
      networkMonitor: network,
      inventoryStore: inventoryStore,
      queueStore: queueStore,
      processedStore: processedStore,
      idGenerator: IdGenerator(),
      deviceId: 'device-under-test',
    );
  }

  final FakeMqttService mqtt;
  final FakeUdpService udp;
  final FakeConnectivityMonitor network;
  final InMemoryInventoryLocalStore inventoryStore;
  final InMemoryOperationQueueStore queueStore;
  final InMemoryProcessedOperationsStore processedStore;
  late final SyncManager manager;

  Future<void> init() => manager.init([_seedItem()]);
}

void main() {
  group('SyncManager transport selection', () {
    test('online: publishes directly over MQTT, nothing queued', () async {
      final h = _Harness();
      await h.init();
      h.mqtt.setConnected(true);
      await pumpEventQueue();

      await h.manager.changeQuantity('item-1', 1);

      expect(h.mqtt.published, hasLength(1));
      expect(h.mqtt.published.single.delta, 1);
      expect(h.queueStore.loadPending(), isEmpty);
      expect(h.manager.currentItems.single.quantity, 11);
    });

    test('offline: change is applied locally and queued, nothing published', () async {
      final h = _Harness(connectivity: LocalConnectivity.none);
      await h.init();

      await h.manager.changeQuantity('item-1', 1);

      expect(h.mqtt.published, isEmpty);
      expect(h.udp.broadcasted, isEmpty);
      expect(h.queueStore.loadPending(), hasLength(1));
      expect(h.manager.currentItems.single.quantity, 11);
      expect(h.manager.currentStatus, SyncStatus.offline);
    });

    test('local network only: broadcasts over UDP AND still queues for eventual MQTT sync', () async {
      final h = _Harness(connectivity: LocalConnectivity.wifi);
      await h.init();
      // MQTT never connects -> stays on Wi-Fi-only fallback.

      await h.manager.changeQuantity('item-1', 1);

      expect(h.manager.currentStatus, SyncStatus.localNetworkOnly);
      expect(h.udp.broadcasted, hasLength(1));
      expect(h.queueStore.loadPending(), hasLength(1),
          reason: 'UDP delivery must not cause the cloud queue entry to be dropped');
    });

    test('MQTT reconnect flushes the queue built up while offline', () async {
      final h = _Harness(connectivity: LocalConnectivity.none);
      await h.init();

      await h.manager.changeQuantity('item-1', 1);
      await h.manager.changeQuantity('item-1', 1);
      expect(h.queueStore.loadPending(), hasLength(2));

      h.network.set(LocalConnectivity.wifi);
      h.mqtt.setConnected(true);
      await pumpEventQueue();

      expect(h.queueStore.loadPending(), isEmpty);
      expect(h.mqtt.published, hasLength(2));
      expect(h.manager.currentStatus, SyncStatus.online);
    });
  });

  group('SyncManager idempotency and conflict handling', () {
    test('duplicate operation id (redelivery) is applied only once', () async {
      final h = _Harness();
      await h.init();

      final op = InventoryOperation(
        operationId: 'dup-op',
        itemId: 'item-1',
        delta: 1,
        deviceId: 'other-device',
        timestamp: DateTime.now(),
      );

      h.mqtt.simulateIncoming(op);
      h.mqtt.simulateIncoming(op); // redelivered, e.g. QoS 1 retry
      await pumpEventQueue();

      expect(h.manager.currentItems.single.quantity, 11);
    });

    test('two concurrent +1 operations from different devices both apply (no lost update)', () async {
      final h = _Harness();
      await h.init();

      h.mqtt.simulateIncoming(InventoryOperation(
        operationId: 'op-a',
        itemId: 'item-1',
        delta: 1,
        deviceId: 'device-a',
        timestamp: DateTime.now(),
      ));
      h.mqtt.simulateIncoming(InventoryOperation(
        operationId: 'op-b',
        itemId: 'item-1',
        delta: 1,
        deviceId: 'device-b',
        timestamp: DateTime.now(),
      ));
      await pumpEventQueue();

      expect(h.manager.currentItems.single.quantity, 12);
    });

    test('operation for an unknown item id is ignored without crashing', () async {
      final h = _Harness();
      await h.init();

      h.mqtt.simulateIncoming(InventoryOperation(
        operationId: 'op-x',
        itemId: 'does-not-exist',
        delta: 1,
        deviceId: 'device-a',
        timestamp: DateTime.now(),
      ));
      await pumpEventQueue();

      expect(h.manager.currentItems.single.quantity, 10);
    });

    test('quantity cannot go below zero and decrementing at zero is a no-op', () async {
      final h = _Harness();
      h.mqtt.setConnected(true);
      await h.manager.init([_seedItem(quantity: 0)]);
      await pumpEventQueue();

      await h.manager.changeQuantity('item-1', -1);

      expect(h.manager.currentItems.single.quantity, 0);
      expect(h.mqtt.published, isEmpty, reason: 'no-op change should not publish anything');
    });
  });

  group('SyncManager retained-state catch-up (device B was offline during a remote change)', () {
    test(
        'a device that (re)connects after missing an operation entirely still '
        'converges once it receives the retained state snapshot', () async {
      // Device B was disconnected the whole time device A's change happened,
      // so it never saw the operation on the live operations topic - this
      // reproduces the originally reported bug.
      final h = _Harness();
      await h.init();
      expect(h.manager.currentItems.single.quantity, 10);

      // B (re)connects and subscribes; the broker replays A's last-known
      // retained value for the item, which B missed entirely.
      h.mqtt.setConnected(true);
      await pumpEventQueue();
      h.mqtt.simulateIncomingState(ItemStateSnapshot(
        item: InventoryItem(
          id: 'item-1',
          name: 'Widget A',
          quantity: 15,
          updatedAt: DateTime.now(),
        ),
        lastOperationId: 'a-never-seen-op',
      ));
      await pumpEventQueue();

      expect(h.manager.currentItems.single.quantity, 15);
    });

    test(
        'REGRESSION: a device applying its own operation does not double-count '
        'when the retained-state publish is echoed back to it live', () async {
      // MQTT delivers a retained publish live to already-subscribed clients
      // too (retain only changes what a *future* subscriber gets) - so the
      // publishing device itself can receive its own state echo back. This
      // reproduces the originally reported "+1 shows up as +2" bug.
      final h = _Harness();
      await h.init();
      h.mqtt.setConnected(true);
      await pumpEventQueue();

      await h.manager.changeQuantity('item-1', 1); // -> 11, publishes op + retained state

      final causingOp = h.mqtt.published.single;
      h.mqtt.simulateIncomingState(ItemStateSnapshot(
        item: h.manager.currentItems.single,
        lastOperationId: causingOp.operationId,
      ));
      await pumpEventQueue();

      expect(h.manager.currentItems.single.quantity, 11, reason: 'not 12 - the echo must be a no-op');
    });

    test(
        'REGRESSION: receiving a remote operation AND its retained-state echo '
        'applies the change exactly once, regardless of arrival order', () async {
      final h = _Harness();
      await h.init();

      final op = InventoryOperation(
        operationId: 'remote-op-1',
        itemId: 'item-1',
        delta: 1,
        deviceId: 'device-a',
        timestamp: DateTime.now(),
      );
      final snapshot = ItemStateSnapshot(
        item: InventoryItem(id: 'item-1', name: 'Widget A', quantity: 11, updatedAt: DateTime.now()),
        lastOperationId: 'remote-op-1',
      );

      // Operation first, then its echo.
      h.mqtt.simulateIncoming(op);
      h.mqtt.simulateIncomingState(snapshot);
      await pumpEventQueue();
      expect(h.manager.currentItems.single.quantity, 11);
    });

    test(
        'REGRESSION: the retained-state echo arriving BEFORE its operation still '
        'applies the change exactly once', () async {
      final h = _Harness();
      await h.init();

      final op = InventoryOperation(
        operationId: 'remote-op-2',
        itemId: 'item-1',
        delta: 1,
        deviceId: 'device-a',
        timestamp: DateTime.now(),
      );
      final snapshot = ItemStateSnapshot(
        item: InventoryItem(id: 'item-1', name: 'Widget A', quantity: 11, updatedAt: DateTime.now()),
        lastOperationId: 'remote-op-2',
      );

      // Echo first, then the operation - network delivery order isn't guaranteed.
      h.mqtt.simulateIncomingState(snapshot);
      h.mqtt.simulateIncoming(op);
      await pumpEventQueue();
      expect(h.manager.currentItems.single.quantity, 11);
    });

    test('a retained snapshot is not applied while this device has its own unsynced edit queued',
        () async {
      final h = _Harness(connectivity: LocalConnectivity.none);
      await h.init();
      await h.manager.changeQuantity('item-1', 1); // queued locally at 11, offline

      h.network.set(LocalConnectivity.wifi);
      h.mqtt.setConnected(true);
      // A snapshot for an operation this device has never seen arrives
      // before this device's own flush has published its edit - it must
      // not be adopted, or this device's own not-yet-synced change would
      // be lost.
      h.mqtt.simulateIncomingState(ItemStateSnapshot(
        item: InventoryItem(id: 'item-1', name: 'Widget A', quantity: 50, updatedAt: DateTime.now()),
        lastOperationId: 'some-other-unseen-op',
      ));

      expect(h.manager.currentItems.single.quantity, 11);
    });

    test(
        'REGRESSION: both devices offline, both edit the same item, then reconnect '
        'near-simultaneously - neither contribution is lost to the other\'s retained snapshot',
        () async {
      // This reproduces a reported bug: A and B are both offline and both
      // change the same item. When they reconnect, each flushes its own
      // queue (clearing it) right around when the OTHER device's retained
      // snapshot - computed from a view that doesn't know about this
      // device's edit - arrives. Without the grace-period guard, the
      // queue-based check alone sees "queue empty" and adopts the peer's
      // stale absolute value, silently discarding this device's own change.
      final h = _Harness(connectivity: LocalConnectivity.none);
      await h.init();

      await h.manager.changeQuantity('item-1', 1); // this device: 10 -> 11, queued

      h.network.set(LocalConnectivity.wifi);
      h.mqtt.setConnected(true);
      await pumpEventQueue(); // this device's flush publishes + clears its queue

      // The concurrent peer's own flush lands right after: a retained
      // snapshot for an operation this device has never seen, computed from
      // the peer's pre-merge view (its own +2 on top of the *original* 10,
      // i.e. 12) - it does not yet reflect this device's +1.
      h.mqtt.simulateIncomingState(ItemStateSnapshot(
        item: InventoryItem(id: 'item-1', name: 'Widget A', quantity: 12, updatedAt: DateTime.now()),
        lastOperationId: 'peer-op-1',
      ));

      // This device's contribution must survive - not be clobbered to 12.
      expect(h.manager.currentItems.single.quantity, 11);

      // The real operation for the peer's edit then arrives (as it normally
      // would, live, once both are connected) and merges correctly.
      h.mqtt.simulateIncoming(InventoryOperation(
        operationId: 'peer-op-1',
        itemId: 'item-1',
        delta: 2,
        deviceId: 'peer-device',
        timestamp: DateTime.now(),
      ));
      await pumpEventQueue();

      expect(h.manager.currentItems.single.quantity, 13, reason: '10 + this device\'s +1 + peer\'s +2');
    });

    test('publishes retained state (tagged with the causing operation id) after '
        'flushing a previously-offline operation', () async {
      final h = _Harness(connectivity: LocalConnectivity.none);
      await h.init();
      await h.manager.changeQuantity('item-1', 1);
      final queuedOp = h.queueStore.loadPending().single.operation;

      h.network.set(LocalConnectivity.wifi);
      h.mqtt.setConnected(true);
      await pumpEventQueue();

      expect(
        h.mqtt.publishedStates.any(
          (s) =>
              s.item.id == 'item-1' &&
              s.item.quantity == 11 &&
              s.lastOperationId == queuedOp.operationId,
        ),
        isTrue,
      );
    });
  });

  group('SyncManager lifecycle', () {
    test('onAppResumed nudges a reconnect attempt when not connected', () async {
      final h = _Harness(connectivity: LocalConnectivity.none);
      await h.init();
      expect(h.mqtt.isConnected, isFalse);

      h.manager.onAppResumed();
      h.mqtt.setConnected(true);
      await pumpEventQueue();

      expect(h.manager.currentStatus, SyncStatus.online);
    });
  });

  group('SyncManager queue resilience', () {
    test('a failed publish during flush keeps the operation queued for retry', () async {
      final h = _Harness(connectivity: LocalConnectivity.none);
      await h.init();
      await h.manager.changeQuantity('item-1', 1);

      h.network.set(LocalConnectivity.wifi);
      h.mqtt.setConnected(true);
      h.mqtt.publishShouldFail = true;
      await pumpEventQueue();

      expect(h.queueStore.loadPending(), hasLength(1));
      expect(h.mqtt.published, isEmpty);
    });
  });
}
