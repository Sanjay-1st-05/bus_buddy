const express = require("express");
const router = express.Router();
const authMiddleware = require("../middleware/auth.middleware");
const { addBus, getBuses } = require("../controllers/bus.controller");

router.post("/add", authMiddleware, addBus);
router.get("/all", getBuses);

module.exports = router;
