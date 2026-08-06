"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const EXPECTED_PROJECT_ID = "esec-bus-01";
const AUTH_DOMAIN = "auth.busbuddy.bytbeta.com";
const TARGET_ROLES = new Set(["driver", "student"]);
const APPLY_FLAG = "--apply";
const VERIFY_SIGN_INS_FLAG = "--verify-sign-ins";
const VERIFY_ONLY_FLAG = "--verify-only";
const DEFAULT_REPORT = path.resolve(
    __dirname,
    "..",
    "reports",
    "auth-reconciliation-report.json",
);

admin.initializeApp();
const db = admin.firestore();
db.settings({preferRest: true});
const auth = admin.auth();

function asMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value : {};
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim() !== "" ?
    value.trim() : null;
}

function valueAfter(args, name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : null;
}

function configuredProjectId() {
  const direct = admin.app().options.projectId ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT;
  if (direct) return direct;

  const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialPath) return undefined;
  const credential = JSON.parse(fs.readFileSync(credentialPath, "utf8"));
  return nonEmptyString(credential.project_id);
}

function emailFor(userId) {
  return `${userId.toLowerCase()}@${AUTH_DOMAIN}`;
}

function driverConventionPassword(userId) {
  const match = userId.match(/(\d+)$/);
  if (!match) return null;
  const routeNumber = String(Number.parseInt(match[1], 10)).padStart(2, "0");
  return `drv_${routeNumber}`;
}

function passwordFromRecord(...records) {
  for (const record of records) {
    const data = asMap(record);
    const authentication = asMap(data.authentication);
    const candidates = [
      data.password,
      data.defaultPassword,
      authentication.password,
      authentication.defaultPassword,
    ];
    const password = candidates.map(nonEmptyString).find(Boolean);
    if (password) return password;
  }
  return null;
}

function hasAssignment(value) {
  return Boolean(nonEmptyString(asMap(value).busId));
}

function projectionAssignment(data) {
  const assignment = asMap(data.assignment);
  if (hasAssignment(assignment)) return assignment;
  const busId = nonEmptyString(data.busId);
  if (!busId) return null;
  return {
    busId,
    ...(nonEmptyString(data.routeId) ? {routeId: data.routeId.trim()} : {}),
    ...(nonEmptyString(data.routeNo) ? {routeNo: data.routeNo.trim()} : {}),
  };
}

