# BusBuddy v1.0 Production Readiness Validation

Audit date: 2026-07-24
Firebase project: `esec-bus-01`
Android validation device: OPPO CPH2223, Android 13
Build under test: release APK/AAB, version 1.0 (1)

## Certification decision

**NOT READY for production release.**

- Overall implementation completion: **72%**
- Production readiness score: **54/100**
- Internal beta readiness: **Conditional**

The core Driver GPS → ByZra → Firestore pipeline works on a real Android
device. A lifecycle defect found during this audit was fixed and retested:
Stop Trip now terminates the Android foreground tracking service.

Production certification is blocked by release signing, incomplete production
assignments/routes, incomplete Admin capabilities, absence of integration
tests, and incomplete two-device live-tracking validation.

## Status legend

- **PASS**: verified by code inspection plus an appropriate automated or
  runtime check.
- **FAIL**: required behavior or production data is missing/incorrect.
- **WARNING**: implemented, but validation is partial or a production risk
  remains.
- **NOT EXECUTED**: deliberately not triggered against production, or the
  required test environment was unavailable.

## 1. System architecture validation

| Area | Status | Evidence |
|---|---|---|
| Flutter architecture | PASS | Application builds and is separated into `app`, `core`, `features`, `shared`, and `smartsync`. |
| Clean Architecture | WARNING | Feature-first boundaries exist, but presentation calls static services directly; there is no domain/repository boundary for most features. |
| Feature modules | PASS | Admin, driver, student, authentication, tracking, and ByZra are separated. |
| Firebase Authentication | PASS | Firestore/Auth parity is 318/318; 57 sampled password sign-ins passed and both admin custom-token sessions passed. |
| Firestore | FAIL | Schema access is consistent in the app, but production relationships and route data contain 129 verifier findings. |
| Security Rules | WARNING | Local role-based deny-by-default rules exist. No emulator rules test suite was found, and deployed-rule equivalence could not be verified because Firebase CLI credentials were expired and the service account cannot list functions/rules deployments. |
| Repository layer | FAIL | No repository abstraction is present. |
| Service layer | PASS | Authentication, tracking, background location, notifications, and ByZra services are implemented. |
| State management | WARNING | `StatefulWidget`, `StreamBuilder`, and in-memory `Session` are used. This works but is not a centralized, testable state-management layer. |
| Dependency injection | FAIL | Production dependencies are largely static constructors/singletons; no DI container or composition interface is used by feature modules. |
| Error handling | WARNING | User-facing failures and local catches exist, but no global error boundary or crash-reporting integration was found. |
| Logging | WARNING | Logging is primarily `debugPrint` and ByZra telemetry. There is no centralized production log/crash sink. |
| Route management | FAIL | Admin route management is absent and production route geometry/first-stop data is inconsistent. |
| Google Maps integration | WARNING | Google Maps and tracking UI are implemented, but a full moving two-device scenario was not available. The API key must be restricted by Android package and signing certificate. |

Additional release configuration warnings:

- Android package/namespace remains `com.example.esec_bus`.
- Release builds use the debug signing configuration.
- Android manifest permits cleartext traffic.
- Android application label remains `esec_bus`.
- `firebase.json` refers to `lib/firebase_options.dart`, while the application
  uses `lib/core/firebase/firebase_options.dart`.

## 2. Admin module validation

| Feature | Status | Result |
|---|---|---|
| Admin login | PASS | Both admin Auth users are enabled, role claims match, and custom-token sessions were verified. Password UI was not exercised because existing admin passwords were preserved. |
| Dashboard | PASS | Real bus stream and operational cards are present. The displayed Operations count is hard-coded and therefore not a production metric. |
| Bus management | WARNING | Add/edit/delete paths exist. Destructive production CRUD was not executed. |
| Driver management | FAIL | No standalone driver CRUD management screen exists. |
| Student management | FAIL | Bulk student generation exists; full list/edit/delete management is absent. |
| Route management | FAIL | No complete route CRUD/geometry management experience exists. |
| Assignment management | WARNING | Driver/bus assignment paths exist, but production contains missing and mismatched assignments. |
| Live tracking dashboard | FAIL | Admin receives status cards, not a complete live tracking map/dashboard. |
| SOS monitoring | FAIL | No Admin SOS monitoring workflow was found. |
| User creation | WARNING | Callable Cloud Function client code exists; deployed function state could not be verified. |
| User editing | FAIL | Full Auth + Firestore user editing is absent. |
| User deletion | FAIL | Full Auth + Firestore user deletion is absent. |
| Firebase synchronization | WARNING | Projection/synchronization functions exist in source; route projection inconsistency suggests the deployment or historical data is not fully synchronized. |

