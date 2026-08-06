# BusBuddy Firestore transport schema (2025-2026)

## Historical source schema analysis

The deployed `esec-bus-01` project was inspected read-only before migration.
The counts below are the historical source inventory, not the current schema.

| Collection | Documents | Current purpose |
|---|---:|---|
| `users` | 275 | 2 admins, 1 driver, 271 students, 1 missing role |
| `drivers` | 36 | Legacy driver profiles and bus IDs |
| `bus_master` | 38 | Bus number, route summary, driver ID |
| `bus_routes` | 36 | Route endpoints and string stop lists |
| `bus_location` | 38 | Latitude, longitude, status, update time |
| `app_settings` | 1 | Application settings |

The legacy data contains `BUS_5`/`BUS_05` identifier variation and stores
route 06 under legacy document `BUS_05`. The migration matches legacy data by
normalized `routeNo`, then writes corrected canonical IDs. The legacy sources
were preserved until the canonical data was verified, then backed up and
removed after the Flutter app was confirmed to have no legacy reads.

The current Flutter code treats these documents as canonical:

- `users/{userId}` stores authentication profile, role, active state, and an
  optional `assignment.busId`.
- `buses/{busId}` stores the bus, embedded `route`, `assignment.driverId`, and
  embedded live `tracking` data.
- `routes`, `trips`, `smartsync_runtime`, `emergencies`, and `app_settings`
  are defined in the current schema/rules.

Authentication uses Firebase Authentication. Passwords are not added to
Firestore. A login ID is converted to
`<lowercase-id>@auth.busbuddy.bytbeta.com`; the Auth UID remains the exact
Firestore `users` document ID.

## Canonical collection structure

```text
users/{userId}                 canonical account/Auth UID
admins/{userId}                read-only admin projection
drivers/{legacyDriverId}       preserved and extended driver profile
students/{userId}              read-only student projection
buses/{busId}                  canonical bus + embedded route/tracking
routes/{busId}                 route projection
tracking/{busId}               read-only live-tracking projection
```

Cloud Functions synchronize linked user fields and mirror `buses.route` and
`buses.tracking`. Existing legacy driver fields (`driverName`, `mobile`,
`busId`, `active`, `createdAt`) are retained.

### Canonical user/driver

```json
{
  "schemaVersion": 3,
  "userId": "DRV_BUS_01",
  "role": "driver",
  "active": true,
  "profile": {
    "name": "KARUPUSAMY",
    "mobile": "6382335959"
  },
  "assignment": {
    "busId": "BUS_01",
    "routeId": "BUS_01",
    "routeNo": "01",
    "pendingBusDetails": false,
    "assignedAt": "server timestamp"
  },
  "authentication": {
    "status": "password-required"
  }
}
```

The migration reuses deployed IDs such as `DRV_BUS_01`. Route 05 reuses its
deployed unpadded driver ID `DRV_BUS_5`; the corrected canonical bus ID remains
`BUS_05`. Missing Auth identities are created without a Firestore password and
must receive a password through the administrator provisioning flow.

### Canonical bus

```json
{
  "schemaVersion": 3,
  "busId": "BUS_01",
  "active": true,
  "busNo": "TN 56 D 1748",
  "route": {
    "routeId": "BUS_01",
    "routeNo": "01",
    "routeName": "KUNDADAM",
    "startPoint": "SURIYA NALLUR",
    "endPoint": "ESEC",
    "via": "KODUVAI",
    "trackPoints": [
      {"stopId": "BUS_01-0", "name": "SURIYA NALLUR", "sequence": 0}
    ],
    "academicYear": "2025-2026",
    "sourceDocument": "BUS FEES 2025-2026.pdf",
    "sourcePage": 3
  },
  "assignment": {
    "driverId": "DRV_BUS_01",
    "assignedAt": "server timestamp"
  },
  "tracking": {
    "busId": "BUS_01",
    "driverId": "DRV_BUS_01",
    "currentPoint": {"latitude": 0.0, "longitude": 0.0},
    "isActive": false,
    "status": "stopped"
  }
}
```

