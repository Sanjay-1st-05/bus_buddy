const admin = require("firebase-admin");

admin.initializeApp();

/** Creates the first Firebase Auth administrator for a deployment. */
async function main() {
  const [userIdArg, password] = process.argv.slice(2);
  const userId = String(userIdArg || "").trim();
  if (!userId || !password || password.length < 8) {
    throw new Error(
        "Usage: node scripts/bootstrap-admin.js <userId> <password>",
    );
  }

  const email = `${userId.toLowerCase()}@auth.busbuddy.bytbeta.com`;
  try {
    await admin.auth().getUser(userId);
    await admin.auth().updateUser(userId, {email, password, disabled: false});
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    await admin.auth().createUser({uid: userId, email, password});
  }

  await admin.auth().setCustomUserClaims(userId, {role: "admin"});
  await admin.firestore().collection("users").doc(userId).set({
    schemaVersion: 3,
    userId,
    role: "admin",
    active: true,
    profile: {name: "Administrator"},
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await admin.firestore().collection("users").doc(userId).update({
    password: admin.firestore.FieldValue.delete(),
  });
  console.log(`Firebase administrator ${userId} is ready.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