No production user/bus was created, edited, or deleted during this audit.

## 3. Driver module validation

| Feature | Status | Result |
|---|---|---|
| Driver login | PASS | `DRV_BUS_01` signed in successfully on the release APK. All 45 driver password sign-ins passed the Auth audit. |
| Assigned bus | PASS | BUS_01 and vehicle TN 56 D 1748 loaded on-device. |
| Assigned route | PASS | Route `01 - KUNDADAM` loaded for BUS_01. Fleet-wide assignments still fail Section 9. |
| GPS permission | PASS | Fine location permission and Android location services were verified. |
| Start Trip | PASS | On-device Start Trip became Running and wrote a valid real GPS point. The first-stop distance is advisory rather than blocking. |
| Stop Trip | PASS | Firestore became stopped/inactive and the foreground background service terminated after the audit fix. |
| Continuous GPS | WARNING | Native stream, adaptive 8-second policy, and 30-second service heartbeat were verified. The device was stationary; physical movement was not performed. |
| Live Firestore update | PASS | BUS_01 received a real `currentPoint`, Running state, ByZra decision, and heartbeat. Stationary coordinates were correctly suppressed by the 20 m distance filter while heartbeat advanced. |
| SOS | NOT EXECUTED | A real emergency event was not sent to production. The code path obtains current GPS and requests emergency synchronization. |
| Background tracking | PASS | Android reported a location foreground service during the trip. |
| Session recovery | WARNING | Firebase session restoration exists, but Driver Home intentionally clears a stale same-driver active trip rather than resuming it. |
| Logout | WARNING | The logout path stops an active trip first and signs out; it was inspected but not repeated after the final lifecycle run. |

### Lifecycle defect fixed during audit

Before the fix, Stop Trip updated Firestore but left
`flutter_background_service.BackgroundService` in foreground mode. The
`stopTracking` handler cancelled streams and timers but did not call
`stopSelf()`. Only an unused separate `stopService` command did.

The `stopTracking` handler now terminates the service after cleanup and also
handles the already-stopped path. Final device evidence:

- `runningBeforeStop=true`
- `stoppedAfterTap=true`
- `backgroundServicePresent=false`
- `backgroundServiceForeground=false`
- Firestore: `status=stopped`, `isActive=false`, heartbeat removed
- Android fused and GPS provider requests: `OFF`

## 4. Student module validation

| Feature | Status | Result |
|---|---|---|
| Student login | PASS | Twelve distributed student password samples passed; all student Auth accounts are enabled and role-aligned. |
| Assigned bus | FAIL | All 271 student documents lack `assignment.busId`. |
| Live tracking | WARNING | A single canonical `buses/{busId}` listener is implemented. No second signed-in student device was available during the moving-driver test. |
| ETA | PASS (logic) | Tests cover real speed, average-speed fallback, Arrived, and stopped states. ETA is straight-line rather than road-network ETA. |
| Distance | PASS (logic) | Tests cover metre/kilometre formatting and continuous recalculation. |
| Bus status | PASS (logic) | Running, stopped, delayed, lost signal, approaching, arriving, and arrived states are derived from live data. |
| Route display | WARNING | Polyline behavior exists, but most production routes lack valid geometry. |
| Auto refresh | PASS | Firestore snapshot stream is used; no polling or duplicate listener was found. |
| Google Maps | WARNING | Implemented and buildable; full moving-device validation was unavailable. |
| Bus marker | PASS (logic) | Marker interpolation and heading rotation are implemented. |
| Route polyline | PASS (logic) | Remaining route is used when available; otherwise a bus-to-student geodesic line is used. |
| Camera behavior | PASS (logic) | Bounds/follow behavior and temporary pause after manual panning are implemented. |
| GPS freshness | PASS (logic) | Freshness updates are timer-driven and tested through tracking-presence logic. |

Student tracking starts its own high-accuracy location stream while the
tracking page is open. This is functionally valid but should be included in a
controlled battery test.

