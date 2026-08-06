const {setGlobalOptions} = require("firebase-functions/v2");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({maxInstances: 10, region: "asia-south1"});

const db = admin.firestore();
const auth = admin.auth();
const validRoles = new Set(["admin", "driver", "student"]);
const roleCollections = {
  admin: "admins",
  driver: "drivers",
  student: "students",
};

/**
 * Verifies that a callable request belongs to an administrator.
 * @param {object} request Callable request.
 * @return {void}
 */
function requireAdmin(request) {
  if (!request.auth || request.auth.token.role !== "admin") {
    throw new HttpsError("permission-denied", "Administrator access required.");
  }
}

/**
 * Validates and normalizes account provisioning input.
 * @param {object} input Raw account data.
 * @return {object} Normalized account data.
 */
function normalizeUser(input) {
  if (!input || typeof input !== "object") {
    throw new HttpsError("invalid-argument", "User data is required.");
  }

  const userId = String(input.userId || "").trim();
  const password = String(input.password || "");
  const role = String(input.role || "").trim().toLowerCase();

  if (!/^[a-z0-9_-]{3,64}$/i.test(userId)) {
    throw new HttpsError("invalid-argument", "Invalid user ID.");
  }
  if (password.length < 8) {
    throw new HttpsError(
        "invalid-argument",
        "Password must contain at least 8 characters.",
    );
  }
  if (!validRoles.has(role)) {
    throw new HttpsError("invalid-argument", "Invalid user role.");
  }

  return {
    userId,
    password,
    role,
    profile: input.profile && typeof input.profile === "object" ?
      input.profile : {},
    assignment: input.assignment && typeof input.assignment === "object" ?
      input.assignment : null,
  };
}

/**
 * Creates or updates a Firebase Auth identity and Firestore profile.
 * @param {object} input Raw account data.
 * @return {Promise<object>} Provisioning result.
 */
