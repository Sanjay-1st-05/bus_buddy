const admin = require("firebase-admin");

admin.initializeApp();

/** Migrates Firestore password accounts to Firebase Authentication. */
async function main() {
  const db = admin.firestore();
  const auth = admin.auth();
  const snapshot = await db.collection("users").get();
  let migrated = 0;
  let skipped = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const password = data.password;
    if (typeof password !== "string" || password.length < 6) {
      skipped++;
      continue;
    }

    const uid = doc.id;
    const email = `${uid.toLowerCase()}@auth.busbuddy.bytbeta.com`;
    try {
      await auth.getUser(uid);
      await auth.updateUser(uid, {email, password, disabled: !data.active});
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
      await auth.createUser({
        uid,
        email,
        password,
        disabled: !data.active,
      });
    }

    await auth.setCustomUserClaims(uid, {role: data.role});
    await doc.ref.update({
      schemaVersion: 3,
      password: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    migrated++;
  }

  console.log(`Migrated ${migrated} users; skipped ${skipped}.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