## 5. ByZra intelligence validation

Analytics was excluded from functional scoring as requested. Learning was
ignored.

| Module | Classification | Initialized / called | Produces output | Influences runtime | Production data notes |
|---|---|---|---|---|---|
| Network Intelligence | REAL RUNTIME | Yes / every GPS sample | Quality, latency, loss, stability | Yes | Uses a real socket probe. A probe per GPS sample may add latency and power cost. |
| Adaptive Synchronization | REAL RUNTIME | Yes / every sample | Dynamic interval and due state | Yes | Uses network and battery state. |
| Packet Optimization | WARNING | Yes / every sample | Compact payload and estimated bytes | No meaningful transport effect | The compact payload is measured in telemetry but the normal Firestore map is written. |
| Motion Intelligence | REAL RUNTIME | Yes / every sample | Movement state, speed/distance interpretation | Yes | Uses device GPS samples. |
| Reliable Delivery | REAL RUNTIME | Yes / write failures | Retry/backoff/queue decisions | Yes | Failure path is unit-tested; forced production failure was not executed. |
| Offline Queue | REAL RUNTIME | Yes | Persistent queue and queue size | Yes | SharedPreferences-backed. Real offline end-to-end was not executed. |
| Battery Optimization | REAL RUNTIME | Yes | Mode and native GPS policy | Yes | Native battery and power-saver data select accuracy, interval, and distance filter. |
| Emergency Communication | WARNING | Yes / on emergency | Emergency evaluation | Partially | The module return value is ignored; the central engine acts on the raw emergency flag. |
| Predictive Tracking | WARNING | Yes | Prediction/confidence telemetry | No | ByZra prediction is not used for Firestore location writes or central decisions. Student UI has a separate brief-gap predictor. |
| Route Awareness | WARNING | Yes | Route status/progress | No | Output is telemetry-only. BUS_01 reported `routeStatus=unavailable` despite embedded route points, and fleet route data is incomplete. |
| Smart Geofencing | WARNING | Yes when route is valid | Geofence events | No | Telemetry-only and frequently unavailable because route geometry is invalid/missing. |
| Security Module | FAIL | Yes / each packet | Local validation/signature metadata | Locally only | Uses the Firebase token but creates a local trust context per packet, signs with non-cryptographic FNV-1a64, and has no server-side signature verification. Firebase Auth and Firestore Rules provide the real security boundary. |
| Health Monitor | REAL RUNTIME | Yes / every sample | Score, severity, issues | Yes | Uses real network/GPS/runtime checks. |
| Multi Transport Validation | REAL RUNTIME | Yes / every sample | Validation result | Yes | Invalid/stale/unrealistic samples can be rejected. |
| Central Decision Engine | REAL RUNTIME | Yes / every request | Send/wait/queue/retry/drop/emergency decision | Yes | Network, battery, motion, queue, retry, health, transport, emergency, and schedule are wired. Route/geofence/prediction outputs are not inputs to the final context. |
| Analytics | EXCLUDED | Initialized and called | Event counts | Not scored | Excluded by task scope. |

No mock GPS or simulated network value is used in the production tracking
pipeline. Unit tests use controlled test values intentionally.

## 6. ByZra developer dashboard

| Metric | Status | Classification |
|---|---|---|
| Network quality | PASS | Real runtime, derived from real probes |
| GPS accuracy | PASS | Real device GPS |
| Battery status | WARNING | Real level/mode; preview hard-codes `isCharging=false` because charging state is not published |
| Sync interval | PASS | Real runtime |
| Current decision | PASS | Real runtime |
| Retry count | PASS | Real runtime |
| Queue size | PASS | Real persistent queue |
| Route status | WARNING | Real calculation, but unavailable for incomplete/invalid routes |
| Geofence events | WARNING | Real calculation, frequently unavailable with bad route geometry |
| Health score | PASS | Real derived runtime value |
| Prediction status | MISSING | Runtime publishes it; dashboard does not display it |
| Runtime events | PASS | Real recent events |
| Active modules | WARNING | List is static and can claim modules are active when route/emergency conditions are unavailable |
| Last update time | MISSING | Runtime timestamp exists; dashboard does not show it |
| Transport validation | MISSING | Module runs, but dashboard does not expose its result |