async function listAuthUsers() {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

async function loadState() {
  const [users, drivers, students, settings, authUsers] = await Promise.all([
    db.collection("users").get(),
    db.collection("drivers").get(),
    db.collection("students").get(),
    db.collection("app_settings").doc("student_config").get(),
    listAuthUsers(),
  ]);
  return {
    users,
    drivers,
    students,
    settings,
    authUsers,
    userMap: new Map(users.docs.map((doc) => [doc.id, doc])),
    driverMap: new Map(drivers.docs.map((doc) => [doc.id, doc])),
    studentMap: new Map(students.docs.map((doc) => [doc.id, doc])),
    authMap: new Map(authUsers.map((user) => [user.uid, user])),
    authEmailMap: new Map(authUsers
        .filter((user) => nonEmptyString(user.email))
        .map((user) => [user.email.toLowerCase(), user])),
  };
}

function buildAccounts(state) {
  const ids = new Set();
  for (const doc of state.users.docs) {
    if (TARGET_ROLES.has(doc.data().role)) ids.add(doc.id);
  }
  state.drivers.docs.forEach((doc) => ids.add(doc.id));
  state.students.docs.forEach((doc) => ids.add(doc.id));

  const studentDefault = nonEmptyString(
      asMap(state.settings.data()).defaultPassword,
  ) || "student123";

  return [...ids].sort().map((userId) => {
    const canonicalDoc = state.userMap.get(userId);
    const driverDoc = state.driverMap.get(userId);
    const studentDoc = state.studentMap.get(userId);
    const canonical = canonicalDoc ? canonicalDoc.data() : {};
    const roles = new Set([
      TARGET_ROLES.has(canonical.role) ? canonical.role : null,
      driverDoc ? "driver" : null,
      studentDoc ? "student" : null,
    ].filter(Boolean));
    const issues = [];
    if (roles.size !== 1) {
      issues.push(`role-conflict:${[...roles].join(",") || "missing"}`);
    }
    if (canonicalDoc && !TARGET_ROLES.has(canonical.role)) {
      issues.push(`invalid-canonical-role:${canonical.role || "missing"}`);
    }
    const role = roles.size === 1 ? [...roles][0] : null;
    const projectionDoc = role === "driver" ? driverDoc : studentDoc;
    const projection = projectionDoc ? projectionDoc.data() : {};
    const recordPassword = passwordFromRecord(canonical, projection);
    const password = recordPassword ||
      (role === "driver" ? driverConventionPassword(userId) : studentDefault);
    const passwordSource = recordPassword ? "firestore-record" :
      role === "driver" ? "driver-convention" : "student-default";
    if (!password || password.length < 6) {
      issues.push("password-unavailable-or-too-short");
    }

    const canonicalAssignment = asMap(canonical.assignment);
    const assignment = hasAssignment(canonicalAssignment) ?
      canonicalAssignment : projectionAssignment(projection);
    if (role === "driver" && !hasAssignment(assignment)) {
      issues.push("driver-assignment-missing");
    }

    const expectedEmail = emailFor(userId);
    const authUser = state.authMap.get(userId);
    const emailOwner = state.authEmailMap.get(expectedEmail);
    if (emailOwner && emailOwner.uid !== userId) {
      issues.push(`email-owned-by-other-uid:${emailOwner.uid}`);
    }
    const actions = [];
    if (!authUser) {
      actions.push("create-auth");
    } else {
      actions.push("reset-password");
      if (authUser.disabled) actions.push("enable-auth");
      if ((authUser.email || "").toLowerCase() !== expectedEmail) {
        actions.push("correct-auth-email");
      }
      if (asMap(authUser.customClaims).role !== role) {
        actions.push("correct-role-claim");
      }
    }
    if (!canonicalDoc) actions.push("create-canonical-user");
    if (canonicalDoc && canonical.active !== true) {
      actions.push("enable-canonical-user");
    }
    if (!projectionDoc) actions.push("create-role-projection");
    if (projectionDoc && projection.active !== true) {
      actions.push("enable-role-projection");
    }
    if (role === "driver" &&
        !hasAssignment(canonicalAssignment) &&
        hasAssignment(assignment)) {
      actions.push("repair-canonical-assignment");
    }

    return {
      userId,
      role,
      password,
      passwordSource,
      expectedEmail,
      canonicalDoc,
      canonical,
      projectionDoc,
      projection,
      assignment,
      authUser,
      issues,
      actions,
    };
  });
}

function publicAccount(account, appliedStatus = null) {
  return {
    userId: account.userId,
    role: account.role,
    canonicalUserExists: Boolean(account.canonicalDoc),
    roleProjectionExists: Boolean(account.projectionDoc),
    authExists: Boolean(account.authUser),
    authEnabled: account.authUser ? !account.authUser.disabled : false,
    emailMatches: account.authUser ?
      (account.authUser.email || "").toLowerCase() === account.expectedEmail :
      false,
    roleClaimMatches: account.authUser ?
      asMap(account.authUser.customClaims).role === account.role : false,
    firestoreRoleMatches: account.canonicalDoc ?
      account.canonical.role === account.role : false,
    firestoreActive: account.canonical.active === true,
    projectionActive: account.projection.active === true,
    assignmentExists: account.role === "driver" ?
      hasAssignment(account.assignment) : null,
    passwordSource: account.passwordSource,
    actions: account.actions,
    issues: account.issues,
    ...(appliedStatus ? {appliedStatus} : {}),
  };
}

function profileFor(account) {
  return {
    ...asMap(account.projection.profile),
    ...asMap(account.canonical.profile),
  };
}

async function applyAccount(account) {
  if (account.issues.some((issue) => !issue.startsWith(
      "driver-assignment-missing",
  ))) {
    throw new Error(account.issues.join(";"));
  }

  let authUser = account.authUser;
  let created = false;
  let enabled = false;
  if (!authUser) {
    authUser = await auth.createUser({
      uid: account.userId,
      email: account.expectedEmail,
      password: account.password,
      disabled: false,
    });
    created = true;
  } else {
    enabled = authUser.disabled;
    authUser = await auth.updateUser(account.userId, {
      email: account.expectedEmail,
      password: account.password,
      disabled: false,
    });
  }
  await auth.setCustomUserClaims(account.userId, {
    ...(authUser.customClaims || {}),
    role: account.role,
  });

  const userRef = db.collection("users").doc(account.userId);
  const projectionRef = db
      .collection(`${account.role}s`)
      .doc(account.userId);
  const profile = profileFor(account);
  const batch = db.batch();
  batch.set(userRef, {
    schemaVersion: account.canonical.schemaVersion || 3,
    userId: account.userId,
    role: account.role,
    active: true,
    profile,
    authentication: {
      ...asMap(account.canonical.authentication),
      provider: "firebase-password",
      status: "enabled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    ...(hasAssignment(account.assignment) ? {
      assignment: account.assignment,
    } : {}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(!account.canonicalDoc ? {
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    } : {}),
  }, {merge: true});
  batch.set(projectionRef, {
    schemaVersion: account.projection.schemaVersion ||
      account.canonical.schemaVersion || 3,
    userId: account.userId,
    role: account.role,
    active: true,
    profile,
    ...(hasAssignment(account.assignment) ? {
      assignment: account.assignment,
    } : {}),
    userRef,
    projectionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
  return {created, enabled};
}

async function runPool(items, concurrency, handler) {
  let index = 0;
  const results = new Array(items.length);
  async function worker() {
    while (index < items.length) {
      const current = index++;
      try {
        results[current] = {
          ok: true,
          value: await handler(items[current]),
        };
      } catch (error) {
        results[current] = {ok: false, error};
      }
    }
  }
  await Promise.all(Array.from({length: concurrency}, worker));
  return results;
}

function firebaseApiKey() {
  const googleServicesPath = path.resolve(
      __dirname,
      "..",
      "..",
      "android",
      "app",
      "google-services.json",
  );
  const config = JSON.parse(fs.readFileSync(googleServicesPath, "utf8"));
  const client = Array.isArray(config.client) ? config.client[0] : null;
  const apiKeys = client && Array.isArray(client.api_key) ?
    client.api_key : [];
  return apiKeys[0] && apiKeys[0].current_key;
}

async function firebaseSignInRequest(endpoint, apiKey, body) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const response = await fetch(
          "https://identitytoolkit.googleapis.com/v1/accounts:" +
          `${endpoint}?key=${apiKey}`,
          {
            method: "POST",
            headers: {"content-type": "application/json"},
            body: JSON.stringify(body),
          },
      );
      const payload = await response.json();
      if (response.ok) return payload;
      const message = asMap(payload.error).message ||
        `HTTP ${response.status}`;
      if (response.status < 500 && response.status !== 429) {
        throw new Error(message);
      }
      lastError = new Error(message);
    } catch (error) {
      lastError = error;
    }
    if (attempt < 3) {
      await new Promise((resolve) => setTimeout(resolve, attempt * 600));
    }
  }
  throw lastError || new Error("Firebase sign-in request failed.");
}

