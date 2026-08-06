# Milestone 5 - ByZra Integration Audit

Status: Initial audit complete
Scope: ByZra modules, debug dashboard, test coverage, runtime wiring, app-level hardening

## Current Runtime Picture

ByZra is implemented as a reusable module layer under `lib/smartsync/`. The modules are mostly pure Dart, configurable, and unit tested. Only the Network Intelligence Module is currently wired to a real runtime source through `RuntimeNetworkMonitor`, and only inside the developer dashboard.

BusBuddy driver tracking still writes live location directly through `DriverTrackingService.updateLiveLocation()` every 5 seconds. The production location path does not yet pass through:

- Central Decision Engine
- Motion Intelligence
- Packet Optimization
- Reliable Delivery
- Offline Queue
- Security Signing
- Health Monitor

That direct path is still useful as the stable baseline, but Milestone 5 should harden it step by step instead of replacing it all at once.

## Module Runtime / Fallback Gap Table

| Area | Current State | Live Runtime? | Gap | Wire Now? |
| --- | --- | --- | --- | --- |
| Network Intelligence | `RuntimeNetworkMonitor` performs DNS/TCP probes and emits classified `NetworkStatus`. | Partial live | Uses generic host probe, not Android connectivity APIs or radio type. | Yes, keep and expose clearly in dashboard. |
| Adaptive Synchronization | Calculates interval from `NetworkStatus`. | Live when fed by dashboard network monitor | Not controlling driver GPS timer yet. | Yes, use in dashboard and later driver sync loop. |
| Packet Optimization | Produces compact payload aliases. | Pure module only | Driver tracking still sends full Firestore fields. | Later, when driver sync pipeline is introduced. |
| Motion Intelligence | Classifies movement from two GPS samples. | Pure module only | Driver tracking does not compare previous/current samples before upload. | Yes, good first runtime hardening after audit. |
| Reliable Delivery | Retry planning exists. | Pure module only | Firestore write failures are caught only by current try/catch flow. | Later with sync manager. |
| Offline Persistence | In-memory offline queue exists. | Runtime-capable but not app-wired | Not persistent/encrypted; lost on app restart. | Later; persistent storage needed first. |
| Predictive Tracking | Prediction module exists. | Pure module only | Student tracking does not consume prediction during connection loss. | Later, after live path is stable. |
| Power Optimization | Classifies battery modes from readings. | Pure module only | No real battery plugin/adapter wired. | Later unless `battery_plus` is added. |
| Emergency Communication | Priority rules exist. | Pure module only | No SOS/crash/panic UI or transport path. | Later feature. |
| Route Awareness | Route analysis exists. | Pure module only | Bus route geometry is not yet loaded into ByZra at runtime. | Later, needs route schema agreement. |
| Smart Geofence | Geofence evaluation exists. | Pure module only | Student/admin notifications do not use ByZra geofence events. | Later, after route/stops are normalized. |
| Security | Signing/validation/replay protection exists. | Pure module only | Firestore location writes are not signed; app auth is still plaintext custom auth. | Later with backend/API boundary. |
| Health Monitor | Pluggable health checks exist. | Pure module only | No GPS/Firebase/background-service health checks wired. | Yes for dashboard labeling, later for recovery. |
| Multi Transport | Transport profiles/policies exist. | Config-ready | Not connected to BusBuddy runtime config. | Later; BusBuddy can continue as college bus profile. |
| Central Decision Engine | Rule-based engine exists. | Pure module only | Not called from driver location updates. | Yes, introduce carefully in driver sync path after dashboard cleanup. |

## Debug Dashboard Audit

Current dashboard values:

| Dashboard Field | Current Source | Status |
| --- | --- | --- |
| Current Network Quality | `RuntimeNetworkMonitor` | Live |
| Latency | `RuntimeNetworkMonitor` | Live |
| Packet Loss | `RuntimeNetworkMonitor` rolling probe window | Live approximation |
| Signal Stability | `RuntimeNetworkMonitor` rolling probe window | Live approximation |
| Current Synchronization Interval | `AdaptiveSynchronizationModule` from live network status | Live derived |
| Current Engine Decision | Simple dashboard decision from network status only | Runtime-derived fallback, not Central Decision Engine |
| Retry Count | `SmartSyncDebugState.initial()` | Fallback |
| Offline Queue Size | `SmartSyncDebugState.initial()` | Fallback |
| GPS Accuracy | Hardcoded preview value in `SmartSyncDeveloperPreviewPage` | Fallback |
| Movement Status | Hardcoded preview `MovementState` | Fallback |
| Battery Mode | Hardcoded preview `BatteryState` | Fallback |
| Active Modules | Hardcoded list | Fallback |
| Recent Engine Events | Dashboard/runtime network events | Partial live |