Other dashboard accuracy findings:

- Movement distance is displayed as zero in the preview mapping.
- All metrics are labeled `live`, including derived metrics.
- Dashboard access is intentionally guarded by `kDebugMode`, so it is absent
  from release builds.

## 7. Visual debugging

**WARNING**

The dashboard already has realtime cards, indicators, status chips, color
coding, connection quality, health, battery, GPS, queue, and decision/event
views. Prediction, last-update, transport validation, and accurate
charging/movement-distance presentation are missing.

No UI was changed during this production validation because the missing
visuals do not justify redesigning the application in a final audit.

## 8. Graph representation

**MISSING**

No production graphs were found for:

- network quality
- GPS accuracy
- battery trend
- sync interval
- movement speed
- health score
- prediction confidence
- retry count
- offline queue size
- decision frequency over time

The runtime document stores the latest snapshot by overwriting
`smartsync_runtime/{busId}`. Historical graphs cannot be reconstructed from
Firestore under the existing schema. Real in-memory session graphs could be
added later without schema changes, but that would be feature work and was
not introduced during this audit.

## 9. Firestore validation

### Production counts

| Collection | Documents |
|---|---:|
| users | 318 |
| admins | 2 |
| drivers | 45 |
| students | 271 |
| buses | 37 |
| routes | 37 |
| tracking | 37 |
| smartsync_runtime | 2 |
| trips | 0 |
| emergencies | 0 |

### Authentication and user projections

- 318/318 Firestore users have Firebase Auth users.
- Zero Auth users are disabled.
- Zero role-claim mismatches were found.
- Zero driver/student projection gaps were found.
- 45/45 driver convention-password sign-ins passed.
- 12/12 distributed student convention-password sign-ins passed.
- Both admin custom-token sessions passed.

Detailed evidence:
`functions/reports/final-audit-auth-signin-report.json`.

### Relationship and data failures

The read-only transport verifier returned **129 findings**:

- All 271 students are missing `assignment.busId`.
- Unassigned buses: BUS_04, BUS_10, BUS_36, BUS_37.
- Unassigned drivers: `dr01`, DRV_BUS_20, DRV_BUS_43 through DRV_BUS_48.
- Canonical/projection assignment mismatch for DRV_BUS_04, DRV_BUS_10,
  DRV_BUS_36, and DRV_BUS_37.
- Route geometry missing for BUS_03 and BUS_06.
- The BUS_01 route projection is stale/inconsistent with the embedded bus
  route.
- Most remaining routes have invalid/non-production first-stop coordinates or
  start-point/name inconsistencies.

The application correctly treats `buses/{busId}` as the canonical bus, route,
and tracking source. `routes/{busId}` and `tracking/{busId}` are Cloud
Function projections. These collections are intentional denormalizations, but
their current content is inconsistent and therefore fails production
validation.

## 10. Live GPS validation

| Step | Status | Evidence |
|---|---|---|
| Driver login | PASS | Real release APK login |
| Start Trip | PASS | UI Running, Firestore active/running |
| GPS update | PASS | Valid device coordinate, accuracy, speed, heading, captured time |
| ByZra runtime | PASS | Real runtime document, `sendNow`, queue 0 |
| Firestore update | PASS | Canonical embedded tracking write plus service heartbeat |
| Student map update | NOT EXECUTED | No second signed-in physical device and all students lack assignments |
| ETA update | PASS (automated logic only) | Unit tests pass; no moving two-device run |
| Distance update | PASS (automated logic only) | Unit tests pass; no moving two-device run |
| Physical movement | NOT EXECUTED | Device remained stationary |
| Stop Trip | PASS | Firestore inactive/stopped, heartbeat removed |
| Tracking stops | PASS | Foreground background service absent and Android GPS/fused provider requests OFF |

The core real-data pipeline is verified through Firestore. The full
Driver-moving-device → Student-map-moving-marker scenario remains a required
internal beta test.

## 11. Performance and quality validation

