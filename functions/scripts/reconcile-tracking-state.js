"use strict";

const fs = require("fs");
const admin = require("firebase-admin");

const EXPECTED_PROJECT_ID = "esec-bus-01";
const APPLY_FLAG = "--apply";

admin.initializeApp();
const db = admin.firestore();
db.settings({preferRest: true});

/**
 * Returns a plain object for Firestore map values.
 * @param {*} value Candidate map value.
 * @return {object} A safe map.
 */
function asMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value : {};
}

/**
 * Returns whether a point contains usable, non-zero coordinates.
 * @param {*} value Candidate point.
 * @return {boolean} Whether the point is a real GPS position.
 */
function hasValidCoordinates(value) {
  const point = asMap(value);
  const latitude = point.latitude;
  const longitude = point.longitude;
  if (typeof latitude !== "number" || !Number.isFinite(latitude) ||
      typeof longitude !== "number" || !Number.isFinite(longitude)) {
    return false;
  }
  if (latitude === 0 && longitude === 0) return false;
  return latitude >= -90 && latitude <= 90 &&
    longitude >= -180 && longitude <= 180;
}

/**
 * Identifies legacy running flags that cannot represent a real driver trip.
 * @param {object} bus Bus document data.
 * @param {boolean} hasRuntime Whether a matching ByZra runtime exists.
 * @return {boolean} Whether this state is safe to reset.
 */
function isSyntheticRunningState(bus, hasRuntime) {
  const tracking = asMap(bus.tracking);
  const status = typeof tracking.status === "string" ?
    tracking.status.trim().toLowerCase() : "";
  const isActive = tracking.isActive === true || status === "running";

  return isActive &&
    !hasValidCoordinates(tracking.currentPoint) &&
    !tracking.tripStartedAt &&
    !hasRuntime;
}

/**
 * Resolves the Firebase project without exposing service-account contents.
 * @return {string|undefined} The configured project ID.
 */
function configuredProjectId() {
  const applicationProjectId = admin.app().options.projectId ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT;
  if (applicationProjectId) return applicationProjectId;

  const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialPath) return undefined;
  const credential = JSON.parse(fs.readFileSync(credentialPath, "utf8"));
  return typeof credential.project_id === "string" ?
    credential.project_id : undefined;
}

/** Audits synthetic running flags and optionally resets safe candidates. */
async function main() {
  const projectId = configuredProjectId();
  if (projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(
        `Refusing to run for project "${projectId || "unknown"}"; ` +
        `expected "${EXPECTED_PROJECT_ID}".`,
    );
  }

  const [busesSnapshot, runtimeSnapshot] = await Promise.all([
    db.collection("buses").get(),
    db.collection("smartsync_runtime").get(),
  ]);
  const runtimeBusIds = new Set(runtimeSnapshot.docs.map((doc) => doc.id));
  const candidates = busesSnapshot.docs.filter((doc) =>
    isSyntheticRunningState(doc.data(), runtimeBusIds.has(doc.id)),
  );

  console.log(JSON.stringify({
    mode: process.argv.includes(APPLY_FLAG) ? "apply" : "dry-run",
    projectId,
    busesScanned: busesSnapshot.size,
    runtimeDocuments: runtimeSnapshot.size,
    candidateCount: candidates.length,
    candidates: candidates.map((doc) => doc.id),
  }, null, 2));

  if (!process.argv.includes(APPLY_FLAG) || candidates.length === 0) return;

  const batch = db.batch();
  for (const doc of candidates) {
    batch.update(doc.ref, {
      "tracking.isActive": false,
      "tracking.status": "stopped",
      "tracking.serviceHeartbeatAt": admin.firestore.FieldValue.delete(),
      "tracking.lastUpdatedAt": admin.firestore.FieldValue.serverTimestamp(),
      "tracking.smartSync.engine": "ByZra",
      "tracking.smartSync.decision": "stale_state_recovery",
      "tracking.smartSync.queuedOffline": false,
      "updatedAt": admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log(`Reset ${candidates.length} synthetic running states.`);
}

main()
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    })
    .finally(() => admin.app().delete());
