# Live tracking pipeline audit

Audit date: 22 July 2026

## Canonical runtime data

The production app has one canonical route and live-location source:

- `users/{uid}` is the authenticated profile and assignment source.
- `buses/{busId}.route` is the route definition consumed by ByZra and the trip-start validator.
- `buses/{busId}.tracking` is the only live bus-location source consumed by the student map.
- `smartsync_runtime/{busId}` is ByZra developer telemetry. It is not a location source.

`routes/{busId}` and `tracking/{busId}` are legacy/read-only Cloud Functions projections of a bus document. The Flutter app does not read either collection for live tracking. Do not delete them until all non-Flutter consumers have been audited and retired.

## Dependency map

| Collection | File | Operation | Purpose |
| --- | --- | --- | --- |
| `users` | `lib/core/services/auth_service.dart` | get | Load signed-in profile. |
| `users` | `lib/features/tracking/services/driver_tracking_service.dart` | get | Validate driver assignment before trip changes. |
| `users`, `buses` | `lib/features/student/services/student_service.dart` | gets, active-buses query stream | Load student assignment/profile and bus details. |
| `buses` | `lib/features/tracking/services/driver_tracking_service.dart` | get, document stream, transaction | Read/validate ownership and atomically start, stop, or reset a trip. |
| `buses` | `lib/features/tracking/services/smartsync_driver_tracking_service.dart` | get, updates | Load embedded route and write canonical `tracking` payloads. |
| `buses` | `lib/features/tracking/presentation/student_track_page.dart` | document snapshot stream | Read `tracking.currentPoint`, animate the Google Maps marker. |
| `smartsync_runtime` | `lib/features/tracking/services/smartsync_driver_tracking_service.dart` | set/merge | Publish ByZra runtime telemetry. |
| `smartsync_runtime` | `lib/smartsync/debug/smartsync_developer_preview_page.dart` | ordered query stream | Admin-only ByZra diagnostics. |
| `users`, `buses` | `lib/features/admin/presentation/{add_bus,admin_home,assign_driver,edit_bus,generate_students}.dart` | reads, queries, batch writes, streams | Admin management and assignments; not in the live location path. |
| `routes`, `tracking` | `functions/index.js` | Cloud Functions document trigger writes | Legacy projections after `buses/{busId}` writes. |
| `buses` | `backend/controllers/{bus,location}.controller.js` | reads/writes | Separate Express API surface; no Flutter caller was found. |
| `buses`, `routes`, `tracking`, `users` | `functions/scripts/migrate-transport-2025-2026.js` | migration reads/writes | One-off data migration only. |

No Flutter runtime code uses `FirestoreCollections.routes` or `FirestoreCollections.tracking`.

## Verified execution path

```text
DriverHome Start Trip
  -> permission/GPS/first-stop validation
  -> DriverTrackingService transaction sets buses/{busId}.tracking active
  -> one foreground SmartSyncDriverTrackingService sync
  -> background service command acknowledgement
  -> Geolocator position stream
  -> SmartSyncDriverTrackingService / ByZra decision engine
  -> buses/{busId}.tracking update
  -> StudentTrackPage buses/{busId}.snapshots()
  -> Google Maps marker animation
```

## Root causes

1. The UI invoked `startTracking` immediately after starting the background isolate. The isolate registered its command listener only after asynchronous Firebase, GPS, and permission setup. `flutter_background_service` uses a broadcast command stream, so the first command could be lost. The service then retained `trackingEnabled = false`, and every GPS callback returned without syncing. This exactly explains a single foreground location update followed by a frozen marker.
2. The background stream used low accuracy and a 40 m filter, while ByZra treats poor GPS accuracy conservatively. That made movement updates unnecessarily sparse even when the command was received.
3. Background initialization and sync exceptions were not surfaced to the caller, making permission, Firebase, and Firestore failures indistinguishable from a frozen marker.

The stale `tracking/{busId}` projection is not the marker root cause: the student UI listens directly to `buses/{busId}`. It remains stale because the legacy projection trigger is not the canonical mobile path.

## Fixes applied

- Registered the background command listeners before any asynchronous initialization.
- Added `trackingReady`, `trackingStarted`, and `trackingError` acknowledgements; the driver trip is rolled back if the background stream cannot start.
- Kept one Geolocator source and one ByZra synchronization service; no duplicate tracking service was added.
- Changed the stream to high accuracy with a 20 m distance filter, while retaining the existing eight-second rate guard and ByZra decision engine as the write authority.
- Reported location-stream and Firestore-sync errors through the background-service channel.
- Deployed Firestore ruleset `projects/esec-bus-01/rulesets/c93a157f-8095-4a53-8a64-28bebf0ce077`. A driver may now create/update only their own `smartsync_runtime/{busId}` document; bus-location permissions were not broadened.

## Live database evidence and release-test blocker

Read-only inspection found `buses/BUS_01.tracking` to be the recent canonical record and `tracking/BUS_01` to be stale. It also found that the first sequenced stop for the configured routes has no verified latitude/longitude. The trip-start validator correctly refuses to start without those values.

`npm run verify-transport` against production reported 117 issues: missing `trackPoints` on BUS_01, BUS_03, and BUS_06; four unassigned buses (BUS_04, BUS_10, BUS_36, BUS_37); eight unassigned canonical drivers (`dr01`, DRV_BUS_20, and DRV_BUS_43 through DRV_BUS_48); and four orphan `drivers` projections (DRV_BUS_04, DRV_BUS_10, DRV_BUS_36, DRV_BUS_37). Most remaining failures are invalid first-stop coordinates and start-point/first-stop-name mismatches in the legacy route projection. Therefore a physical Driver -> Start Trip -> move device production run cannot truthfully be completed until verified coordinates and the intended driver/bus mappings are entered. No assignments or coordinates were invented or migrated by this audit.

## Validation

- `dart analyze lib test`: passed with no issues.
- `flutter test --reporter compact`: passed, 146 tests.
- `npm run lint` in `functions`: passed.
- Production `npm run verify-transport`: executed read-only and correctly failed with the data issues listed above.
- No `integration_test/` directory exists, so there is no automated Flutter integration suite to execute.

The next required external action is to supply/enter verified first-stop coordinates. Then run the physical device scenario: driver login, start at the first stop, move the phone, confirm `buses/{busId}.tracking.currentPoint` changes, confirm the student marker moves, and stop the trip.
