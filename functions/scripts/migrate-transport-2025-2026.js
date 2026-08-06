const admin = require("firebase-admin");
const transport = require("../data/transport-2025-2026.json");

const args = new Set(process.argv.slice(2));
const shouldApply = args.has("--apply");
const rosterAcknowledged = args.has("--acknowledge-driver-roster");

const roleCollections = {
  admin: "admins",
  driver: "drivers",
  student: "students",
};

/**
 * Returns true when value is a non-empty string.
 * @param {*} value Candidate value.
 * @return {boolean} Whether the candidate is a non-empty string.
 */
function isString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * Normalizes legacy route numbers for safe cross-collection matching.
 * @param {*} value Legacy or canonical route number.
 * @return {string|null} Two-digit route number, or null when invalid.
 */
function routeKey(value) {
  if (!isString(value) && typeof value !== "number") return null;
  const parsed = Number.parseInt(String(value).trim(), 10);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 99) return null;
  return String(parsed).padStart(2, "0");
}

/**
 * Converts legacy string stops to the embedded route point shape.
 * @param {Array<*>} stops Legacy route stops.
 * @param {string} busId Canonical bus identifier.
 * @return {Array<object>} Canonical route points.
 */
function routePoints(stops, busId) {
  if (!Array.isArray(stops)) return [];
  return stops.map((stop, index) => {
    if (stop && typeof stop === "object" && !Array.isArray(stop)) {
      return {
        ...stop,
        stopId: stop.stopId || `${busId}-${index}`,
        sequence: Number.isInteger(stop.sequence) ? stop.sequence : index,
      };
    }
    return {
      stopId: `${busId}-${index}`,
      name: String(stop || "").trim().toUpperCase(),
      sequence: index,
    };
  }).filter((stop) => isString(stop.name) || isString(stop.stopId));
}

/**
 * Distinguishes a current trip from a stale legacy active flag.
 * @param {object} tracking Canonical or legacy tracking data.
 * @return {boolean} Whether the trip is active with recent evidence.
 */
function isRecentlyActive(tracking) {
  if (!tracking || tracking.isActive !== true) return false;
  const point = tracking.currentPoint || {};
  const rawTimestamp = tracking.lastUpdatedAt || tracking.updatedAt ||
    point.capturedAt;
  if (!rawTimestamp) return true;
  const date = typeof rawTimestamp.toDate === "function" ?
    rawTimestamp.toDate() : new Date(rawTimestamp);
  if (Number.isNaN(date.getTime())) return true;
  const ageMilliseconds = Date.now() - date.getTime();
  return ageMilliseconds >= -300000 && ageMilliseconds <= 12 * 60 * 60 * 1000;
}

/** Fails early when the source dataset contains unsafe or duplicate values. */
function validateSource() {
  if (transport.schemaVersion !== 3) {
    throw new Error("Expected transport schemaVersion 3.");
  }
  if (!Array.isArray(transport.buses) || !Array.isArray(transport.drivers)) {
    throw new Error("Transport buses and drivers must be arrays.");
  }

  const unique = (items, key, label) => {
    const values = items.map((item) => item[key]);
    if (values.some((value) => !isString(value))) {
      throw new Error(`${label} contains an empty ${key}.`);
    }
    if (new Set(values).size !== values.length) {
      throw new Error(`${label} contains a duplicate ${key}.`);
    }
  };

  unique(transport.buses, "busId", "Buses");
  unique(transport.buses, "routeNo", "Buses");
  unique(transport.buses, "busNo", "Buses");
  unique(transport.drivers, "driverId", "Drivers");
  unique(transport.drivers, "routeNo", "Drivers");
  unique(transport.drivers, "mobile", "Drivers");

  for (const bus of transport.buses) {
    if (!/^BUS_\d{2}$/.test(bus.busId) || !/^\d{2}$/.test(bus.routeNo)) {
      throw new Error(`Invalid bus identity: ${JSON.stringify(bus)}`);
    }
    for (const key of ["busNo", "routeName", "via"]) {
      if (!isString(bus[key])) throw new Error(`${bus.busId} has no ${key}.`);
    }
  }

  for (const driver of transport.drivers) {
    if (!/^drv_bus_\d{2}$/.test(driver.driverId) ||
        !/^\d{2}$/.test(driver.routeNo) ||
        !/^[6-9]\d{9}$/.test(driver.mobile)) {
      throw new Error(`Invalid driver row: ${JSON.stringify(driver)}`);
    }
    if (!isString(driver.name)) {
      throw new Error(`${driver.driverId} has no name.`);
    }
  }
}

