module.exports = (req, res, next) => {
  const role = req.headers["role"]; // admin / driver / student

  if (!role) {
    return res.status(401).json({ message: "Role missing" });
  }

  req.role = role;
  next();
};
