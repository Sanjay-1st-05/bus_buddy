"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const EXPECTED_PROJECT_ID = "esec-bus-01";
const VALID_ROLES = new Set(["admin", "driver", "student"]);
const ROLE_COLLECTIONS = ["admins", "drivers", "students"];
const AUTH_DOMAIN = "auth.busbuddy.bytbeta.com";

admin.initializeApp();
const db = admin.firestore();
db.settings({preferRest: true});
const auth = admin.auth();

function valueAfter(args, name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : null;
}

function asBoolean(value, fallback = true) {
  if (typeof value === "boolean") return value;
  if (typeof value !== "string" || value.trim() === "") return fallback;
  return !["false", "0", "no", "inactive", "disabled"].includes(
      value.trim().toLowerCase(),
  );
}

function nonEmptyFields(source, keys) {
  const result = {};
  for (const key of keys) {
    const value = source[key];
    if (value !== undefined && value !== null && String(value).trim() !== "") {
      result[key] = typeof value === "string" ? value.trim() : value;
    }
  }
  return result;
}

function normalizeUser(input) {
  const rawId = input.userId || input.loginId || input.collegeId ||
    input.rollNo || input.id;
  const userId = String(rawId || "").trim();
  const password = String(input.password || "");
  const role = String(input.role || "student").trim().toLowerCase();

  if (!/^[a-z0-9_-]{3,64}$/i.test(userId)) {
    throw new Error(`Invalid user ID: ${userId || "<empty>"}`);
  }
  if (password.length < 6) {
    throw new Error(`Password is shorter than 6 characters for ${userId}.`);
  }
  if (!VALID_ROLES.has(role)) {
    throw new Error(`Invalid role for ${userId}: ${role}`);
  }

  const flatProfile = nonEmptyFields(input, [
    "name",
    "mobile",
    "year",
    "department",
    "rollNumber",
  ]);
  const profile = input.profile && typeof input.profile === "object" ?
    {...input.profile, ...flatProfile} : flatProfile;
  let assignment = null;
  if (input.assignment && typeof input.assignment === "object") {
    assignment = {...input.assignment};
  } else if (input.busId) {
    assignment = {busId: String(input.busId).trim()};
  }

  return {
    userId,
    password,
    role,
    active: asBoolean(input.active, true),
    profile,
    assignment,
  };
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (character === "\"") {
      if (quoted && text[index + 1] === "\"") {
        field += "\"";
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      row.push(field);
      field = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && text[index + 1] === "\n") index++;
      row.push(field);
      if (row.some((value) => value.trim() !== "")) rows.push(row);
      row = [];
      field = "";
    } else {
      field += character;
    }
  }
  row.push(field);
  if (row.some((value) => value.trim() !== "")) rows.push(row);
  if (rows.length < 2) return [];

  const headers = rows[0].map((header) => header.trim().replace(/^\uFEFF/, ""));
  return rows.slice(1).map((values) => Object.fromEntries(
      headers.map((header, index) => [header, values[index] || ""]),
  ));
}

function readImportFile(filePath) {
  const resolved = path.resolve(filePath);
  const content = fs.readFileSync(resolved, "utf8");
  if (path.extname(resolved).toLowerCase() === ".csv") {
    return parseCsv(content);
  }
  const parsed = JSON.parse(content);
  if (Array.isArray(parsed)) return parsed;
  if (parsed && Array.isArray(parsed.users)) return parsed.users;
  throw new Error("JSON import must be an array or contain a users array.");
}

async function readLegacyFirestoreUsers() {
  const snapshot = await db.collection("users").get();
  return snapshot.docs.filter((doc) => {
    return typeof doc.data().password === "string";
  }).map((doc) => ({...doc.data(), userId: doc.id}));
}

async function readMissingStudentsWithDefaultPassword() {
  const [usersSnapshot, settingSnapshot] = await Promise.all([
    db.collection("users").get(),
    db.collection("app_settings").doc("student_config").get(),
  ]);
  const settingData = settingSnapshot.data();
  const password = settingData && settingData.defaultPassword;
  if (typeof password !== "string" || password.length < 6) {
    throw new Error("A valid student_config defaultPassword is required.");
  }

  const authIds = new Set();
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    page.users.forEach((user) => authIds.add(user.uid));
    pageToken = page.pageToken;
  } while (pageToken);

  return usersSnapshot.docs.filter((doc) => {
    return doc.data().role === "student" && !authIds.has(doc.id);
  }).map((doc) => ({
    ...doc.data(),
    userId: doc.id,
    password,
  }));
}