/** Builds and prints the non-destructive import plan. */
function printPlan() {
  const busByRoute = new Map(
      transport.buses.map((bus) => [bus.routeNo, bus]),
  );
  const driverByRoute = new Map(
      transport.drivers.map((driver) => [driver.routeNo, driver]),
  );
  const matchedRoutes = transport.drivers
      .filter((driver) => busByRoute.has(driver.routeNo))
      .map((driver) => driver.routeNo);
  const busesWithoutRosterDriver = transport.buses
      .filter((bus) => !driverByRoute.has(bus.routeNo))
      .map((bus) => bus.routeNo);
  const driversWithoutPdfBus = transport.drivers
      .filter((driver) => !busByRoute.has(driver.routeNo))
      .map((driver) => driver.routeNo);

  console.log("BusBuddy transport migration plan");
  console.log(`  buses/routes/tracking: ${transport.buses.length}`);
  console.log(`  canonical/driver profiles: ${transport.drivers.length}`);
  console.log(`  confirmed route assignments: ${matchedRoutes.length}`);
  console.log("  PDF buses without roster driver: " +
    busesWithoutRosterDriver.join(", "));
  console.log("  roster routes pending PDF bus data: " +
    driversWithoutPdfBus.join(", "));
  console.log("  existing fields are preserved with merge writes");
  console.log("  active trips block reassignment");
}

/**
 * Returns a role projection without copying authentication secrets.
 * @param {string} userId Canonical user identifier.
 * @param {object} data Canonical user data.
 * @param {object} userRef Canonical Firestore document reference.
 * @param {object} timestamp Server timestamp sentinel.
 * @return {object} Safe role projection.
 */
function roleProjection(userId, data, userRef, timestamp) {
  const assignment = data.assignment ||
    (isString(data.busId) ? {busId: data.busId} : null);
  return {
    schemaVersion: data.schemaVersion || transport.schemaVersion,
    userId,
    role: data.role,
    active: data.active === true,
    profile: data.profile || {},
    assignment: assignment || admin.firestore.FieldValue.delete(),
    ...(isString(data.rollNo) ? {rollNo: data.rollNo} : {}),
    ...(isString(data.department) ? {department: data.department} : {}),
    ...(typeof data.year === "number" ? {year: data.year} : {}),
    ...(isString(data.busId) ? {busId: data.busId} : {}),
    userRef,
    projectionUpdatedAt: timestamp,
  };
}

/**
 * Creates a disabled Auth identity when a driver profile has none.
 * @param {object} auth Firebase Auth service.
 * @param {object} driver Driver source row.
 * @return {Promise<object>} Auth user and creation status.
 */
async function ensureDriverIdentity(auth, driver) {
  try {
    return {user: await auth.getUser(driver.driverId), created: false};
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    const user = await auth.createUser({
      uid: driver.driverId,
      email: `${driver.driverId.toLowerCase()}@auth.busbuddy.bytbeta.com`,
      displayName: driver.name,
      disabled: true,
    });
    return {user, created: true};
  }
}

