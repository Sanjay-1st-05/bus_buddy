const { db } = require("../services/firebase.service");

const updateLocation = async (req, res) => {
  if (req.role !== "driver") {
    return res.status(403).json({ message: "Only driver can update location" });
  }

  const { busId, latitude, longitude } = req.body;

  if (!busId || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return res.status(400).json({ message: "Invalid data" });
  }

  const busRef = db.collection("buses").doc(busId);
  const busDoc = await busRef.get();
  if (!busDoc.exists || busDoc.data()?.assignment?.driverId !== req.user.uid) {
    return res.status(403).json({ message: "Driver is not assigned to this bus" });
  }

  await busRef.update({
    "tracking.driverId": req.user.uid,
    "tracking.currentPoint.latitude": latitude,
    "tracking.currentPoint.longitude": longitude,
    "tracking.updatedAt": new Date(),
    "tracking.isActive": true,
    "tracking.status": "running",
    updatedAt: new Date(),
  });

  res.json({ message: "Location updated (FIREBASE)" });
};

const getBusLocation = async (req, res) => {
  const { busId } = req.params;

  const doc = await db.collection("buses").doc(busId).get();

  if (!doc.exists) {
    return res.status(404).json({ message: "Bus location not found" });
  }

  res.json(doc.data().tracking || null);
};

module.exports = { updateLocation, getBusLocation };
