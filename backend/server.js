const express = require("express");
const cors = require("cors");
require("dotenv").config();

const authRoutes = require("./routes/auth.routes");
const busRoutes = require("./routes/bus.routes");
const locationRoutes = require("./routes/location.routes");

const app = express();

app.use(cors());
app.use(express.json());

app.use("/api/auth", authRoutes);
app.use("/api/bus", busRoutes);
app.use("/api/location", locationRoutes);

app.get("/", (req, res) => {
  res.send("ESEC BUS Backend Running");
});

const PORT = process.env.PORT || 5000;

app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