async function provision(user, preserveExistingPassword = false) {
  const userRef = db.collection("users").doc(user.userId);
  const existingDoc = await userRef.get();
  const existingData = existingDoc.data() || {};
  const email = `${user.userId.toLowerCase()}@${AUTH_DOMAIN}`;
  let authUser;
  let created = false;

  try {
    authUser = await auth.getUser(user.userId);
    const hasPasswordProvider = authUser.providerData.some((provider) => {
      return provider.providerId === "password";
    });
    const update = {
      email,
      disabled: !user.active,
    };
    if (!preserveExistingPassword || !hasPasswordProvider) {
      update.password = user.password;
    }
    authUser = await auth.updateUser(user.userId, update);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    authUser = await auth.createUser({
      uid: user.userId,
      email,
      password: user.password,
      disabled: !user.active,
    });
    created = true;
  }
  await auth.setCustomUserClaims(user.userId, {
    ...(authUser.customClaims || {}),
    role: user.role,
  });

  const profile = {
    ...(existingData.profile || {}),
    ...user.profile,
  };
  const assignment = user.assignment || existingData.assignment || null;
  const payload = {
    schemaVersion: 3,
    userId: user.userId,
    role: user.role,
    active: user.active,
    profile,
    authentication: {
      provider: "firebase-password",
      status: "provisioned",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    password: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (assignment) payload.assignment = assignment;
  if (!existingDoc.exists) {
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  const batch = db.batch();
  batch.set(userRef, payload, {merge: true});
  for (const collectionName of ROLE_COLLECTIONS) {
    const projectionRef = db.collection(collectionName).doc(user.userId);
    if (collectionName !== `${user.role}s`) {
      batch.delete(projectionRef);
      continue;
    }
    batch.set(projectionRef, {
      schemaVersion: 3,
      userId: user.userId,
      role: user.role,
      active: user.active,
      profile,
      assignment: assignment || admin.firestore.FieldValue.delete(),
      userRef,
      projectionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
  return created;
}

async function runPool(items, concurrency, handler) {
  let nextIndex = 0;
  const results = [];
  async function worker() {
    while (nextIndex < items.length) {
      const index = nextIndex++;
      try {
        results[index] = {ok: true, value: await handler(items[index])};
      } catch (error) {
        results[index] = {ok: false, error};
      }
    }
  }
  await Promise.all(Array.from({length: concurrency}, worker));
  return results;
}

async function main() {
  const args = process.argv.slice(2);
  const filePath = valueAfter(args, "--file");
  const fromFirestore = args.includes("--from-firestore");
  const missingStudents = args.includes("--missing-students-from-default");
  const shouldApply = args.includes("--apply");
  const sourceCount = (filePath ? 1 : 0) + (fromFirestore ? 1 : 0) +
    (missingStudents ? 1 : 0);
  if (sourceCount !== 1) {
    throw new Error(
        "Use one import source: --file, --from-firestore, or " +
        "--missing-students-from-default.",
    );
  }

  let rawUsers;
  if (filePath) {
    rawUsers = readImportFile(filePath);
  } else if (fromFirestore) {
    rawUsers = await readLegacyFirestoreUsers();
  } else {
    rawUsers = await readMissingStudentsWithDefaultPassword();
  }
  const users = rawUsers.map(normalizeUser);
  const duplicateIds = users.map((user) => user.userId.toLowerCase())
      .filter((id, index, all) => all.indexOf(id) !== index);
  if (duplicateIds.length > 0) {
    throw new Error(`Duplicate IDs: ${[...new Set(duplicateIds)].join(", ")}`);
  }

  const roleCounts = Object.fromEntries([...VALID_ROLES].map((role) => [
    role,
    users.filter((user) => user.role === role).length,
  ]));
  const weakPasswordCount = users.filter((user) => user.password.length < 8)
      .length;
  console.log(`Validated ${users.length} users.`, roleCounts);
  if (weakPasswordCount > 0) {
    console.warn(
        `${weakPasswordCount} passwords are shorter than 8 characters.`,
    );
  }
  if (!shouldApply) {
    console.log("Dry run only. Add --apply to provision Firebase Auth users.");
    return;
  }
  if (db.projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(
        `Refusing project ${db.projectId}; expected ${EXPECTED_PROJECT_ID}.`,
    );
  }

  const requestedConcurrency = Number(valueAfter(args, "--concurrency") || 10);
  const concurrency = Math.max(1, Math.min(20, requestedConcurrency));
  const results = await runPool(users, concurrency, (user) => {
    return provision(user, fromFirestore || missingStudents);
  });
  const failures = results.map((result, index) => ({result, index}))
      .filter(({result}) => !result.ok);
  const created = results.filter((result) => result.ok && result.value).length;
  console.log(
      `Processed ${results.length - failures.length}; created ${created}; ` +
      `updated ${results.length - failures.length - created}.`,
  );
  if (failures.length > 0) {
    for (const {result, index} of failures) {
      console.error(`${users[index].userId}: ${result.error.message}`);
    }
    throw new Error(`${failures.length} users failed provisioning.`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
