const express = require("express");
const { getSession } = require("../controllers/auth.controller");
const authMiddleware = require("../middleware/auth.middleware");

const router = express.Router();

router.get("/session", authMiddleware, getSession);

module.exports = router;
