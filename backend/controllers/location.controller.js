const { db } = require("../services/firebase.service");

const updateLocation = async (req, res) => {
  if (req.role !== "driver") {
    return res.status(403).json({ message: "Only driver can update location" });
  }

  const { busId, latitude, longitude } = req.body;

  if (!busId || !latitude || !longitude) {
    return res.status(400).json({ message: "Invalid data" });
  }

  await db.collection("bus_location").doc(busId).set({
    latitude,
    longitude,
    updatedAt: new Date(),
    isActive: true,
  });

  res.json({ message: "Location updated (FIREBASE)" });
};

const getBusLocation = async (req, res) => {
  const { busId } = req.params;

  const doc = await db.collection("bus_location").doc(busId).get();

  if (!doc.exists) {
    return res.status(404).json({ message: "Bus location not found" });
  }

  res.json(doc.data());
};

module.exports = { updateLocation, getBusLocation };