| Check | Status | Result |
|---|---|---|
| Flutter Analyze | PASS | No issues found |
| Unit/widget tests | PASS | 164 tests passed |
| Coverage | WARNING | 1,350/2,125 instrumented lines = 63.53% |
| Integration tests | FAIL | No `integration_test` directory or automated end-to-end suite |
| Node lint | PASS | Functions lint passed |
| Release APK build | PASS | 52,969,656 bytes |
| Release AAB build | PASS | 46,473,353 bytes |
| Release signing | FAIL | AAB certificate is `C=US, O=Android, CN=Android Debug` |
| Memory | WARNING | Driver dashboard PSS 175,682 KB; no agreed budget or comparative baseline |
| Frame drops | NOT MEASURABLE | OEM `gfxinfo` reported zero Flutter frames after reset; no valid conclusion can be drawn |
| Firestore reads/writes | WARNING | No production cost instrumentation. ByZra reads embedded route per GPS sample and writes runtime plus tracking when decisions send; heartbeat writes every 30 seconds while active |
| Network calls | WARNING | A real TCP network probe can run for every GPS sample and can wait up to three seconds |
| Background tracking | PASS | Real foreground service during trip; service terminates after Stop Trip |
| Battery usage | WARNING | Adaptive native GPS policy is active, but no controlled 15–30 minute drain test was run |

The fresh AAB is available at
`build/app/outputs/bundle/release/app-release.aab`, but it must not be
distributed as the production artifact until release signing is corrected.

## 12. Final scorecard

| Area | Result |
|---|---|
| Architecture | WARNING |
| Admin module | FAIL |
| Driver module | PASS with warnings |
| Student module | FAIL because assignments and two-device E2E are incomplete |
| Network Intelligence | REAL RUNTIME |
| Packet Optimization | WARNING / telemetry-only effect |
| Motion Intelligence | REAL RUNTIME |
| Health Monitor | REAL RUNTIME |
| Prediction | WARNING / telemetry-only in ByZra |
| Developer dashboard | WARNING |
| Graphs | MISSING |
| Tracking pipeline | PASS through Firestore |
| Student moving map | NOT EXECUTED |
| ETA | PASS logic / unverified moving E2E |
| Firestore | FAIL |
| Firebase Authentication | PASS |
| Security rules | WARNING |
| ByZra Security Module | FAIL |
| Release signing | FAIL |
| Automated tests | PASS |
| Integration tests | MISSING |

## 13. Final summary

### Critical issues

1. Replace debug signing with a protected production upload/release keystore.
2. Replace `com.example.esec_bus` with the approved production application ID
   before Play distribution and regenerate Firebase Android configuration.
3. Repair all Driver → Bus → Route relationships and assign every student to
   an appropriate bus.
4. Replace invalid/missing route and first-stop geometry, then resynchronize
   `routes` and `tracking` projections.
5. Add and pass an automated integration suite plus a two-device physical
   Driver/Student movement test.
6. Decide whether incomplete Admin driver/student/route/SOS workflows are in
   the v1.0 release scope; if yes, implement and validate them.
7. Do not treat the current ByZra local signature as a server-verified
   security mechanism.

### Minor and operational issues

- Restrict the Maps API key to the final Android package and production
  signing certificate.
- Disable cleartext traffic unless a documented endpoint requires it.
- Add Crashlytics or an equivalent production crash/error pipeline.
- Add Firestore Rules emulator tests.
- Publish prediction, transport validation, charging state, and last-update
  metrics accurately in the debug dashboard.
- Add real in-memory dashboard trend graphs if required without changing the
  Firestore schema.
- Measure battery drain, network traffic, frame pacing, and Firestore cost
  during a representative route.

### Validation commands and artifacts

- `flutter analyze` — PASS
- `flutter test` — 164/164 PASS
- `flutter test --coverage` — PASS, 63.53% line coverage
- `npm run lint` — PASS
- `npm run verify-transport` — FAIL, 129 findings
- Release APK installed and exercised on a real Android 13 device
- Fresh AAB:
  `build/app/outputs/bundle/release/app-release.aab`
- Auth report:
  `functions/reports/final-audit-auth-signin-report.json`

### Changes made during this audit

Application code changed only in
`lib/core/services/background_location_service.dart`:

- Stop Trip now calls `service.stopSelf()` after cancelling timers/location
  subscriptions and updating Firestore.
- The already-stopped command path also terminates the service.

No UI, authentication flow, Firestore schema, Firebase user, route, bus,
student assignment, or production collection was created/deleted by this
audit. BUS_01 was temporarily started and stopped for the real-device
validation and was left in the correct stopped/inactive state.
