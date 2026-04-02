const express = require("express");
const router = express.Router();
const authMiddleware = require("../middleware/auth.middleware");
const {
  updateLocation,
  getBusLocation,
} = require("../controllers/location.controller");

router.post("/update", authMiddleware, updateLocation);
router.get("/:busId", getBusLocation);

module.exports = router;