Existing canonical route points, tracking coordinates, SmartSync data, active
state, and timestamps win over imported values. When canonical data is absent,
legacy route strings are converted to typed points and legacy coordinates are
copied. An active trip blocks any conflicting reassignment.

### Route projection

```json
{
  "schemaVersion": 3,
  "routeId": "BUS_01",
  "routeNo": "01",
  "routeName": "KUNDADAM",
  "startPoint": "SURIYA NALLUR",
  "endPoint": "ESEC",
  "via": "KODUVAI",
  "busId": "BUS_01",
  "driverId": "DRV_BUS_01",
  "assignmentStatus": "assigned",
  "feeSchedule": {
    "academicYear": "2025-2026",
    "frequency": "semester",
    "approximate": true,
    "sourceDocument": "BUS FEES 2025-2026.pdf",
    "sourcePage": 3
  }
}
```

### Tracking projection

```json
{
  "schemaVersion": 3,
  "busId": "BUS_01",
  "driverId": "DRV_BUS_01",
  "currentPoint": {"latitude": 0.0, "longitude": 0.0},
  "isActive": false,
  "status": "stopped",
  "busRef": "reference to buses/BUS_01"
}
```

## Source reconciliation

- PDF: 37 buses/routes.
- Driver roster: 40 drivers.
- Direct matches by route number: 33.
- PDF routes without a roster driver: `04`, `10`, `36`, `37`. New canonical
  buses remain unassigned.
- Roster routes without PDF bus details: `20`, `43`, `44`, `45`, `46`, `47`,
  `48`. Profiles receive `pendingBusDetails: true`; no bus is fabricated.
- 32 roster routes could be compared with deployed driver profiles. The image
  provides newer values: only 19 names and 16 mobile numbers matched exactly.

## Running the migration

From the `functions` directory, validate without Firebase credentials:

```powershell
npm run migrate-transport
```

Apply with the service-account file for the app's `esec-bus-01` project:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\Users\hp\Downloads\esec_bus_01-firebase_com.json"
npm run migrate-transport -- --apply --acknowledge-driver-roster
```

The operation uses merge writes, retries transient failures, reuses deployed
driver IDs, and can be rerun safely. New driver Auth identities are marked
`password-required`; provision a secure password before giving each driver
login access.

## Verifying canonical transport relationships

With application-default or service-account credentials configured, run the
read-only live verifier from the `functions` directory:

```powershell
npm run verify-transport
```

The command reads only the existing `users`, `drivers`, `buses`, `routes`, and
`tracking` collections. It reports reciprocal Driver -> Bus -> Route
assignment mismatches, unassigned or orphaned records, duplicate assignments,
missing projections, and route/start-stop problems. For every bus and route
projection, the first point ordered by `sequence` must have valid non-zero
latitude/longitude values, and `startPoint` must match that point's `name`.

The verifier exits successfully only when no problems are found. It has no
write or `--apply` mode. Use `npm run verify-transport -- --help` to display
the short usage message without connecting to Firebase.

## Legacy cleanup

After validating the canonical collections, the complete legacy trees were
backed up and removed with:

```powershell
cd functions
npm run cleanup-legacy-transport
npm run cleanup-legacy-transport -- --apply --acknowledge-delete-legacy-transport
```

Cleanup is project-guarded, creates a checksummed JSON backup, recursively
includes subcollections, deletes nested documents before parents, and verifies
every deleted document. The removed top-level collections are `bus_master`,
`bus_routes`, and `bus_location`.

## Deployment status

- The migration has been applied to `esec-bus-01` and verified: 37 buses, 37
  routes, 37 tracking projections, and all 33 source-matched assignments.
- The three legacy transport collections have been backed up and removed.
- Existing legacy password accounts were moved to Firebase Authentication;
  plaintext password fields were deleted from Firestore.
- Firestore rules compiled successfully and are deployed without legacy paths.
- Cloud Functions source is ready and lint-clean, but deployment is blocked
  until the Firebase project is upgraded to the Blaze plan. Firebase requires
  that plan to enable Cloud Build and Artifact Registry. Until then, rerun the
  migration after bulk data changes or use Admin SDK provisioning scripts;
  automatic projection/auth triggers are not active.
