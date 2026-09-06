# Video Walkthrough Script (~5 minutes)

Record with a screen-share tool (Loom/Zoom) showing your phone screen(s) —
mirror both phones if your recording tool supports it (e.g. via `scrcpy`,
QuickTime for iOS, or your recorder's phone-mirroring feature), or record
each phone screen separately in a side-by-side layout. Read this as a guide,
not a word-for-word script — talk naturally, but hit every bullet.

---

## 0:00–0:30 — Intro (talking over the app UI)

*Open the app on one phone, sitting on the inventory list.*

> "This is a distributed inventory app for two warehouse workers on
> different phones. Each item has a name, a quantity, and big plus/minus
> buttons. Up here [point to top-right] is the sync status indicator —
> green for online, yellow for local-network-only, red for offline. The
> requirement was to keep both devices in sync across all three of those
> states, without using Firebase or any backend-as-a-service — just MQTT
> and UDP, hand-implemented."

---

## 0:30–2:30 — Demonstration (both phones side by side)

### Cloud sync (🟢 Online) — ~40s

*Both phones on screen, both showing the green badge.*

> "Both phones are online right now, connected to a public MQTT broker,
> test.mosquitto.org. Watch what happens when I tap plus on this one —
> [tap +] — and the other phone updates within about a second, with zero
> interaction on that device. That's a live MQTT publish/subscribe round
> trip."

### Offline queue (🔴 Offline) — ~50s

*Turn on airplane mode on phone A.*

> "Now I'll cut the internet on this phone — airplane mode. Notice the
> badge immediately turns red, but the app doesn't lock up: I can still
> change quantities right now [tap +/- a couple times] and the UI responds
> instantly every time. These changes are being saved locally and queued —
> they haven't gone anywhere yet."

*Turn airplane mode back off.*

> "And when I turn the internet back on... [pause 2-3s] ...the badge flips
> back to green, and moments later the other phone picks up every change I
> made while offline. Nothing was lost."

### Local network fallback (🟡 Local Network Only) — ~60s

*Show your hotspot-client setup: one phone as a mobile hotspot with data
off, the other connected to it as a Wi-Fi client.*

> "For the last scenario — both devices lose internet but stay on the same
> Wi-Fi — I've set one phone up as a hotspot with its mobile data switched
> off, so there's genuinely no internet anywhere in this picture, and
> connected the second phone to it as a normal Wi-Fi client. That client
> phone shows the yellow 'Local Network Only' badge. Watch: I change a
> quantity here [tap +] — and it reaches the other phone directly over the
> Wi-Fi, via a UDP broadcast, with no internet involved at all."

---

## 2:30–4:00 — Architecture walkthrough

*Switch to your editor. Go through the points below in order — each one
names the exact file, the exact lines, and what to say about them. Open
only these files; nothing else is worth screen time for a 5-minute video.*

### Point 0 — Folder structure (~20s, no file open yet)

*Show the `lib/` tree (sidebar, or run `tree lib` in a terminal).*

> "The code is split into four layers: `core` for cross-cutting stuff like
> constants and the sync orchestrator, `domain` for plain entities and
> abstract interfaces, `data` for the concrete MQTT, UDP, and Hive
> implementations, and `presentation` for the UI. Nothing in `presentation`
> ever imports `mqtt_client`, `dart:io` sockets, or `hive` directly."

### Point 1 — File: `lib/domain/entities/inventory_operation.dart` — Lines 5–16

*Open the file, point at the class doc comment.*

> "Every change is modeled as an operation, not a new absolute quantity —
> a delta like plus-one, tagged with a unique operation ID, a device ID,
> and a timestamp. Deltas commute: two devices both tapping plus-one on the
> same item at the same time both count, instead of one overwriting the
> other. That one design decision is what the rest of the sync logic is
> built around."

### Point 2 — File: `lib/core/sync/sync_manager.dart` — Lines 149–169 (`_recomputeStatus`)

*Scroll to this method.*

> "This is the one place that decides the sync status. Line 151: is MQTT
> actually connected? If so, we're online. Line 153: if not, is there
> Wi-Fi? Then it's local-network-only. Line 155: no network at all means
> offline. Notice it checks MQTT connection first, not just 'is there
> internet' — because Wi-Fi being up doesn't mean the broker is reachable,
> and that distinction is exactly what the task asked us to handle
> correctly."

### Point 3 — File: `lib/core/sync/sync_manager.dart` — Lines 178–196 (`_dispatch`)

*Scroll down to this method, right below the last one.*

> "Once we know the status, this method decides what to actually do with
> an operation. Online, at line 181: publish it straight to MQTT.
> Local-network-only, at lines 190–191: broadcast it over UDP for the
> other device to see right now — but also enqueue it, because the Wi-Fi
> peer isn't the only consumer that matters; someone checking from the
> cloud later still needs to see it. Offline, at line 194: just enqueue.
> That's the entire MQTT-vs-UDP-vs-queue decision, in one method."

### Point 4 — File: `lib/core/sync/sync_manager.dart` — Lines 259–284 (`_applyLocal`)

*Scroll to this method.*

> "This is where an operation actually changes a quantity — whether it
> came from this device's own tap, or arrived from MQTT or UDP. Line 260:
> first check, has this exact operation ID already been processed? If so,
> ignore it — that's the idempotency guard, it's what makes a duplicate
> MQTT redelivery, or the same change arriving over both UDP and MQTT,
> safe. Line 277: the actual merge — add the delta to the current
> quantity, clamped at zero."

### Point 5 — File: `lib/data/mqtt/mqtt_service_impl.dart` — Lines 95–99 and Lines 159–176

*Open this file, point at lines 95–99 first, then scroll to 159–176.*

> "This is the real MQTT client, not a wrapper around a backend service.
> Lines 95 to 99: on connect, it subscribes to two topics — the live
> operations topic, and a wildcard for retained per-item state, which is
> what lets a device that reconnects later catch up on changes it missed
> entirely. Lines 159 to 176 are the actual publish call — plain
> `mqtt_client` publishMessage, QoS 1."

### Point 6 — File: `lib/data/udp/udp_service_impl.dart` — Lines 27–47 and Lines 70–87

*Open this file, point at the `start()` method, then `broadcast()`.*

> "And this is the UDP side — a plain `RawDatagramSocket` from `dart:io`.
> `start()`, lines 27 to 47, binds the socket and turns on broadcast.
> `broadcast()`, lines 70 to 87, sends the operation as JSON to
> 255.255.255.255 on a fixed port. No discovery protocol, no pairing —
> just listen and shout, which is all this challenge's 'same Wi-Fi router'
> scope needs."

### Point 7 — File: `lib/presentation/controllers/inventory_controller.dart` — Lines 13–17 and Lines 81–93

*Open this file last, point at the class doc comment, then `changeQuantity`.*

> "And finally, this is the only file the UI actually talks to. Lines 13
> to 17: it never touches MQTT, UDP, or storage directly. Lines 81 to 93:
> when a button is tapped, it just calls the repository and updates state
> if that throws — there's no networking type anywhere in this file. That
> separation is what the task's 'keep networking and UI logic separate'
> constraint meant in practice."

---

## 4:00–4:45 — What made this interesting

> "The trickiest part wasn't the happy path — it was catching a device up
> that missed a change entirely while fully disconnected, since MQTT
> doesn't replay missed messages to a new subscriber. I added a retained
> 'current state' topic per item for that. But that surfaced two real bugs
> during testing on physical devices: a retained publish also echoes back
> live to already-connected clients, which was double-counting changes —
> fixed by tagging every state snapshot with the operation ID that caused
> it. And when both devices were offline, edited the same item, and
> reconnected at the same time, there was a race where one device's edit
> could get silently overwritten by the other's stale snapshot — fixed
> with a short grace window. Both are covered by regression tests now."

---

## 4:45–5:00 — Close

> "Known limitations are documented honestly in the README — this uses a
> public, unauthenticated broker which is fine for a demo but not
> production, and UDP broadcast won't get through networks with
> client-isolation enabled, which is a property of the network, not the
> app. That's the walkthrough — thanks for watching."

---

## Code walkthrough cheat sheet

Exactly which files to have open, in which order, and which lines to point
at — nothing else needs screen time in a 5-minute video. (Line numbers as
of this script's writing; if you've edited these files since, re-check them
before recording.)

| # | File | Lines | Point at |
|---|---|---|---|
| 1 | `lib/domain/entities/inventory_operation.dart` | 5–16 | The doc comment explaining delta-based, commutative operations. |
| 2 | `lib/core/sync/sync_manager.dart` | 149–169 | `_recomputeStatus()` — the MQTT-connected / Wi-Fi / offline decision. |
| 3 | `lib/core/sync/sync_manager.dart` | 178–196 | `_dispatch()` — what happens for each `SyncStatus` (publish / UDP+queue / queue only). |
| 4 | `lib/core/sync/sync_manager.dart` | 259–284 | `_applyLocal()` — the idempotency check (line 260) and the delta merge (line 277). |
| 5 | `lib/data/mqtt/mqtt_service_impl.dart` | 95–99, 159–176 | Subscribing to both topics on connect; the real `publishMessage` call. |
| 6 | `lib/data/udp/udp_service_impl.dart` | 27–47, 70–87 | `start()` binding the broadcast socket; `broadcast()` sending the packet. |
| 7 | `lib/presentation/controllers/inventory_controller.dart` | 13–17, 81–93 | The doc comment + `changeQuantity()` — proof the UI never sees networking types. |

Optional, only if you have time left after the "what made this interesting"
section:

| # | File | Lines | Point at |
|---|---|---|---|
| 8 | `lib/core/sync/sync_manager.dart` | 299–339 | `_reconcileState()` — the retained-state catch-up and the two bugs it took to get right. |
| 9 | `test/unit/sync_manager_test.dart` | — | The regression tests reproducing those two bugs (search for "REGRESSION" in the file). |

For each row: open the file, scroll to the line range, point at it on
screen, and say the one or two sentences of narration written for that
point above — don't read the surrounding code line-by-line.
