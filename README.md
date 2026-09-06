## 🎥 Video Walkthrough

**[Watch the demo & architecture walkthrough here](https://drive.google.com/file/d/1t4WOefVNqx84zXolYZY7_zb9Ot9lW8z6/view?usp=sharing)**

---

# Distributed Inventory Sync

A Flutter "Live Distributed Inventory" app for two warehouse workers on
different phones, built for the Smartnode take-home challenge. It keeps
inventory quantities in sync across three network conditions:

| Condition | Transport | Indicator |
|---|---|---|
| Both devices online | MQTT (cloud) | 🟢 Online |
| Broker unreachable, same Wi-Fi | UDP broadcast (LAN) | 🟡 Local Network Only |
| No network at all | Local queue only | 🔴 Offline |

No Firebase/BaaS is used anywhere. MQTT and UDP are hand-implemented on top
of `mqtt_client` and `dart:io` sockets respectively.

## Project Overview

Two warehouse workers tap `+`/`-` on shared inventory items from their own
phones. The app has to keep both screens converged no matter what the
network is doing, and it must never block a worker's tap on a network round
trip. The approach:

1. **Every tap applies instantly and locally** (optimistic update, persisted
   to Hive immediately).
2. **The same change is described as a small, immutable "operation"**
   (`+1` on item X) rather than a new absolute quantity, and dispatched
   through whichever transport is currently viable.
3. **A `SyncManager` decides, from a single source of truth, whether to use
   MQTT, UDP, or just the offline queue** - and it always keeps a durable
   record until an operation is confirmed delivered to the cloud, even if it
   was *also* delivered instantly over the LAN.

## Architecture

```
                    presentation/
                 ┌───────────────────┐
                 │  InventoryScreen   │  (StatelessWidget, Consumer<InventoryController>)
                 └─────────┬──────────┘
                           │ reads/calls
                 ┌─────────▼──────────┐
                 │ InventoryController │  (ChangeNotifier - the ONLY thing the UI talks to)
                 └─────────┬──────────┘
                           │
                    domain/repositories
                 ┌─────────▼──────────┐
                 │ InventoryRepository │  (thin interface + impl, no logic of its own)
                 └─────────┬──────────┘
                           │
                     core/sync
                 ┌─────────▼──────────┐
                 │     SyncManager      │  ← decision point: MQTT vs UDP vs Queue
                 │  (dedupe, conflict   │
                 │   resolution, queue) │
                 └──┬─────────┬──────┬─┘
                    │         │      │
             ┌──────▼──┐ ┌────▼───┐ ┌▼──────────────┐
             │  MQTT    │ │  UDP   │ │  Hive local DB │
             │ (cloud)  │ │ (LAN)  │ │ (items, queue, │
             │          │ │        │ │ processed-ops) │
             └──────────┘ └────────┘ └────────────────┘
```

### Folder structure

```
lib/
├── core/
│   ├── constants/app_constants.dart   # broker/topic/port/QoS - all in one place
│   ├── errors/app_exceptions.dart     # app-level exception types
│   ├── network/                       # connectivity TYPE detection (wifi/mobile/none)
│   ├── sync/sync_manager.dart         # the orchestrator (see below)
│   └── utils/                         # logger, id generator
│
├── domain/
│   ├── entities/                      # InventoryItem, InventoryOperation, PendingOperation, SyncStatus
│   ├── repositories/                  # abstract InventoryRepository + local store contracts
│   └── services/                      # abstract MqttService, UdpService, ConnectivityMonitor
│
├── data/
│   ├── local/                         # Hive implementations of the store contracts
│   ├── mqtt/mqtt_service_impl.dart    # real mqtt_client-backed implementation
│   ├── udp/udp_service_impl.dart      # real RawDatagramSocket-backed implementation
│   └── repositories/                  # InventoryRepositoryImpl (delegates to SyncManager)
│
├── presentation/
│   ├── controllers/inventory_controller.dart
│   ├── screens/inventory_screen.dart
│   └── widgets/                       # SyncStatusBadge, InventoryItemTile, InventorySummaryBar
│
└── main.dart                          # composition root - wires concrete impls to interfaces
```

Every arrow in the diagram above is an abstract interface (`MqttService`,
`UdpService`, `ConnectivityMonitor`, `InventoryLocalStore`,
`OperationQueueStore`, `ProcessedOperationsStore`). Widgets never import
`mqtt_client`, `dart:io`, or `hive` - only `main.dart` (the composition root)
wires the concrete implementations together. This is what makes
`SyncManager` unit-testable with in-memory/fake doubles (see `test/`),
without a real broker or a physical Wi-Fi network.

## Synchronization Strategy

### Data model: operations, not snapshots

Instead of publishing `quantity = 6`, the app publishes an *operation*:
`{ operationId, itemId, delta: +1, deviceId, timestamp }`. Deltas commute:
if two devices both tap `+1` on the same item at the same time, applying
`+1` then `+1` gives the same converged result regardless of the order they
arrive in. A naive "last write wins on the absolute value" design would
instead let one device's write clobber the other's - a classic lost-update
bug. This is documented in `domain/entities/inventory_operation.dart`.

**Known limitation:** quantity is clamped at 0 for display sanity (can't show
negative stock). That clamp technically breaks pure commutativity in a rare
edge case - two devices racing `-1` on an item at quantity 1 could converge
to 0 instead of the "mathematically correct" -1. This is an intentional,
documented tradeoff: a real distributed counter (e.g. a PN-Counter CRDT)
would handle it, but it's out of scope for a demo where inventory can't
sensibly go negative anyway.

### When each transport is used

`SyncManager` (`core/sync/sync_manager.dart`) recomputes a `SyncStatus`
whenever either the MQTT connection state or the local connectivity type
changes:

```
MQTT connected?
  └─ yes → 🟢 ONLINE        → publish directly over MQTT
  └─ no  → Wi-Fi present?
             └─ yes → 🟡 LOCAL NETWORK ONLY → UDP broadcast + still enqueue for MQTT
             └─ no  → any network at all?
                        └─ no  → 🔴 OFFLINE  → enqueue only
                        └─ yes → CONNECTING  → enqueue only (mobile data/ethernet
                                                 present but MQTT hasn't resolved yet)
```

Important: **UDP delivery and MQTT/cloud delivery are treated as separate
concerns.** When on Wi-Fi-only, an operation is broadcast over UDP for the
other device on the same LAN to see *right now*, but it is *also* pushed
onto the durable offline queue, because the LAN peer isn't the only consumer
that matters - a manager checking from home over the cloud still needs to
see it eventually. Successfully sending over UDP never causes an operation
to be dropped from the queue.

### Network detection: Wi-Fi ≠ internet

`connectivity_plus` answers "what kind of network interface is up?"
(Wi-Fi / mobile / none) - not "is the internet reachable?" Those are
different questions: a phone can be on Wi-Fi with no internet (captive
portal, router with no WAN). This app treats **MQTT connection success** as
the actual proof of internet reachability, and connectivity type only as
"is there a LAN to fall back to?" This is why the state machine checks MQTT
first, then Wi-Fi, then "nothing."

### Offline queue

Every operation dispatched while not confirmed-delivered to MQTT is
persisted to a Hive box (`PendingOperation`: the operation + status +
retry count + enqueue time), **not just held in memory** - so an app kill
mid-sync (or while fully offline for hours) never silently loses a change.
When MQTT reports "connected", `SyncManager` flushes the queue oldest-first,
removing an entry only after the broker has accepted the publish call for
that operation. If the connection drops mid-flush, the remaining entries
stay queued and a retry timer (`AppConstants.queueRetryInterval`) picks them
up later.

### Idempotency / duplicate handling

Every operation carries a globally unique `operationId` (UUID v4). A
persistent "processed operation ids" set (`ProcessedOperationsStore`) is
checked before applying *any* operation - local or remote. This makes the
following all safe:

- MQTT QoS 1 redelivering the same message after a dropped ack.
- The same operation arriving over both UDP and MQTT (LAN peer got it via
  UDP, then it also comes through the cloud once reconnected).
- A device receiving its own broadcast (defensive check - `deviceId` is
  compared even though `test.mosquitto.org` and this app's own UDP loop
  don't normally echo back to the sender).

**Known limitation:** the processed-ops set is unbounded for the life of
the app install. Acceptable for a demo; a production version would prune
entries past a retention window (e.g. keep 7 days by `timestamp`).

### Catching a reconnecting device up

The delta/operations topic above only reaches devices that are *currently
subscribed* at the moment something is published - by design, MQTT (without
a persistent broker-side session) does not replay missed messages. That
means a device that was fully offline while another device made a change
would never see it, even after reconnecting - `SyncManager`'s queue-flush
only replays *that device's own* pending edits, not what it missed from
others.

This is solved with a second, **retained** topic per item:
`inventory/demo/{warehouseId}/state/{itemId}`. Whenever an operation is
applied (locally or remotely) while connected, the device also publishes
the item's now-current quantity there with MQTT's `retain` flag set. The
broker keeps only the latest retained message per topic and delivers it
immediately to anyone who (re)subscribes - including long after the
original publish. On connect, the app subscribes to
`inventory/demo/{warehouseId}/state/#`, so a reconnecting device gets every
item's latest known value as part of simply subscribing, independent of how
many operations it missed.

Adopting a retained snapshot is deliberately conservative
(`SyncManager._reconcileState`) and guarded two ways:

1. **Still queued:** skipped while this device has an unsynced edit of its
   own for that item sitting in the offline queue.
2. **Recently published (grace period):** skipped for `retainedStateGracePeriod`
   (10s) after this device's own edit to that item, even once it's been
   flushed out of the queue.

Guard 2 exists because of a race the first version of this feature missed:
when **both** devices are offline, both edit the *same* item, and then both
reconnect at roughly the same time, each device's own flush empties its
queue almost immediately - and right around then, the *other* device's
retained snapshot (computed from a view that doesn't know about this
device's edit yet) can arrive and pass the queue check purely because the
queue happens to be empty by that point, silently discarding this device's
own contribution. The grace period closes that window for the realistic
case of two devices reconnecting to a public broker at about the same time;
once this device's own operation propagates over the live operations
topic, `_applyLocal`'s commutative-delta merge picks it up correctly
regardless of this skip.

**A subtlety this uncovered:** a retained publish is *also* delivered live
to every client that's already subscribed - `retain` only changes what a
*future* subscriber receives. That means an already-connected device
normally receives **both** the delta operation and a live echo of the
resulting state for the very same change. Without de-duplication that
double-applies the change (a `+1` from another device showing up as `+2`
locally). The fix: every `ItemStateSnapshot` is tagged with the id of the
operation that produced it (`lastOperationId`), and reconciliation checks
that id against the exact same processed-operation set used for
`incomingOperations` - so the echo is recognized as "already known" and
ignored, regardless of whether the operation or its state echo arrives
first.

### QoS and topic design

- **Broker:** `test.mosquitto.org:1883` (public, unauthenticated - see
  Security below).
- **Topics:** `inventory/demo/{warehouseId}` (non-retained operations/deltas)
  and `inventory/demo/{warehouseId}/state/{itemId}` (retained current-value
  snapshots, one sub-topic per item - see "Catching a reconnecting device
  up" above). `warehouseId` (in `core/constants/app_constants.dart`)
  namespaces the demo so it doesn't collide with other people's traffic on
  the same public broker. Change it if you want an isolated run.
- **QoS 1 (at least once):** guarantees delivery on reconnect without QoS
  2's extra handshake overhead. Because every operation is already
  idempotent (see above), "at least once + de-dupe" is strictly simpler and
  cheaper than paying for QoS 2's "exactly once."

## UI/UX

Built for someone scanning shelves and tapping quickly - a warehouse
operations tool, not a consumer app - but still a deliberately designed one
rather than default Material widgets:

- **Design tokens in one place** (`presentation/theme/app_theme.dart`): an
  industrial navy for structure/trust, a warm amber reserved for "needs
  attention" states (low stock, pending sync), kept visually distinct from
  the red used for offline/errors so severities never collide.
- Big (44dp) circular +/- touch targets, large tabular-figure quantity text
  (so digits don't jiggle horizontally as they change), a brief scale
  animation on the quantity itself, and light haptic feedback on tap.
- The sync indicator is an icon + colored pill with a plain-English label
  ("Local Network Only", not "MQTT disconnected, Wi-Fi up"). Tapping it
  shows a one-line, non-technical explanation.
- A compact summary bar (item count, total units, pending-sync count) gives
  an at-a-glance shelf status without adding another screen or a card-heavy
  dashboard.
- Items at or below `AppConstants.lowStockThreshold` get a small "Low
  stock" tag - a genuinely useful warehouse affordance, not decoration.
- A quantity change is reflected on screen the instant it's tapped - no
  spinner, no blocking dialog, ever.
- Explicit loading / empty / error states, each with a soft icon treatment
  instead of a bare glyph; raw exceptions are never shown to the user
  (`AppException` subtypes carry user-safe messages instead).

## Setup

- Flutter 3.38.x / Dart 3.10.x (see `flutter --version`).
- `flutter pub get`
- Two physical devices (or a device + emulator) on the same network for the
  full demo; UDP broadcast between two emulators on the same host can be
  unreliable depending on the virtual network setup - physical devices on
  the same Wi-Fi router are recommended for Phase 3 testing.
- `flutter run` on each device.

No API keys or secrets are required - `test.mosquitto.org` is a public,
anonymous broker.

## Testing

### Automated

```
flutter analyze
flutter test
```

`test/unit/` covers, with hand-written fakes (no codegen/mocking framework
needed - see `test/fakes/`):

- Payload parsing/validation (`inventory_operation_test.dart`): valid
  payloads, missing fields, wrong types, zero delta, empty ids, garbage.
- `SyncManager` orchestration (`sync_manager_test.dart`): online → direct
  MQTT publish; offline → queue only, nothing published; Wi-Fi-only → UDP
  broadcast *and* still queued; reconnect flushes the queue; duplicate
  operation ids are applied once; two concurrent same-item operations from
  different devices both apply (no lost update); operations for unknown
  items are ignored without crashing; quantity cannot go negative; a failed
  publish during a flush leaves the operation queued for retry.
- Controller and widget-level tests for sorting/state wiring and the
  loading/empty/ready UI states.

### Manual (for the video)

**Scenario 1 - Cloud sync:** run the app on two devices with internet.
Both should show 🟢 Online. Tap `+` on device A; device B's count updates
within roughly a second with no interaction on B.

**Scenario 2 - Offline queue:** turn on airplane mode on device A. Its badge
turns 🔴 Offline. Change quantities a few times - the UI keeps responding
instantly. Turn airplane mode back off; watch the badge return to 🟢 Online
and device B receive the queued changes shortly after.

**Scenario 3 - Local fallback:** put both devices on the same Wi-Fi router
and turn off mobile data / block `test.mosquitto.org` (or just turn off the
router's internet uplink while keeping the LAN up). Both badges should turn
🟡 Local Network Only. Change a quantity on device A - device B should
update almost immediately via UDP, without either device reaching the
internet.

## Known Limitations

- **`test.mosquitto.org` is a public, unauthenticated demo broker.** Anyone
  else who knows (or brute-forces) the topic name can publish to or read
  from it. This is explicitly acceptable for this challenge but would never
  be used for real inventory data - a production build would use a private,
  authenticated broker (e.g. AWS IoT Core, HiveMQ Cloud, or self-hosted
  Mosquitto with TLS + credentials).
- **UDP broadcast has no discovery/pairing protocol** - it's a flat
  "shout on the LAN, listen on a fixed port" design. Networks with AP/client
  isolation enabled (common on some public/guest Wi-Fi) will block broadcast
  traffic between devices even though both show as "connected" - Phase 3
  will silently not work on such networks, which is a property of the
  network, not a bug in this app.
- **Conflict resolution is delta-based, not a full CRDT.** It correctly
  handles the primary "lost update" failure mode required by this
  challenge, but clamping quantity at zero is a deliberate simplification
  (see "Data model" above) rather than a mathematically perfect merge.
- **The processed-operations de-dupe set grows unbounded** for the life of
  the app install (no TTL/pruning) - fine for a demo, not for long-lived
  production use.
- **No authentication/authorization anywhere** - by design, matching the
  "no BaaS, use a free public broker" constraint of the challenge.
