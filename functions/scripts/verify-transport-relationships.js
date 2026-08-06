"use strict";

const admin = require("firebase-admin");

const COLLECTIONS = ["users", "drivers", "buses", "routes", "tracking"];

/**
 * Returns true for a non-empty string.
 * @param {*} value Candidate value.
 * @return {boolean} Whether the value is a non-empty string.
 */
function isString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * Returns a plain object or an empty object for an invalid value.
 * @param {*} value Candidate map.
 * @return {object} Plain object value.
 */
function asMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value : {};
}

/**
 * Normalizes human-readable stop names for comparison.
 * @param {*} value Candidate stop name.
 * @return {string} Normalized stop name.
 */
function normalizedName(value) {
  return isString(value) ? value.trim().replace(/\s+/g, " ").toUpperCase() : "";
}

/**
 * Returns true when a coordinate pair can represent an actual GPS point.
 * @param {*} point Candidate route point.
 * @return {boolean} Whether the route point has usable coordinates.
 */
function hasValidCoordinates(point) {
  const value = asMap(point);
  const latitude = value.latitude;
  const longitude = value.longitude;
  if (typeof latitude !== "number" || !Number.isFinite(latitude) ||
      typeof longitude !== "number" || !Number.isFinite(longitude)) {
    return false;
  }
  if (latitude === 0 && longitude === 0) return false;
  return latitude >= -90 && latitude <= 90 &&
    longitude >= -180 && longitude <= 180;
}

/**
 * Returns route points ordered by sequence and then their stored position.
 * @param {*} route Candidate route map.
 * @return {Array<object>} Ordered route point maps.
 */
function orderedTrackPoints(route) {
  const points = asMap(route).trackPoints;
  if (!Array.isArray(points)) return [];
  return points.map((point, index) => ({
    point: asMap(point),
    index,
    sequence: Number.isFinite(asMap(point).sequence) ?
      asMap(point).sequence : index,
  })).sort((left, right) =>
    left.sequence - right.sequence || left.index - right.index,
  ).map((entry) => entry.point);
}

/**
 * Converts a Firestore snapshot into a document-ID map.
 * @param {object} snapshot Firestore query snapshot.
 * @return {Map<string, object>} Documents keyed by ID.
 */
function snapshotMap(snapshot) {
  return new Map(snapshot.docs.map((document) => [
    document.id,
    document.data(),
  ]));
}

/**
 * Adds an ID to a map of assignment targets and their owners.
 * @param {Map<string, Array<string>>} ownersByTarget Assignment index.
 * @param {*} targetId Candidate assignment target ID.
 * @param {string} ownerId Assignment owner ID.
 */
function addOwner(ownersByTarget, targetId, ownerId) {
  if (!isString(targetId)) return;
  const owners = ownersByTarget.get(targetId) || [];
  owners.push(ownerId);
  ownersByTarget.set(targetId, owners);
}

/**
 * Records a verification problem.
 * @param {Array<object>} problems Accumulated problems.
 * @param {string} code Stable problem code.
 * @param {string} path Firestore path or field path.
 * @param {string} message Human-readable problem description.
 */
function problem(problems, code, path, message) {
  problems.push({code, path, message});
}

/**
 * Validates a route's first ordered stop and its declared start point.
 * @param {Array<object>} problems Accumulated problems.
 * @param {string} path Route path for reporting.
 * @param {*} route Candidate route map.
 */
function validateFirstStop(problems, path, route) {
  const routeData = asMap(route);
  const points = orderedTrackPoints(routeData);
  if (points.length === 0) {
    problem(problems, "missing-track-points", path,
        "Route has no trackPoints.");
    return;
  }

  const first = points[0];
  if (!hasValidCoordinates(first)) {
    problem(problems, "invalid-first-stop-location", path,
        "First ordered trackPoint needs valid non-zero latitude/longitude.");
  }

  const startPoint = normalizedName(routeData.startPoint);
  const firstName = normalizedName(first.name);
  if (!startPoint || !firstName || startPoint !== firstName) {
    problem(problems, "start-point-mismatch", path,
        `startPoint "${routeData.startPoint || ""}" does not match ` +
        `first stop "${first.name || ""}".`);
  }
}

/**
 * Validates canonical driver-to-bus assignments and driver projections.
 * @param {object} context Loaded collections and result indexes.
 */
