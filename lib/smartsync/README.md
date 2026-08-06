# ByZra Engine

ByZra is the isolated synchronization framework boundary for BusBuddy and
future transport products. It is designed to decide when, how, and what to
synchronize instead of forwarding every GPS update directly to a backend.

The current implementation provides reusable ByZra modules plus an initial
rule-based Central Decision Engine:

- Public contracts in `interfaces/`
- Neutral immutable models in `models/`
- Configuration defaults in `configuration/`
- Module implementations under `modules/`
- Rule-based Decision Engine behavior under `engine/`
- Public package boundary in `smartsync.dart`

BusBuddy's production driver tracking path is wired through the reusable
ByZra orchestration adapter. Network, adaptive synchronization, movement,
packet optimization, retry, offline persistence, prediction, battery,
emergency, route, geofence, security, health, transport, analytics, and the
Central Decision Engine now contribute to runtime processing or telemetry.

## Module Requirements

Each module must have a single responsibility and must not directly communicate
with Firebase, REST APIs, or any BusBuddy feature. Modules report facts to the
Decision Engine through interfaces. The Decision Engine decides whether to send,
wait, queue, retry, drop, predict, or emergency-sync.

Current module folders:

- `network`: network quality, latency, packet loss, offline state
- `synchronization`: adaptive sync interval strategy, queue-only offline mode,
  and emergency interval bypass
- `packet`: compact payloads, field aliases, precision optimization,
  metadata stripping, size estimates, and future DeltaSync
- `movement`: stopped, moving, accelerating, turning, idle, parked detection,
  threshold checks, and GPS drift filtering
- `retry`: reliable delivery policy, failure classification, retry backoff,
  and queue-offline decisions after exhausted retries
- `offline`: chronological queue persistence contracts, queue item state,
  cleanup policy, and local offline batch reads
- `prediction`: temporary predicted position, ETA estimate, confidence score,
  and immediate stop when live GPS returns
- `battery`: battery-aware mode decisions, sync interval scaling, and GPS
  frequency reduction policy
- `emergency`: emergency trigger handling, immediate emergency decisions,
  compression bypass, interval bypass, and aggressive retry policy
- `route`: route loading contracts, segment progress, completion percentage,
  distance remaining, route deviation alerts, and GPS drift classification
- `geofence`: campus, bus stop, depot, and custom geofence entry, exit,
  arrival, departure, and approach events
- `security`: device validation, token validation, timestamp checks, request
  signing, replay protection, and tamper detection foundation
- `health`: engine health checks and recovery suggestions
- `transport`: transport profile configuration
- `analytics`: reserved for a future version and not implemented now

## Interfaces

The core contracts are defined in `interfaces/smartsync_interfaces.dart`.
They cover GPS providers, network monitors, packet optimizers, movement
analysis, transport delivery, offline queueing, telemetry, health checks,
configuration, and Decision Engine coordination.

## Models

The model layer is intentionally BusBuddy-independent:

- `LocationSample`
- `NetworkStatus`
- `BatteryState`
- `MovementState`
- `SyncPacket`
- `SyncDecision`
- `SyncResult`
- `HealthStatus`

## Configuration

`SmartSyncConfig.defaults()` defines configurable defaults for sync intervals,
movement thresholds, retry count, offline queue size, geofence radius,
prediction window, battery thresholds, emergency priority, and transport type.

These defaults are not final business rules. They are a safe starting point for
module-by-module implementation.

## Decision Engine Interaction

The intended runtime flow:

1. GPS provider emits a `LocationSample`.
2. Modules produce network, synchronization interval, optimized packet payload,
   movement intelligence, prediction state, battery power policy, route
   progress, geofence events, security validation, health, and queue state.
3. The Decision Engine receives a `SmartSyncDecisionContext`.
4. The Decision Engine returns a `SyncDecision`.
5. A synchronization manager executes that decision through transport, reliable
   delivery, offline queue, emergency handling, telemetry, or prediction
   services.

## Edge Cases To Handle Later

- Offline mode and network flapping
- Duplicate GPS samples
- Invalid coordinates such as `0,0`
- GPS drift and impossible jumps
- Low battery and emergency battery mode
- Retry storms and backend overload
- Oversized offline queue
- Replay attacks or tampered packets
- Emergency override
- Route deviation and geofence noise

Module 10, Learning and Analytics, is intentionally kept as a future version
area and should not be implemented for the current scenario.
