"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const EXPECTED_PROJECT_ID = "esec-bus-01";
const LEGACY_COLLECTIONS = ["bus_master", "bus_routes", "bus_location"];
const CANONICAL_COLLECTIONS = ["buses", "routes", "tracking"];
const APPLY_FLAG = "--apply";
const ACK_FLAG = "--acknowledge-delete-legacy-transport";

admin.initializeApp();
const db = admin.firestore();
db.settings({preferRest: true});

/** Converts Firestore values into portable JSON backup values. */
function encodeValue(value) {
  if (value === null || value === undefined) return value;
  if (value instanceof admin.firestore.Timestamp) {
    return {__type: "timestamp", value: value.toDate().toISOString()};
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return {
      __type: "geopoint",
      latitude: value.latitude,
      longitude: value.longitude,
    };
  }
  if (Buffer.isBuffer(value)) {
    return {__type: "bytes", value: value.toString("base64")};
  }
  if (Array.isArray(value)) return value.map(encodeValue);
  if (typeof value === "object" && typeof value.path === "string" &&
      typeof value.get === "function") {
    return {__type: "reference", path: value.path};
  }
  if (typeof value === "object") {
    return Object.fromEntries(
        Object.entries(value).map(([key, item]) => [key, encodeValue(item)]),
    );
  }
  return value;
}

/** Recursively reads a document and all nested collections. */
async function readDocument(doc) {
  const collectionRefs = await doc.ref.listCollections();
  const childEntries = await Promise.all(collectionRefs.map(async (ref) => [
    ref.id,
    await readCollectionRef(ref),
  ]));
  return {
    id: doc.id,
    path: doc.ref.path,
    data: encodeValue(doc.data()),
    ref: doc.ref,
    subcollections: Object.fromEntries(childEntries),
  };
}

/** Recursively reads all documents in a collection reference. */
async function readCollectionRef(collectionRef) {
  const snapshot = await collectionRef.get();
  return Promise.all(snapshot.docs.map(readDocument));
}

/** Reads a whole top-level collection for validation and backup. */
async function readCollection(collectionName) {
  return readCollectionRef(db.collection(collectionName));
}

function flattenDocuments(documents) {
  const result = [];
  function visit(document) {
    result.push(document);
    for (const children of Object.values(document.subcollections)) {
      for (const child of children) visit(child);
    }
  }
  for (const document of documents) visit(document);
  return result;
}

function backupDocument(document) {
  return {
    id: document.id,
    path: document.path,
    data: document.data,
    subcollections: Object.fromEntries(
        Object.entries(document.subcollections).map(([name, children]) => [
          name,
          children.map(backupDocument),
        ]),
    ),
  };
}

function nestedSummary(legacyData) {
  const summary = {};
  for (const documents of Object.values(legacyData)) {
    for (const document of flattenDocuments(documents)) {
      const segments = document.path.split("/");
      if (segments.length <= 2) continue;
      const collectionName = segments[segments.length - 2];
      const item = summary[collectionName] || {
        documents: 0,
        fields: new Set(),
        samples: [],
      };
      item.documents++;
      Object.keys(document.data).forEach((field) => item.fields.add(field));
      if (item.samples.length < 2) {
        item.samples.push({path: document.path, data: document.data});
      }
      summary[collectionName] = item;
    }
  }
  return Object.fromEntries(Object.entries(summary).map(([name, item]) => [
    name,
    {
      documents: item.documents,
      fields: [...item.fields].sort(),
      samples: item.samples,
    },
  ]));
}

/** Creates a local, checksummed JSON backup before destructive cleanup. */
function createBackup(legacyData) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupDir = path.resolve(process.cwd(), "backups");
  const backupPath = path.join(
      backupDir,
      `legacy-transport-${timestamp}.json`,
  );
  const collections = Object.fromEntries(
      Object.entries(legacyData).map(([name, documents]) => [
        name,
        documents.map(backupDocument),
      ]),
  );
  const payload = JSON.stringify({
    projectId: db.projectId,
    createdAt: new Date().toISOString(),
    collections,
  }, null, 2);

  fs.mkdirSync(backupDir, {recursive: true});
  fs.writeFileSync(backupPath, payload, {encoding: "utf8", flag: "wx"});
  return {
    backupPath,
    sha256: crypto.createHash("sha256").update(payload).digest("hex"),
  };
}

/** Deletes nested documents before their parents in safe batches. */
async function deleteDocuments(legacyData) {
  const documents = Object.values(legacyData).flatMap(flattenDocuments);
  documents.sort((left, right) => {
    return right.path.split("/").length - left.path.split("/").length;
  });
  const refs = documents.map((document) => document.ref);
  for (let offset = 0; offset < refs.length; offset += 400) {
    const batch = db.batch();
    for (const ref of refs.slice(offset, offset + 400)) batch.delete(ref);
    await batch.commit();
  }
  return refs;
}

async function verifyDeleted(refs) {
  for (let offset = 0; offset < refs.length; offset += 300) {
    const snapshots = await db.getAll(...refs.slice(offset, offset + 300));
    if (snapshots.some((snapshot) => snapshot.exists)) return false;
  }
  return true;
}

async function main() {
  const args = new Set(process.argv.slice(2));
  const shouldApply = args.has(APPLY_FLAG);
  if (shouldApply && !args.has(ACK_FLAG)) {
    throw new Error(`Applying cleanup requires ${ACK_FLAG}.`);
  }
  if (db.projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(
        `Refusing project ${db.projectId}; expected ${EXPECTED_PROJECT_ID}.`,
    );
  }

  const [canonicalSnapshots, legacyEntries] = await Promise.all([
    Promise.all(
        CANONICAL_COLLECTIONS.map((name) => db.collection(name).get()),
    ),
    Promise.all(LEGACY_COLLECTIONS.map(async (name) => [
      name,
      await readCollection(name),
    ])),
  ]);
  const canonicalCounts = Object.fromEntries(
      CANONICAL_COLLECTIONS.map((name, index) => [
        name,
        canonicalSnapshots[index].size,
      ]),
  );
  const legacyData = Object.fromEntries(legacyEntries);
  const legacyCounts = Object.fromEntries(
      LEGACY_COLLECTIONS.map((name) => [name, legacyData[name].length]),
  );

  for (const [name, count] of Object.entries(canonicalCounts)) {
    if (count === 0) throw new Error(`Canonical ${name} is empty.`);
  }
  console.log("Canonical counts:", canonicalCounts);
  console.log("Legacy counts:", legacyCounts);
  console.log("Nested legacy data:", JSON.stringify(
      nestedSummary(legacyData),
      null,
      2,
  ));
  if (!shouldApply) {
    console.log(`Dry run only. Use ${APPLY_FLAG} ${ACK_FLAG} to delete.`);
    return;
  }

  const backup = createBackup(legacyData);
  console.log(`Backup: ${backup.backupPath}`);
  console.log(`Backup SHA-256: ${backup.sha256}`);
  const deletedRefs = await deleteDocuments(legacyData);

  const verification = await Promise.all(
      LEGACY_COLLECTIONS.map((name) => db.collection(name).limit(1).get()),
  );
  if (verification.some((snapshot) => !snapshot.empty) ||
      !await verifyDeleted(deletedRefs)) {
    throw new Error("Legacy cleanup verification failed.");
  }
  console.log("Legacy transport collections removed successfully.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
