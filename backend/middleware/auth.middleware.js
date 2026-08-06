const { auth } = require("../services/firebase.service");

module.exports = async (req, res, next) => {
  const authorization = req.headers.authorization || "";
  const [scheme, token] = authorization.split(" ");

  if (scheme !== "Bearer" || !token) {
    return res.status(401).json({ message: "Firebase ID token required" });
  }

  try {
    const decoded = await auth.verifyIdToken(token, true);
    req.user = decoded;
    req.role = decoded.role;
    return next();
  } catch (error) {
    return res.status(401).json({ message: "Invalid or expired token" });
  }
};
