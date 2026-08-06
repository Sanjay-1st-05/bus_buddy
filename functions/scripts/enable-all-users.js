const admin = require("firebase-admin");

admin.initializeApp();

const projectionCollections = {
  admin: "admins",
  driver: "drivers",
  student: "students",
};

/**
 * Lists every Firebase Authentication identity.
 * @param {object} auth Auth service.
 * @return {Promise<object[]>} Identities.
 */
async function listAuthUsers(auth) {
  const users = [];
  let pageToken;

  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);

  return users;
}

/**
 * Enables all existing Firebase Auth identities and canonical user profiles.
 * @return {Promise<void>} Completion.
 */
async function main() {
  const auth = admin.auth();
  const db = admin.firestore();
  const [authUsers, userSnapshot] = await Promise.all([
    listAuthUsers(auth),
    db.collection("users").get(),
  ]);
  const profiles = new Map(userSnapshot.docs.map((doc) => [doc.id, doc]));
  const changedUserIds = new Set();
  let enabledAuthUsers = 0;
  let enabledProfiles = 0;

  for (const user of authUsers) {
    if (!user.disabled) continue;
    await auth.updateUser(user.uid, {disabled: false});
    changedUserIds.add(user.uid);
    enabledAuthUsers++;
  }

  for (const profile of userSnapshot.docs) {
    if (profile.data().active === true) continue;
    changedUserIds.add(profile.id);
    enabledProfiles++;
  }

  const writer = db.bulkWriter();
  let enabledProjections = 0;
  for (const userId of changedUserIds) {
    const profile = profiles.get(userId);
    if (!profile) continue;
    const data = profile.data();
    writer.set(profile.ref, {
      active: true,
      authentication: {
        ...(data.authentication || {}),
        status: "enabled",
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const projectionCollection = projectionCollections[data.role];
    if (!projectionCollection) continue;
    const projectionRef = db.collection(projectionCollection).doc(userId);
    const projection = await projectionRef.get();
    if (!projection.exists || projection.data().active === true) continue;
    writer.update(projectionRef, {
      active: true,
      projectionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    enabledProjections++;
  }
  await writer.close();

  const authIds = new Set(authUsers.map((user) => user.uid));
  const missingAuthProfiles = userSnapshot.docs
      .filter((profile) => !authIds.has(profile.id))
      .map((profile) => profile.id);

  console.log("User account enablement completed.");
  console.log(`  Auth identities enabled: ${enabledAuthUsers}`);
  console.log(`  Canonical user profiles enabled: ${enabledProfiles}`);
  console.log(`  Existing role projections enabled: ${enabledProjections}`);
  console.log(
      `  User profiles without Auth identities: ${missingAuthProfiles.length}`,
  );
  if (missingAuthProfiles.length > 0) {
    console.log(`  Missing Auth IDs: ${missingAuthProfiles.join(", ")}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