async function passwordSignIn(account, apiKey) {
  const payload = await firebaseSignInRequest(
      "signInWithPassword",
      apiKey,
      {
        email: account.expectedEmail,
        password: account.password,
        returnSecureToken: true,
      },
  );
  if (payload.localId !== account.userId) {
    throw new Error(`UID mismatch: ${payload.localId}`);
  }
  return true;
}

async function customTokenSignIn(userId, apiKey) {
  const customToken = await auth.createCustomToken(userId);
  const payload = await firebaseSignInRequest(
      "signInWithCustomToken",
      apiKey,
      {
        token: customToken,
        returnSecureToken: true,
      },
  );
  const idToken = nonEmptyString(payload.idToken);
  if (!idToken) throw new Error("Firebase ID token is missing.");
  const segments = idToken.split(".");
  if (segments.length !== 3) throw new Error("Firebase ID token is invalid.");
  const claims = JSON.parse(
      Buffer.from(segments[1], "base64url").toString("utf8"),
  );
  const authenticatedUserId = claims.user_id || claims.sub;
  if (authenticatedUserId !== userId) {
    throw new Error(`UID mismatch: ${authenticatedUserId}`);
  }
  return true;
}

function studentSamples(accounts, count = 12) {
  const students = accounts.filter((account) =>
    account.role === "student" && account.issues.length === 0,
  );
  if (students.length <= count) return students;
  const samples = new Map();
  for (let index = 0; index < count; index++) {
    const sampleIndex = Math.round(index * (students.length - 1) / (count - 1));
    samples.set(students[sampleIndex].userId, students[sampleIndex]);
  }
  return [...samples.values()];
}

