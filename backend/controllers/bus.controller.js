const { db } = require("../services/firebase.service");

const addBus = async (req, res) => {
  if (req.role !== "admin") {
    return res.status(403).json({ message: "Only admin can add bus" });
  }

  const { busId, route, driverId } = req.body;

  await db.collection("buses").doc(busId).set({
    route,
    driverId,
  });

  res.json({ message: "Bus added successfully" });
};

const getBuses = async (req, res) => {
  const snapshot = await db.collection("buses").get();
  const buses = snapshot.docs.map((doc) => doc.data());
  res.json(buses);
};

module.exports = { addBus, getBuses };