function validateDrivers(context) {
  const {problems, users, drivers, buses, routes, driversByBus} = context;
  const canonicalDrivers = [...users.entries()].filter(([, data]) =>
    data.role === "driver",
  );

  for (const [driverId, user] of canonicalDrivers) {
    const path = `users/${driverId}`;
    const projection = drivers.get(driverId);
    if (!projection) {
      problem(problems, "missing-driver-projection", path,
          `drivers/${driverId} does not exist.`);
    } else if (projection.userId !== driverId || projection.role !== "driver") {
      problem(problems, "driver-projection-identity-mismatch",
          `drivers/${driverId}`,
          "userId and role must match the canonical driver.");
    }

    const assignment = asMap(user.assignment);
    const busId = assignment.busId;
    if (!isString(busId)) {
      problem(problems, "unassigned-driver", path,
          "Driver has no assignment.busId.");
      if (projection && isString(asMap(projection.assignment).busId)) {
        problem(problems, "driver-projection-mismatch",
            `drivers/${driverId}`,
            "Projection is assigned while the canonical driver is not.");
      }
      continue;
    }
    addOwner(driversByBus, busId, driverId);

    const bus = buses.get(busId);
    if (!bus) {
      problem(problems, "orphan-driver-assignment", path,
          `Assigned bus buses/${busId} does not exist.`);
      continue;
    }
    const busDriverId = asMap(bus.assignment).driverId;
    if (busDriverId !== driverId) {
      problem(problems, "driver-bus-mismatch", path,
          `buses/${busId}.assignment.driverId is ` +
          `"${busDriverId || "<missing>"}".`);
    }

    const busRoute = asMap(bus.route);
    const expectedRouteId = busRoute.routeId || busId;
    if (assignment.routeId !== expectedRouteId) {
      problem(problems, "driver-route-mismatch", path,
          `assignment.routeId is "${assignment.routeId || "<missing>"}"; ` +
          `expected "${expectedRouteId}".`);
    }
    if (!routes.has(expectedRouteId)) {
      problem(problems, "orphan-driver-route", path,
          `Assigned route routes/${expectedRouteId} does not exist.`);
    }

    if (projection) {
      const projectionAssignment = asMap(projection.assignment);
      const projectionBusId = projectionAssignment.busId;
      if (projectionBusId !== busId) {
        problem(problems, "driver-projection-mismatch",
            `drivers/${driverId}`,
            `assignment.busId is "${projectionBusId || "<missing>"}"; ` +
            `expected "${busId}".`);
      }
      if (projectionAssignment.routeId !== expectedRouteId ||
          projectionAssignment.routeNo !== busRoute.routeNo) {
        problem(problems, "driver-projection-route-mismatch",
            `drivers/${driverId}`,
            "assignment.routeId/routeNo do not match the assigned bus.");
      }
    }
    if (assignment.routeNo !== busRoute.routeNo) {
      problem(problems, "driver-route-number-mismatch", path,
          `assignment.routeNo is "${assignment.routeNo || "<missing>"}"; ` +
          `expected "${busRoute.routeNo || "<missing>"}".`);
    }
  }

  for (const driverId of drivers.keys()) {
    const user = users.get(driverId);
    if (!user || user.role !== "driver") {
      problem(problems, "orphan-driver-projection", `drivers/${driverId}`,
          "No matching canonical driver exists in users.");
    }
  }
}

/**
 * Validates buses, route/tracking projections, and reciprocal assignments.
 * @param {object} context Loaded collections and result indexes.
 */
function validateBuses(context) {
  const {
    problems, users, buses, routes, tracking, busesByDriver,
  } = context;

  for (const [busId, bus] of buses) {
    const path = `buses/${busId}`;
    if (bus.busId !== busId) {
      problem(problems, "bus-identity-mismatch", path,
          `busId is "${bus.busId || "<missing>"}".`);
    }
    const assignment = asMap(bus.assignment);
    const driverId = assignment.driverId;
    if (!isString(driverId)) {
      problem(problems, "unassigned-bus", path,
          "Bus has no assignment.driverId.");
    } else {
      addOwner(busesByDriver, driverId, busId);
      const user = users.get(driverId);
      if (!user || user.role !== "driver") {
        problem(problems, "orphan-bus-assignment", path,
            `Assigned driver users/${driverId} is missing or not a driver.`);
      } else if (asMap(user.assignment).busId !== busId) {
        problem(problems, "bus-driver-mismatch", path,
            `users/${driverId}.assignment.busId is ` +
            `"${asMap(user.assignment).busId || "<missing>"}".`);
      }
    }

    const embeddedRoute = asMap(bus.route);
    const embeddedTracking = asMap(bus.tracking);
    if (embeddedTracking.busId !== busId) {
      problem(problems, "embedded-tracking-bus-mismatch",
          `${path}.tracking`,
          `busId is "${embeddedTracking.busId || "<missing>"}".`);
    }
    if (embeddedTracking.driverId !== driverId) {
      problem(problems, "embedded-tracking-driver-mismatch",
          `${path}.tracking`,
          `driverId is "${embeddedTracking.driverId || "<missing>"}"; ` +
          `expected "${driverId}".`);
    }
    const routeId = embeddedRoute.routeId;
    if (!isString(routeId)) {
      problem(problems, "missing-route-id", path,
          "Embedded route.routeId is missing.");
    } else if (routeId !== busId) {
      problem(problems, "bus-route-id-mismatch", path,
          `Embedded route.routeId is "${routeId}"; expected "${busId}".`);
    }
    validateFirstStop(problems, `${path}.route`, embeddedRoute);

    const route = routes.get(busId);
    if (!route) {
      problem(problems, "missing-route-projection", path,
          `routes/${busId} does not exist.`);
    } else {
      if (route.busId !== busId || route.routeId !== busId) {
        problem(problems, "route-projection-mismatch", `routes/${busId}`,
            "busId and routeId must both match the route document ID.");
      }
      if (route.routeNo !== embeddedRoute.routeNo) {
        problem(problems, "route-number-mismatch", `routes/${busId}`,
            "routeNo does not match the bus embedded route.");
      }
      if (route.driverId !== driverId) {
        problem(problems, "route-driver-mismatch", `routes/${busId}`,
            `driverId is "${route.driverId || "<missing>"}"; ` +
            `expected "${driverId}".`);
      }
      validateFirstStop(problems, `routes/${busId}`, route);
    }

    const trackingData = tracking.get(busId);
    if (!trackingData) {
      problem(problems, "missing-tracking-projection", path,
          `tracking/${busId} does not exist.`);
    } else {
      if (trackingData.busId !== busId) {
        problem(problems, "tracking-bus-mismatch", `tracking/${busId}`,
            `busId is "${trackingData.busId || "<missing>"}".`);
      }
      if (trackingData.driverId !== driverId) {
        problem(problems, "tracking-driver-mismatch", `tracking/${busId}`,
            `driverId is "${trackingData.driverId || "<missing>"}"; ` +
            `expected "${driverId}".`);
      }
    }
  }
}