async function verifySignIns(accounts, state) {
  const apiKey = firebaseApiKey();
  if (!apiKey) throw new Error("Firebase Web API key is unavailable.");
  const drivers = accounts.filter((account) =>
    account.role === "driver" &&
    !account.issues.some((issue) =>
      !issue.startsWith("driver-assignment-missing"),
    ),
  );
  const students = studentSamples(accounts);
  const targets = [...drivers, ...students];
  const results = await runPool(targets, 4, (account) =>
    passwordSignIn(account, apiKey),
  );
  const signIns = targets.map((account, index) => ({
    userId: account.userId,
    role: account.role,
    success: results[index].ok,
    ...(results[index].ok ? {} : {
      error: results[index].error.message,
    }),
  }));

  const admins = state.users.docs
      .filter((doc) => doc.data().role === "admin")
      .map((doc) => ({
        userId: doc.id,
        authUser: state.authMap.get(doc.id),
      }));
  const adminIntegrity = admins.map(({userId, authUser}) => ({
    userId,
    authExists: Boolean(authUser),
    enabled: authUser ? !authUser.disabled : false,
    roleClaimMatches: Boolean(authUser) &&
      asMap(authUser.customClaims).role === "admin",
  }));
  const validAdmins = adminIntegrity.filter((adminAccount) =>
    adminAccount.authExists &&
    adminAccount.enabled &&
    adminAccount.roleClaimMatches,
  );
  const adminSignInResults = await runPool(validAdmins, 2, (adminAccount) =>
    customTokenSignIn(adminAccount.userId, apiKey),
  );
  const adminResultMap = new Map(validAdmins.map((adminAccount, index) => [
    adminAccount.userId,
    adminSignInResults[index],
  ]));
  const verifiedAdminIntegrity = adminIntegrity.map((adminAccount) => {
    const result = adminResultMap.get(adminAccount.userId);
    return {
      ...adminAccount,
      sessionVerified: Boolean(result && result.ok),
      verificationMethod: "firebase-custom-token",
      ...(result && !result.ok ? {error: result.error.message} : {}),
    };
  });

  return {
    driversAttempted: drivers.length,
    studentSamplesAttempted: students.length,
    successful: signIns.filter((result) => result.success).length,
    failed: signIns.filter((result) => !result.success).length,
    signIns,
    adminIntegrity: verifiedAdminIntegrity,
    adminFailed: verifiedAdminIntegrity.filter((adminAccount) =>
      !adminAccount.sessionVerified,
    ).length,
  };
}

function verificationIssues(account) {
  const issues = [];
  if (!account.authUser) issues.push("auth-missing");
  if (account.authUser && account.authUser.disabled) {
    issues.push("auth-disabled");
  }
  if (((account.authUser && account.authUser.email) || "").toLowerCase() !==
      account.expectedEmail) {
    issues.push("auth-email-mismatch");
  }
  if (!account.authUser ||
      asMap(account.authUser.customClaims).role !== account.role) {
    issues.push("auth-role-claim-mismatch");
  }
  if (!account.canonicalDoc) issues.push("canonical-user-missing");
  if (account.canonical.role !== account.role) {
    issues.push("firestore-role-mismatch");
  }
  if (account.canonical.active !== true) {
    issues.push("canonical-user-disabled");
  }
  if (!account.projectionDoc) issues.push("role-projection-missing");
  if (account.projection.active !== true) {
    issues.push("role-projection-disabled");
  }
  if (account.role === "driver" && !hasAssignment(account.assignment)) {
    issues.push("driver-assignment-missing");
  }
  return issues;
}

function writeReport(reportPath, report) {
  fs.mkdirSync(path.dirname(reportPath), {recursive: true});
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
}

