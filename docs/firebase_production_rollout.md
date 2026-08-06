# Firebase production rollout

The source migration is complete, but these deployment steps must be performed
against the intended Firebase project before releasing the updated client.

## 1. Enable Authentication

In Firebase Console, open Authentication > Sign-in method and enable
Email/Password. BusBuddy maps a college ID to an internal address in the form
`<college-id>@auth.busbuddy.bytbeta.com`; users continue entering only their ID.

## 2. Bootstrap the first administrator

Run with Application Default Credentials or a narrowly scoped service account:

```powershell
cd functions
npm run bootstrap-admin -- <admin-id> <temporary-password>
```

The script creates Firebase Auth identity, admin custom claim, and schema-v3
Firestore profile without storing the password in Firestore.

## 3. Migrate legacy accounts

Back up Firestore first, then run:

```powershell
cd functions
npm run provision-users -- --from-firestore --apply
```

The migration creates or updates Firebase Auth accounts, applies role claims,
updates role projections, and deletes plaintext `password` fields. Existing
Auth passwords are preserved. Accounts with passwords shorter than Firebase's
minimum are rejected and must be reset manually.

To provision existing student profiles that never had individual passwords,
use the configured `student_config.defaultPassword` without printing or
writing it to an import file:

```powershell
npm run provision-users -- --missing-students-from-default
npm run provision-users -- --missing-students-from-default --apply
```

For a CSV or JSON import of any size, validate first and then apply:

```powershell
cd functions
npm run provision-users -- --file data/private/users-import.csv
npm run provision-users -- --file data/private/users-import.csv --apply
```

The CSV columns are shown in `functions/data/users-import.example.csv`. The
script processes accounts concurrently and is safe to rerun. It accepts login
IDs in `userId`, `loginId`, `collegeId`, or `rollNo`; passwords never remain in
Firestore. Keep real import files under `functions/data/private`, which is
ignored by Git.

## 4. Deploy the security boundary

```powershell
firebase use esec-bus-01
firebase deploy --only functions,firestore:rules,firestore:indexes
```

If the Firebase CLI user session is unavailable, a service account with
Firebase Rules permissions can deploy only the rules through:

```powershell
cd functions
npm run deploy-firestore-rules
```

Deploy Functions before distributing the client because admin driver/student
creation now calls authenticated functions in `asia-south1`.

## 5. Verify

- Sign in as admin, driver, and student.
- Confirm ID tokens contain the expected `role` custom claim.
- Confirm non-admin users cannot write user profiles or bus configuration.
- Start one driver trip and confirm `smartsync_runtime/{busId}` updates.
- Open the debug-only admin dashboard and verify live values.
- Send a test SOS and confirm an `emergencies/{eventId}` document is created.
- Confirm no `users` document contains a `password` field.