/** Imports source data with merge semantics and projects existing users. */
async function applyMigration() {
  if (transport.source.driverRosterReviewed !== true && !rosterAcknowledged) {
    throw new Error(
        "Review the driver roster, then rerun with " +
        "--apply --acknowledge-driver-roster.",
    );
  }

  admin.initializeApp();
  const db = admin.firestore();
  db.settings({preferRest: true});
  const auth = admin.auth();
  const timestamp = admin.firestore.FieldValue.serverTimestamp();

  const [legacyMasterSnapshot, legacyRouteSnapshot,
    legacyLocationSnapshot, legacyDriverSnapshot] = await Promise.all([
    db.collection("bus_master").get(),
    db.collection("bus_routes").get(),
    db.collection("bus_location").get(),
    db.collection("drivers").get(),
  ]);
  const legacyMastersByRoute = new Map();
  const legacyRoutesByRoute = new Map();
  const legacyRoutesById = new Map(
      legacyRouteSnapshot.docs.map((doc) => [doc.id, doc]),
  );
  const legacyLocationsById = new Map(
      legacyLocationSnapshot.docs.map((doc) => [doc.id, doc]),
  );
  const legacyDriversById = new Map(
      legacyDriverSnapshot.docs.map((doc) => [doc.id, doc]),
  );
  for (const doc of legacyMasterSnapshot.docs) {
    const key = routeKey(doc.data().routeNo);
    if (key && !legacyMastersByRoute.has(key)) {
      legacyMastersByRoute.set(key, doc);
    }
  }
  for (const doc of legacyRouteSnapshot.docs) {
    const key = routeKey(doc.data().routeNo);
    if (key && !legacyRoutesByRoute.has(key)) {
      legacyRoutesByRoute.set(key, doc);
    }
  }

  const drivers = transport.drivers.map((source) => {
    const master = legacyMastersByRoute.get(source.routeNo);
    const masterDriverId = master && master.data().driverId;
    const paddedId = source.driverId.toUpperCase();
    const compactId = `DRV_BUS_${Number.parseInt(source.routeNo, 10)}`;
    const driverId = isString(masterDriverId) ? masterDriverId :
      legacyDriversById.has(paddedId) ? paddedId :
      legacyDriversById.has(compactId) ? compactId : paddedId;
    return {...source, driverId};
  });
  const busByRoute = new Map(
      transport.buses.map((bus) => [bus.routeNo, bus]),
  );
  const driverByRoute = new Map(
      drivers.map((driver) => [driver.routeNo, driver]),
  );
  const sourceBusIds = new Set(transport.buses.map((bus) => bus.busId));
  const sourceDriverIds = new Set(
      drivers.map((driver) => driver.driverId),
  );

  const busRefs = transport.buses.map((bus) => db.collection("buses")
      .doc(bus.busId));
  const driverRefs = drivers.map((driver) => db.collection("users")
      .doc(driver.driverId));
  const [busSnapshots, driverSnapshots] = await Promise.all([
    db.getAll(...busRefs),
    db.getAll(...driverRefs),
  ]);
  const busSnapshotsById = new Map(
      busSnapshots.map((snapshot) => [snapshot.id, snapshot]),
  );
  const driverSnapshotsById = new Map(
      driverSnapshots.map((snapshot) => [snapshot.id, snapshot]),
  );

  const outsideBusIds = new Set();
  const outsideDriverIds = new Set();
  for (const driver of drivers) {
    const bus = busByRoute.get(driver.routeNo);
    if (!bus) continue;
    const driverData = driverSnapshotsById.get(driver.driverId).data() || {};
    const previousBusId = driverData.assignment && driverData.assignment.busId;
    if (isString(previousBusId) && !sourceBusIds.has(previousBusId)) {
      outsideBusIds.add(previousBusId);
    }
  }
  const blockedBusAssignments = new Set();
  for (const bus of transport.buses) {
    const busData = busSnapshotsById.get(bus.busId).data() || {};
    const previousDriverId = busData.assignment &&
      busData.assignment.driverId;
    if (isString(previousDriverId) &&
        !sourceDriverIds.has(previousDriverId)) {
      outsideDriverIds.add(previousDriverId);
    }
  }
  const outsideBusSnapshots = outsideBusIds.size === 0 ? [] :
    await db.getAll(...[...outsideBusIds].map((id) => db.collection("buses")
        .doc(id)));
  const outsideBusesById = new Map(
      outsideBusSnapshots.map((snapshot) => [snapshot.id, snapshot]),
  );
  const outsideDriverSnapshots = outsideDriverIds.size === 0 ? [] :
    await db.getAll(...[...outsideDriverIds].map((id) =>
      db.collection("users").doc(id)));
  const outsideDriversById = new Map(
      outsideDriverSnapshots.map((snapshot) => [snapshot.id, snapshot]),
  );

  for (const bus of transport.buses) {
    const driver = driverByRoute.get(bus.routeNo);
    if (!driver) continue;
    const snapshot = busSnapshotsById.get(bus.busId);
    const data = snapshot.data() || {};
    const tracking = data.tracking || {};
    const legacyMaster = legacyMastersByRoute.get(bus.routeNo);
    const legacyMasterData = legacyMaster ? legacyMaster.data() : {};
    const legacyLocation = legacyLocationsById.get(
        legacyMaster ? legacyMaster.id : bus.busId,
    );
    const legacyTracking = legacyLocation ? legacyLocation.data() : {};
    const previousDriverId = (data.assignment && data.assignment.driverId) ||
      legacyMasterData.driverId;
    if ((isRecentlyActive(tracking) || isRecentlyActive(legacyTracking)) &&
        previousDriverId !== driver.driverId) {
      blockedBusAssignments.add(bus.busId);
      console.warn(
          `Deferring ${bus.busId} driver assignment: trip is active.`,
      );
      continue;
    }

    const driverData = driverSnapshotsById.get(driver.driverId).data() || {};
    const previousBusId = driverData.assignment && driverData.assignment.busId;
    if (isString(previousBusId) && previousBusId !== bus.busId) {
      const previousSnapshot = busSnapshotsById.get(previousBusId) ||
        outsideBusesById.get(previousBusId);
      if (previousSnapshot && previousSnapshot.exists &&
          isRecentlyActive(previousSnapshot.data().tracking || {})) {
        blockedBusAssignments.add(bus.busId);
        console.warn(
            `Deferring ${bus.busId} assignment: ${previousBusId} is active.`,
        );
      }
    }
  }

  const authState = new Map();
  for (const driver of drivers) {
    const result = await ensureDriverIdentity(auth, driver);
    await auth.setCustomUserClaims(driver.driverId, {role: "driver"});
    authState.set(driver.driverId, result);
  }

  const writer = db.bulkWriter();
  writer.onWriteError((error) => error.failedAttempts < 3);

  const existingUsers = await db.collection("users").get();
  for (const doc of existingUsers.docs) {
    const data = doc.data();
    if (data.role === "driver") continue;
    const collection = roleCollections[data.role];
    if (!collection) continue;
    const profile = {
      ...(data.profile || {}),
      ...(!isString(data.profile && data.profile.name) ? {
        name: data.rollNo || doc.id,
      } : {}),
      ...(isString(data.rollNo) ? {rollNo: data.rollNo} : {}),
      ...(isString(data.department) ? {department: data.department} : {}),
      ...(typeof data.year === "number" ? {year: data.year} : {}),
      ...(isString(data.mobile) ? {mobile: data.mobile} : {}),
    };
    const assignment = data.assignment ||
      (isString(data.busId) ? {busId: data.busId} : null);
    const canonicalData = {
      ...data,
      schemaVersion: transport.schemaVersion,
      userId: doc.id,
      profile,
      ...(assignment ? {assignment} : {}),
      updatedAt: timestamp,
    };
    writer.set(doc.ref, {
      schemaVersion: canonicalData.schemaVersion,
      userId: doc.id,
      profile,
      ...(assignment ? {assignment} : {}),
      updatedAt: timestamp,
    }, {merge: true});
    writer.set(
        db.collection(collection).doc(doc.id),
        roleProjection(doc.id, canonicalData, doc.ref, timestamp),
        {merge: true},
    );
  }

  for (const bus of transport.buses) {
    const busRef = db.collection("buses").doc(bus.busId);
    const routeRef = db.collection("routes").doc(bus.busId);
    const trackingRef = db.collection("tracking").doc(bus.busId);
    const snapshot = busSnapshotsById.get(bus.busId);
    const existing = snapshot.data() || {};
    const rosterDriver = driverByRoute.get(bus.routeNo);
    const driver = blockedBusAssignments.has(bus.busId) ? null : rosterDriver;
    const legacyMasterDoc = legacyMastersByRoute.get(bus.routeNo);
    const legacyMaster = legacyMasterDoc ? legacyMasterDoc.data() : {};
    const legacyRouteDoc = legacyRoutesByRoute.get(bus.routeNo) ||
      legacyRoutesById.get(legacyMasterDoc ? legacyMasterDoc.id : bus.busId) ||
      legacyRoutesById.get(bus.busId);
    const legacyRoute = legacyRouteDoc ? legacyRouteDoc.data() : {};
    const legacyLocationDoc = legacyLocationsById.get(
        legacyMasterDoc ? legacyMasterDoc.id : bus.busId,
    ) || legacyLocationsById.get(bus.busId);
    const legacyLocation = legacyLocationDoc ? legacyLocationDoc.data() : {};
    const existingRoute = existing.route || {};
    const existingTracking = existing.tracking || {};
    const normalizedExistingTracking = {...existingTracking};
    if (existingTracking.isActive === true &&
        !isRecentlyActive(existingTracking)) {
      normalizedExistingTracking.isActive = false;
      normalizedExistingTracking.status = "stopped";
    }
    const existingAssignment = existing.assignment || {};
    const legacyTrackPoints = routePoints(legacyRoute.stops, bus.busId);
    const trackPoints = Array.isArray(existingRoute.trackPoints) &&
        existingRoute.trackPoints.length > 0 ?
      existingRoute.trackPoints : legacyTrackPoints;
    const route = {
      ...existingRoute,
      routeId: bus.busId,
      routeNo: bus.routeNo,
      routeName: bus.routeName,
      startPoint: existingRoute.startPoint || legacyRoute.startPoint ||
        bus.routeName,
      endPoint: existingRoute.endPoint || legacyRoute.endPoint || "ESEC",
      via: bus.via,
      trackPoints,
      academicYear: transport.academicYear,
      sourceDocument: transport.source.busDetails,
      sourcePage: bus.pdfPage,
    };
    const assignment = driver ? {
      ...existingAssignment,
      driverId: driver.driverId,
      assignedAt: timestamp,
    } : existing.assignment;
    const tracking = {
      busId: bus.busId,
      currentPoint: {latitude: 0.0, longitude: 0.0},
      isActive: false,
      status: "stopped",
      ...(typeof legacyLocation.latitude === "number" &&
        typeof legacyLocation.longitude === "number" ? {
          currentPoint: {
            latitude: legacyLocation.latitude,
            longitude: legacyLocation.longitude,
          },
        } : {}),
      ...(typeof legacyLocation.isActive === "boolean" ? {
        isActive: isRecentlyActive(legacyLocation),
      } : {}),
      ...(isString(legacyLocation.status) ? {
        status: isRecentlyActive(legacyLocation) ?
          legacyLocation.status : "stopped",
      } : {}),
      ...(legacyLocation.updatedAt ?
        {lastUpdatedAt: legacyLocation.updatedAt} : {}),
      ...normalizedExistingTracking,
      ...(driver ? {driverId: driver.driverId} : {}),
    };
    const busPayload = {
      schemaVersion: transport.schemaVersion,
      busId: bus.busId,
      active: typeof existing.active === "boolean" ? existing.active :
        typeof legacyMaster.active === "boolean" ? legacyMaster.active : true,
      busNo: bus.busNo,
      route,
      ...(assignment ? {assignment} : {}),
      tracking,
      source: {
        ...(existing.source || {}),
        academicYear: transport.academicYear,
        document: transport.source.busDetails,
        pdfPage: bus.pdfPage,
        ...(legacyMasterDoc ? {
          legacyMasterPath: legacyMasterDoc.ref.path,
        } : {}),
        ...(legacyRouteDoc ? {
          legacyRoutePath: legacyRouteDoc.ref.path,
        } : {}),
        ...(legacyLocationDoc ? {
          legacyLocationPath: legacyLocationDoc.ref.path,
        } : {}),
      },
      updatedAt: timestamp,
      ...(!snapshot.exists ? {
        createdAt: legacyMaster.createdAt || timestamp,
      } : {}),
    };

    writer.set(busRef, busPayload, {merge: true});
    writer.set(routeRef, {
      schemaVersion: transport.schemaVersion,
      ...route,
      busId: bus.busId,
      busRef,
      active: busPayload.active,
      assignmentStatus: blockedBusAssignments.has(bus.busId) ?
        "blocked-active-trip" : driver ? "assigned" :
        "not-listed-in-roster",
      ...(driver ? {driverId: driver.driverId} : {}),
      feeSchedule: {
        academicYear: transport.academicYear,
        frequency: "semester",
        approximate: true,
        sourceDocument: transport.source.busDetails,
        sourcePage: bus.pdfPage,
      },
      updatedAt: timestamp,
    }, {merge: true});
    writer.set(trackingRef, {
      schemaVersion: transport.schemaVersion,
      ...tracking,
      busRef,
      updatedAt: timestamp,
    }, {merge: true});

    const previousDriverId = existingAssignment.driverId;
    if (driver && isString(previousDriverId) &&
        previousDriverId !== driver.driverId &&
        !sourceDriverIds.has(previousDriverId) &&
        outsideDriversById.get(previousDriverId).exists) {
      const previousDriverRef = db.collection("users").doc(previousDriverId);
      writer.update(previousDriverRef, {
        assignment: admin.firestore.FieldValue.delete(),
        updatedAt: timestamp,
      });
    }
  }

  for (const driver of drivers) {
    const userRef = db.collection("users").doc(driver.driverId);
    const driverRef = db.collection("drivers").doc(driver.driverId);
    const snapshot = driverSnapshotsById.get(driver.driverId);
    const existing = snapshot.data() || {};
    const legacyDriverDoc = legacyDriversById.get(driver.driverId);
    const legacyDriver = legacyDriverDoc ? legacyDriverDoc.data() : {};
    const bus = busByRoute.get(driver.routeNo);
    const assignableBus = bus && !blockedBusAssignments.has(bus.busId) ?
      bus : null;
    const authResult = authState.get(driver.driverId);
    const active = typeof existing.active === "boolean" ?
      existing.active : typeof legacyDriver.active === "boolean" ?
        legacyDriver.active : !authResult.user.disabled;
    const assignment = {
      ...(existing.assignment || {}),
      routeId: bus ? bus.busId : `BUS_${driver.routeNo}`,
      routeNo: driver.routeNo,
      ...(assignableBus ? {
        busId: assignableBus.busId,
        assignedAt: timestamp,
        pendingBusDetails: false,
        assignmentBlockedActiveTrip: false,
      } : bus ? {
        pendingBusDetails: false,
        assignmentBlockedActiveTrip: true,
      } : {
        pendingBusDetails: !isString(
            existing.assignment && existing.assignment.busId,
        ),
      }),
    };
    const userPayload = {
      schemaVersion: transport.schemaVersion,
      userId: driver.driverId,
      role: "driver",
      active,
      profile: {
        ...(existing.profile || {}),
        name: driver.name,
        mobile: driver.mobile,
      },
      assignment,
      authentication: {
        ...((existing.authentication || {})),
        status: authResult.user.disabled ?
          "password-required" : "provisioned",
      },
      source: {
        ...(existing.source || {}),
        document: transport.source.driverRoster,
        rosterReviewed: transport.source.driverRosterReviewed === true ||
          rosterAcknowledged,
        ...(legacyDriverDoc ? {
          legacyDriverPath: legacyDriverDoc.ref.path,
        } : {}),
      },
      updatedAt: timestamp,
      ...(!snapshot.exists ? {createdAt: timestamp} : {}),
    };

    writer.set(userRef, userPayload, {merge: true});
    writer.set(
        driverRef,
        {
          ...roleProjection(
              driver.driverId,
              userPayload,
              userRef,
              timestamp,
          ),
          driverName: driver.name,
          mobile: driver.mobile,
          active,
          role: "driver",
          ...(assignableBus || isString(legacyDriver.busId) ? {
            busId: legacyDriver.busId || assignableBus.busId,
          } : {}),
          updatedAt: timestamp,
          ...(!legacyDriverDoc ? {createdAt: timestamp} : {}),
        },
        {merge: true},
    );

    const previousBusId = existing.assignment && existing.assignment.busId;
    if (assignableBus && isString(previousBusId) &&
        previousBusId !== assignableBus.busId &&
        !sourceBusIds.has(previousBusId) &&
        outsideBusesById.get(previousBusId).exists) {
      const previousBusRef = db.collection("buses").doc(previousBusId);
      writer.update(previousBusRef, {
        "assignment": admin.firestore.FieldValue.delete(),
        "tracking.driverId": admin.firestore.FieldValue.delete(),
        "updatedAt": timestamp,
      });
    }
  }

  await writer.close();
  console.log("Transport migration applied successfully.");
  if (blockedBusAssignments.size > 0) {
    console.log("Deferred active-trip assignments: " +
      [...blockedBusAssignments].join(", "));
  }
  console.log(
      "New disabled driver identities require a password through the " +
      "existing admin provisioning flow before login.",
  );
}

/** Validates, previews, and optionally applies the migration. */
async function main() {
  validateSource();
  printPlan();
  if (!shouldApply) {
    console.log(
        "Dry run only. No Firebase credentials or database writes were used.",
    );
    console.log(
        "Apply after roster review: npm run migrate-transport -- " +
        "--apply --acknowledge-driver-roster",
    );
    return;
  }
  await applyMigration();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