async function main() {
  const args = process.argv.slice(2);
  const shouldApply = args.includes(APPLY_FLAG);
  const verifyOnly = args.includes(VERIFY_ONLY_FLAG);
  const shouldVerifySignIns = args.includes(VERIFY_SIGN_INS_FLAG);
  if (shouldApply && verifyOnly) {
    throw new Error("Use either --apply or --verify-only, not both.");
  }
  const reportPath = path.resolve(
      valueAfter(args, "--report") || DEFAULT_REPORT,
  );
  const projectId = configuredProjectId();
  if (projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(
        `Refusing project "${projectId || "unknown"}"; ` +
        `expected "${EXPECTED_PROJECT_ID}".`,
    );
  }

  const before = await loadState();
  const accounts = buildAccounts(before);
  const preflightFailures = accounts.filter((account) =>
    account.issues.some((issue) =>
      !issue.startsWith("driver-assignment-missing"),
    ),
  );
  const resultById = new Map();
  let applyResults = [];

  if (shouldApply) {
    applyResults = await runPool(accounts, 8, applyAccount);
    applyResults.forEach((result, index) => {
      resultById.set(accounts[index].userId, result);
    });
  }

  const after = shouldApply ? await loadState() : before;
  const verifiedAccounts = buildAccounts(after);
  const failedVerification = shouldApply ?
    verifiedAccounts.filter((account) =>
      verificationIssues(account).some((issue) =>
        issue !== "driver-assignment-missing",
      ),
    ) : [];
  const signInVerification =
    (shouldApply || verifyOnly) && shouldVerifySignIns ?
    await verifySignIns(verifiedAccounts, after) : null;
  const applyFailures = applyResults
      .map((result, index) => ({result, account: accounts[index]}))
      .filter(({result}) => !result.ok);
  const created = applyResults.filter((result) =>
    result.ok && result.value.created,
  ).length;
  const enabled = applyResults.filter((result) =>
    result.ok && result.value.enabled,
  ).length;
  const updated = applyResults.filter((result) =>
    result.ok && !result.value.created,
  ).length;
  const nonTargetUsers = before.users.docs.filter((doc) =>
    !TARGET_ROLES.has(doc.data().role),
  ).length;

  const report = {
    generatedAt: new Date().toISOString(),
    projectId,
    mode: shouldApply ? "apply" : verifyOnly ? "verify-only" : "dry-run",
    summary: {
      totalFirestoreUsers: before.users.size,
      totalDriverDocuments: before.drivers.size,
      totalStudentDocuments: before.students.size,
      totalFirebaseAuthUsers: before.authUsers.length,
      targetDriverStudentAccounts: accounts.length,
      createdUsers: created,
      updatedUsers: updated,
      skippedUsers: nonTargetUsers,
      disabledUsersEnabled: enabled,
      preflightFailedAccounts: preflightFailures.length,
      applyFailedAccounts: applyFailures.length,
      verificationFailedAccounts: failedVerification.length,
    },
    signInVerification,
    accounts: verifiedAccounts.map((account) => {
      const applyResult = resultById.get(account.userId);
      const appliedStatus = verifyOnly ? "verified" :
        !shouldApply ? "dry-run" :
        applyResult && applyResult.ok ? "applied" :
        `failed:${applyResult && applyResult.error ?
          applyResult.error.message : "not-processed"}`;
      return {
        ...publicAccount(account, appliedStatus),
        verificationIssues: shouldApply ?
          verificationIssues(account) : [],
      };
    }),
  };
  writeReport(reportPath, report);

  console.log(JSON.stringify({
    reportPath,
    ...report.summary,
    signInVerification: signInVerification ? {
      driversAttempted: signInVerification.driversAttempted,
      studentSamplesAttempted: signInVerification.studentSamplesAttempted,
      successful: signInVerification.successful,
      failed: signInVerification.failed,
      adminFailed: signInVerification.adminFailed,
      adminIntegrity: signInVerification.adminIntegrity,
    } : null,
  }, null, 2));

  if (applyFailures.length > 0 ||
      failedVerification.length > 0 ||
      (signInVerification &&
        (signInVerification.failed > 0 ||
          signInVerification.adminFailed > 0))) {
    process.exitCode = 1;
  }
}

main()
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    })
    .finally(() => admin.app().delete());