Immediate dashboard cleanup should label each metric as `Live`, `Derived`, or `Fallback` so the dashboard does not imply full runtime integration.

## Test Coverage Audit

Existing focused test files cover:

- Architecture foundation
- Network
- Synchronization
- Packet
- Movement
- Retry
- Offline queue
- Prediction
- Battery
- Emergency
- Route
- Geofence
- Security
- Health
- Transport
- Central Decision Engine
- Debug dashboard widget rendering

Recommended test expansion for Milestone 5:

1. Central Decision Engine priority conflicts:
   - emergency while offline
   - emergency with invalid GPS
   - queue full while emergency
2. Runtime network monitor:
   - overlapping refresh does not start duplicate probes
   - stability score with mixed latency
3. Offline queue:
   - max queue behavior with cleanup
   - failed item requeue ordering
4. Security:
   - missing packet/device mismatch edge cases
   - boundary timestamp tolerance
5. Route/geofence:
   - empty route/stops
   - GPS drift plus geofence boundary
6. Debug dashboard:
   - live/fallback labels render correctly after cleanup

## App-Level Regression Checklist

Manual or emulator checks needed:

1. Splash -> restore session -> AppEntry.
2. Login for admin, driver, and student.
3. Logout from admin, driver, and student profile.
4. Admin:
   - add bus
   - assign driver
   - edit bus
   - safe delete bus
   - ByZra Debug entry appears only in debug mode
5. Driver:
   - assigned bus loads
   - start trip writes structured live location
   - stop trip updates Firestore state
   - logout stops running trip
6. Student:
   - assigned bus appears first
   - track page consumes structured `buses/{busId}.tracking`
   - running/stopped/waiting GPS statuses render correctly

## Security Hardening Plan

Current state:

- Authentication uses Firebase Authentication with role custom claims.
- Passwords are not stored or compared in Firestore.
- `app_settings/student_config.defaultPassword` is used only as input to the
  privileged account-provisioning workflow.
- ByZra location packets include validated security metadata.

Do not migrate blindly during UI/runtime cleanup. Recommended path:

1. Add Firebase Auth users for admin/driver/student identities.
2. Keep existing Firestore `users` collection as the role/profile document source.
3. On login, authenticate with Firebase Auth first.
4. Load role/profile from Firestore after Firebase Auth succeeds.
5. Move password reset/default student password workflows into Firebase Auth-compatible flows.
6. Introduce backend/API or callable function boundary for signed ByZra packets.
7. Enforce Firestore security rules based on authenticated UID and role document.

## Production Readiness Pass

Immediate production-readiness items:

- Label dashboard live/fallback values.
- Remove or clearly gate debug-only dashboard access behind `kDebugMode`.
- Update stale ByZra README text that says runtime decision behavior is not implemented.
- Keep `INTERNET` permission in main Android manifest.
- Run `dart analyze lib`.
- Run all ByZra unit tests.
- Attempt a Flutter test/build check and record any environment blocker.

Later production-readiness items:

- Persistent encrypted offline queue.
- Real battery adapter.
- Real GPS health checks.
- Background service health checks.
- Signed packet transport boundary.
- Firebase Auth migration.
- Firestore security rules review.

## Recommended Milestone 5 Order

1. Debug Dashboard cleanup: add live/derived/fallback labels.
2. Unit test expansion for dashboard labels and decision priority conflicts.
3. Wire Motion Intelligence + Central Decision Engine into driver sync path behind small helper functions.
4. Add driver runtime regression tests around sync decisions where possible.
5. App-level manual regression checks.
6. Security hardening plan document refinement and Firebase Auth migration preparation.
7. Production readiness pass.