async function provision(input) {
  const user = normalizeUser(input);
  const email = `${user.userId.toLowerCase()}@auth.busbuddy.bytbeta.com`;
  let created = false;

  try {
    await auth.getUser(user.userId);
    await auth.updateUser(user.userId, {
      email,
      password: user.password,
      disabled: false,
    });
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    await auth.createUser({
      uid: user.userId,
      email,
      password: user.password,
      disabled: false,
    });
    created = true;
  }

  await auth.setCustomUserClaims(user.userId, {role: user.role});

  const payload = {
    schemaVersion: 3,
    userId: user.userId,
    role: user.role,
    active: true,
    profile: user.profile,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (user.assignment) {
    payload.assignment = {
      ...user.assignment,
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
  }
  if (created) {
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await db.collection("users").doc(user.userId).set(payload, {merge: true});
  await db.collection("users").doc(user.userId).update({
    password: admin.firestore.FieldValue.delete(),
  });

  return {userId: user.userId, role: user.role, created};
}

exports.provisionUser = onCall(async (request) => {
  requireAdmin(request);
  return provision(request.data);
});

exports.provisionUsers = onCall(async (request) => {
  requireAdmin(request);
  const users = request.data && request.data.users;
  if (!Array.isArray(users) || users.length === 0 || users.length > 100) {
    throw new HttpsError(
        "invalid-argument",
        "Provide between 1 and 100 users.",
    );
  }

  const results = [];
  for (const user of users) results.push(await provision(user));
  return {
    processed: results.length,
    created: results.filter((result) => result.created).length,
  };
});

exports.migrateLegacyUsers = onCall(async (request) => {
  requireAdmin(request);
  const snapshot = await db.collection("users").limit(100).get();
  const legacyUsers = snapshot.docs.filter((doc) => {
    return typeof doc.data().password === "string";
  });
  const results = [];
  for (const doc of legacyUsers) {
    const data = doc.data();
    results.push(await provision({
      userId: doc.id,
      password: data.password,
      role: data.role,
      profile: data.profile || {},
      assignment: data.assignment || null,
    }));
  }
  return {migrated: results.length, hasMore: snapshot.size === 100};
});

exports.syncUserClaims = onDocumentWritten("users/{userId}", async (event) => {
  const userId = event.params.userId;
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  const projectionWrites = Object.entries(roleCollections).map(
      ([role, collection]) => {
        const projectionRef = db.collection(collection).doc(userId);
        if (!after || after.role !== role) {
          if (role === "driver" && before && before.role === "driver") {
            return projectionRef.set({
              userId: admin.firestore.FieldValue.delete(),
              userRef: admin.firestore.FieldValue.delete(),
              profile: admin.firestore.FieldValue.delete(),
              assignment: admin.firestore.FieldValue.delete(),
              projectionUpdatedAt:
                admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          }
          return projectionRef.delete();
        }

        const projection = {
          schemaVersion: after.schemaVersion || 3,
          userId,
          role,
          active: after.active === true,
          profile: after.profile || {},
          assignment: after.assignment ||
            admin.firestore.FieldValue.delete(),
          userRef: event.data.after.ref,
          projectionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        return projectionRef.set(projection, {merge: true});
      },
  );

  const authWrite = async () => {
    if (!after) {
      try {
        await auth.deleteUser(userId);
      } catch (error) {
        if (error.code !== "auth/user-not-found") throw error;
      }
      return;
    }

    if (!validRoles.has(after.role)) return;
    try {
      await auth.setCustomUserClaims(userId, {role: after.role});
      await auth.updateUser(userId, {disabled: after.active !== true});
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
  };

  await Promise.all([authWrite(), ...projectionWrites]);
});

exports.syncBusProjections = onDocumentWritten(
    "buses/{busId}",
    async (event) => {
      const busId = event.params.busId;
      const routeRef = db.collection("routes").doc(busId);
      const trackingRef = db.collection("tracking").doc(busId);

      if (!event.data.after.exists) {
        await Promise.all([routeRef.delete(), trackingRef.delete()]);
        return;
      }

      const bus = event.data.after.data();
      const route = bus.route && typeof bus.route === "object" ? bus.route : {};
      const tracking = bus.tracking && typeof bus.tracking === "object" ?
    bus.tracking : {};
      const writes = [];

      if (Object.keys(route).length > 0) {
        const routeProjection = {
          schemaVersion: bus.schemaVersion || 3,
          ...route,
          busId,
          busRef: event.data.after.ref,
          active: bus.active === true,
          driverId: bus.assignment && bus.assignment.driverId ?
          bus.assignment.driverId : admin.firestore.FieldValue.delete(),
          projectionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        writes.push(routeRef.set(routeProjection, {merge: true}));
      }

      if (Object.keys(tracking).length > 0) {
        writes.push(trackingRef.set({
          schemaVersion: bus.schemaVersion || 3,
          ...tracking,
          busId,
          driverId: tracking.driverId ||
          admin.firestore.FieldValue.delete(),
          busRef: event.data.after.ref,
          projectionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true}));
      }

      await Promise.all(writes);
    },
);

/**
 * Returns a Firestore timestamp from a tracking value when one exists.
 * @param {*} value Candidate timestamp.
 * @return {admin.firestore.Timestamp|null} Parsed timestamp.
 */
function trackingTimestamp(value) {
  return value && typeof value.toMillis === "function" ? value : null;
}

/**
 * Detects unexpectedly lost driver tracking without relying on the driver
 * phone to report its own shutdown. Intentionally stopped trips are cleared.
 */
exports.monitorTrackingHealth = onSchedule(
    {
      schedule: "every 1 minutes",
      timeZone: "Asia/Kolkata",
      timeoutSeconds: 60,
    },
    async () => {
      const settings = await db.collection("app_settings")
          .doc("operations").get();
      const configuredTimeout = Number(
          settings.data() && settings.data().gpsLostTimeoutSeconds,
      );
      const timeoutSeconds = Number.isFinite(configuredTimeout) ?
        Math.min(600, Math.max(60, configuredTimeout)) : 120;
      const now = admin.firestore.Timestamp.now();
      const buses = await db.collection("buses").get();

      await Promise.all(buses.docs.map(async (busDoc) => {
        const bus = busDoc.data();
        const tracking = bus.tracking && typeof bus.tracking === "object" ?
          bus.tracking : {};
        const point = tracking.currentPoint &&
          typeof tracking.currentPoint === "object" ?
          tracking.currentPoint : {};
        const active = tracking.isActive === true ||
          String(tracking.status || "").toLowerCase() === "running";
        const lastSignal = trackingTimestamp(tracking.serviceHeartbeatAt) ||
          trackingTimestamp(point.capturedAt) ||
          trackingTimestamp(tracking.lastUpdatedAt) ||
          trackingTimestamp(bus.updatedAt);
        const stale = active && (!lastSignal ||
          now.toMillis() - lastSignal.toMillis() >
            timeoutSeconds * 1000);
        const alertRef = db.collection("emergencies")
            .doc(`gps_lost_${busDoc.id}`);
        const alert = await alertRef.get();
        const existing = alert.exists ? alert.data() : {};
        const existingStatus = String(existing.status || "").toLowerCase();

        if (!stale) {
          if (existingStatus === "active" ||
              existingStatus === "acknowledged") {
            await alertRef.set({
              status: "cleared",
              cleared: true,
              clearedReason: active ?
                "driver_gps_reconnected" : "trip_stopped",
              clearedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          }
          return;
        }

        const route = bus.route && typeof bus.route === "object" ?
          bus.route : {};
        const assignment = bus.assignment &&
          typeof bus.assignment === "object" ? bus.assignment : {};
        const wasOpen = existingStatus === "active" ||
          existingStatus === "acknowledged";
        const payload = {
          eventId: `gps_lost_${busDoc.id}`,
          type: "gps_lost",
          priority: "high",
          busId: busDoc.id,
          busNo: bus.busNo || busDoc.id,
          driverId: assignment.driverId || tracking.driverId || null,
          routeName: route.routeName || route.name || null,
          status: wasOpen ? existingStatus : "active",
          acknowledged: wasOpen && existingStatus === "acknowledged",
          cleared: false,
          timeoutSeconds,
          lastSignalAt: lastSignal,
          location: {
            latitude: typeof point.latitude === "number" ?
              point.latitude : null,
            longitude: typeof point.longitude === "number" ?
              point.longitude : null,
            capturedAt: trackingTimestamp(point.capturedAt),
          },
          lastObservedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (!wasOpen) {
          payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
          payload.acknowledgedAt =
            admin.firestore.FieldValue.delete();
          payload.acknowledgedBy =
            admin.firestore.FieldValue.delete();
          payload.clearedAt = admin.firestore.FieldValue.delete();
          payload.clearedBy = admin.firestore.FieldValue.delete();
        }
        await alertRef.set(payload, {merge: true});
      }));
    },
);