/**
 * Reports duplicate and orphan route/tracking documents.
 * @param {object} context Loaded collections and result indexes.
 */
function validateIndexes(context) {
  const {
    problems, buses, routes, tracking, driversByBus, busesByDriver,
  } = context;
  for (const [busId, driverIds] of driversByBus) {
    if (driverIds.length > 1) {
      problem(problems, "duplicate-bus-assignment", `buses/${busId}`,
          `Assigned by multiple drivers: ${driverIds.join(", ")}.`);
    }
  }
  for (const [driverId, busIds] of busesByDriver) {
    if (busIds.length > 1) {
      problem(problems, "duplicate-driver-assignment",
          `users/${driverId}`, `Assigned by multiple buses: ` +
          `${busIds.join(", ")}.`);
    }
  }
  for (const routeId of routes.keys()) {
    if (!buses.has(routeId)) {
      problem(problems, "orphan-route-projection", `routes/${routeId}`,
          "No matching canonical bus exists.");
    }
  }
  for (const trackingId of tracking.keys()) {
    if (!buses.has(trackingId)) {
      problem(problems, "orphan-tracking-projection",
          `tracking/${trackingId}`, "No matching canonical bus exists.");
    }
  }
}

/**
 * Prints verification results in a deterministic, reviewable format.
 * @param {object} context Loaded collections and verification problems.
 */
function printReport(context) {
  const {problems, users, drivers, buses, routes, tracking} = context;
  console.log("BusBuddy canonical transport verification (read-only)");
  console.log("  users: " + users.size);
  console.log("  driver projections: " + drivers.size);
  console.log("  buses: " + buses.size);
  console.log("  route projections: " + routes.size);
  console.log("  tracking projections: " + tracking.size);
  console.log("  problems: " + problems.length);

  if (problems.length === 0) {
    console.log("PASS: Driver -> Bus -> Route relationships are consistent.");
    return;
  }

  const ordered = [...problems].sort((left, right) =>
    left.path.localeCompare(right.path) || left.code.localeCompare(right.code),
  );
  for (const item of ordered) {
    console.error(`FAIL [${item.code}] ${item.path}: ${item.message}`);
  }
}

/** Reads canonical Firestore collections and verifies their relationships. */
async function main() {
  if (process.argv.slice(2).includes("--help")) {
    console.log("Usage: npm run verify-transport");
    console.log("Reads Firestore only; this command has no write/apply mode.");
    return;
  }
  if (process.argv.length > 2) {
    throw new Error("Unknown arguments. This verifier has no apply mode.");
  }

  admin.initializeApp();
  const db = admin.firestore();
  db.settings({preferRest: true});
  const snapshots = await Promise.all(
      COLLECTIONS.map((collection) => db.collection(collection).get()),
  );
  const context = {
    problems: [],
    users: snapshotMap(snapshots[0]),
    drivers: snapshotMap(snapshots[1]),
    buses: snapshotMap(snapshots[2]),
    routes: snapshotMap(snapshots[3]),
    tracking: snapshotMap(snapshots[4]),
    driversByBus: new Map(),
    busesByDriver: new Map(),
  };

  validateDrivers(context);
  validateBuses(context);
  validateIndexes(context);
  printReport(context);
  if (context.problems.length > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
